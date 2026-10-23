/// EdgeOne Makers Blob 客户端（腾讯云 COS 协议 + STS 临时凭证）。
///
/// 协议来源：@edgeone/pages-blob@0.0.18 发布产物逆向，
/// 关键点：
/// 1. `POST https://blob-sts.edgeone.site/` 用 API Token 换临时凭证（12 小时有效）。
/// 2. 对象读写走 `https://{子域}.blob.edgeone.site`（最终一致）
///    或 `https://{子域}.blob-nocache.edgeone.site`（强一致）。
/// 3. 鉴权为 COS 签名 v1：HMAC-SHA1(secretKey, keyTime) 再
///    HMAC-SHA1(上一步, "sha1\n{keyTime}\n{SHA1(httpString)}\n")。
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// 临时凭证。
class BlobCredential {
  BlobCredential({
    required this.tmpSecretId,
    required this.tmpSecretKey,
    required this.sessionToken,
    required this.expiredAt,
    this.appId = '',
    this.zoneId = '',
    this.projectId = '',
    this.resourcePrefix = '',
    this.edgeRegion = '',
    this.defaultCacheControl = '',
  });

  final String tmpSecretId;
  final String tmpSecretKey;
  final String sessionToken;
  final DateTime expiredAt;
  final String appId;
  final String zoneId;
  final String projectId;
  final String resourcePrefix;
  final String edgeRegion;
  final String defaultCacheControl;

  /// 剩余不足 5 分钟即视为过期。
  bool get expiring =>
      expiredAt.difference(DateTime.now()).inSeconds < 300;
}

/// 同步异常，[code] 用于界面给中文提示。
class BlobException implements Exception {
  BlobException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'BlobException($code): $message';
}

/// STS 客户端：用 API Token 换临时凭证并缓存。
class StsClient {
  StsClient({
    required this.projectId,
    required this.apiToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const String stsEndpoint = 'https://blob-sts.edgeone.site/';

  final String projectId;
  final String apiToken;
  final http.Client _client;
  BlobCredential? _cached;

  Future<BlobCredential> getCredential({bool force = false}) async {
    final c = _cached;
    if (!force && c != null && !c.expiring) return c;

    // 本地只拦截两种明确错误，其余交给服务端判断。
    // 实测：新版项目 ID 形如 makers-60tcjerf0vgq，
    // 旧版/官方文档示例形如 pages-urtsvuwmfvli，两者都要放行。
    final pid = projectId.trim();
    if (pid.isEmpty) {
      throw BlobException(
        'BAD_PROJECT',
        'projectId 未填写。在 Makers 项目页面看地址栏，\n'
        '形如 makers-60tcjerf0vgq，复制 makers- 开头那一段。',
      );
    }
    if (RegExp(r'^\d+$').hasMatch(pid)) {
      throw BlobException(
        'BAD_PROJECT',
        '你填的 $pid 是腾讯云 APPID（纯数字），不是 projectId。\n'
        'projectId 形如 makers-60tcjerf0vgq，请从项目页面地址栏复制。',
      );
    }

    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final resp = await _client
            .post(
              Uri.parse(stsEndpoint),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiToken',
                'X-Env': 'prod',
              },
              body: jsonEncode({'ProjectId': projectId}),
            )
            .timeout(const Duration(seconds: 20));

        if (resp.statusCode == 413) {
          throw BlobException('QUOTA', '云端存储容量已超限（免费版 1GB）');
        }
        if (resp.statusCode == 429) {
          throw BlobException('RATE_LIMIT', '请求过于频繁，请稍后重试');
        }
        if (resp.statusCode == 401 || resp.statusCode == 403) {
          throw BlobException('AUTH', 'API Token 无效或已过期，请重新创建');
        }
        if (resp.statusCode >= 500) {
          lastError = 'STS 服务异常（${resp.statusCode}）';
          await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }
        if (resp.statusCode != 200) {
          final body = resp.body.length > 200
              ? resp.body.substring(0, 200)
              : resp.body;
          throw BlobException(
            'STS_${resp.statusCode}',
            '凭证交换失败：${resp.statusCode} $body',
          );
        }

        final decoded = jsonDecode(resp.body);
        final map = decoded is Map<String, dynamic>
            ? (decoded['data'] is Map<String, dynamic>
                ? decoded['data'] as Map<String, dynamic>
                : decoded)
            : <String, dynamic>{};

        final code = map['code'];
        if (code != null && code != 0) {
          final msg = (map['msg'] ?? map['message'] ?? '').toString();
          if (msg.toLowerCase().contains('invalid project')) {
            throw BlobException(
              'BAD_PROJECT',
              'projectId 无效（服务端返回 Invalid project）。\n'
              '请确认它形如 makers-60tcjerf0vgq —— 从项目页地址栏复制的那一段。',
            );
          }
          if (msg.toLowerCase().contains('required')) {
            throw BlobException(
              'BAD_PROJECT',
              'projectId 未提供。请先在 Makers 里创建项目并复制项目 ID。',
            );
          }
          throw BlobException(
            'STS_CODE',
            '凭证交换被拒绝（code=$code）：$msg',
          );
        }

        final secretId = (map['tmpSecretId'] ?? '').toString();
        final secretKey = (map['tmpSecretKey'] ?? '').toString();
        final token = (map['sessionToken'] ?? '').toString();
        final expired = map['expiredTime'];
        if (secretId.isEmpty || secretKey.isEmpty || token.isEmpty) {
          throw BlobException('STS_INVALID', '凭证响应缺少必要字段');
        }

        final exp = expired is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (expired.toInt() * 1000),
                isUtc: true,
              )
            : DateTime.now().toUtc().add(const Duration(hours: 1));

        final cred = BlobCredential(
          tmpSecretId: secretId,
          tmpSecretKey: secretKey,
          sessionToken: token,
          expiredAt: exp,
          appId: (map['appId'] ?? '').toString(),
          zoneId: (map['zoneId'] ?? '').toString(),
          projectId: (map['projectId'] ?? '').toString(),
          resourcePrefix: (map['resourcePrefix'] ?? '').toString(),
          edgeRegion: resp.headers['x-edge-region'] ?? '',
          defaultCacheControl: (map['defaultCacheControl'] ?? '').toString(),
        );
        _cached = cred;
        return cred;
      } on BlobException {
        rethrow;
      } catch (e) {
        lastError = e;
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    throw BlobException('NETWORK', '无法连接 EdgeOne（$lastError）');
  }

  void clear() => _cached = null;

  void close() => _client.close();
}

/// COS 签名 v1。
class CosSigner {
  /// 生成 Authorization 头值。
  static String authorization({
    required String method,
    required String path,
    required Map<String, String> query,
    required Map<String, String> headers,
    required String secretId,
    required String secretKey,
    int expireSeconds = 3600,
  }) {
    final start = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final end = start + expireSeconds;
    final keyTime = '$start;$end';

    final signedHeaders = _signable(headers);
    final headerStr = _joinPairs(signedHeaders);
    final queryStr = _joinPairs(_sorted(query));

    final httpString = '${method.toLowerCase()}\n$path\n$queryStr\n$headerStr\n';
    final stringToSign = 'sha1\n$keyTime\n${sha1.convert(utf8.encode(httpString))}\n';
    final signKey = _hmacHex(utf8.encode(secretKey), keyTime);
    final signature = _hmacHex(utf8.encode(signKey), stringToSign);

    final headerList = signedHeaders.map((e) => _enc(e.key)).join(';');
    final paramList = _sorted(query).map((e) => _enc(e.key)).join(';');

    return 'q-sign-algorithm=sha1'
        '&q-ak=$secretId'
        '&q-sign-time=$keyTime'
        '&q-key-time=$keyTime'
        '&q-header-list=$headerList'
        '&q-url-param-list=$paramList'
        '&q-signature=$signature';
  }

  static String _hmacHex(List<int> key, String message) {
    final h = Hmac(sha1, key);
    return h.convert(utf8.encode(message)).toString();
  }

  /// 参与签名的头：白名单 + 全部 x-cos-*，排除 host 与 x-cos-security-token。
  static List<MapEntry<String, String>> _signable(Map<String, String> headers) {
    const whitelist = {
      'cache-control',
      'content-disposition',
      'content-encoding',
      'content-length',
      'content-md5',
      'content-type',
      'expect',
      'expires',
      'if-match',
      'if-modified-since',
      'if-none-match',
      'if-unmodified-since',
      'origin',
      'range',
      'transfer-encoding',
    };
    final out = <MapEntry<String, String>>[];
    headers.forEach((k, v) {
      final key = k.toLowerCase();
      if (key == 'host' || key == 'x-cos-security-token') return;
      if (whitelist.contains(key) || key.startsWith('x-cos-')) {
        out.add(MapEntry(key, v));
      }
    });
    out.sort((a, b) => a.key.compareTo(b.key));
    return out;
  }

  static List<MapEntry<String, String>> _sorted(Map<String, String> m) {
    final list = m.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => MapEntry(e.key.toLowerCase(), e.value))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return list;
  }

  static String _joinPairs(List<MapEntry<String, String>> list) =>
      list.map((e) => '${_enc(e.key)}=${_enc(e.value)}').join('&');

  static String _enc(String s) => Uri.encodeComponent(s);
}

/// 列表项。
class BlobItem {
  BlobItem(this.key, this.etag);
  final String key;
  final String etag;
}

/// 列表结果。
class BlobListResult {
  BlobListResult(this.items, this.prefixes, this.truncated, this.nextMarker);
  final List<BlobItem> items;
  final List<String> prefixes;
  final bool truncated;
  final String nextMarker;
}

/// Blob 客户端。
class BlobClient {
  BlobClient({
    required this.sts,
    required this.storeName,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final StsClient sts;
  final String storeName;
  final http.Client _client;

  bool _closed = false;

  /// 强一致时走 no-cache 域名，避开边缘缓存最长 60 秒旧值。
  Future<String> _baseUrl({required bool strong}) async {
    final c = await sts.getCredential();
    final sub = _subdomain(c);
    if (sub.isEmpty) {
      throw BlobException('NO_DOMAIN', '无法从凭证推导 Blob 域名，请检查 projectId');
    }
    final host = strong ? 'blob-nocache.edgeone.site' : 'blob.edgeone.site';
    return 'https://$sub.$host';
  }

  String _subdomain(BlobCredential c) {
    final parts = <String>[
      if (c.appId.isNotEmpty) c.appId,
      if (c.zoneId.isNotEmpty) c.zoneId,
      if (c.projectId.isNotEmpty) c.projectId,
    ];
    if (parts.length >= 2) return parts.join('-');
    if (c.resourcePrefix.isNotEmpty) {
      final segs = c.resourcePrefix
          .replaceAll(RegExp(r'/?\*$'), '')
          .split('/')
          .where((e) => e.isNotEmpty)
          .toList();
      if (segs.length >= 2) return segs.take(3).join('-');
    }
    return '';
  }

  String _objectPath(BlobCredential c, String key) {
    final prefix = c.resourcePrefix.replaceAll(RegExp(r'/?\*$'), '');
    final p = prefix.isEmpty ? '/$key' : '/$prefix/$key';
    // 保证不以 / 开头重复
    return p.startsWith('//') ? p.substring(1) : p;
  }

  /// 校验 Blob key 约束（非空、不以 / 开头、UTF-8 ≤ 600 字节）。
  static String? validateKey(String key) {
    if (key.isEmpty) return '键不能为空';
    if (key.startsWith('/')) return '键不能以 / 开头';
    if (utf8.encode(key).length > 600) return '键的 UTF-8 长度超过 600 字节';
    return null;
  }

  /// 写入（可要求“键不存在才写入”）。
  Future<bool> put(
    String key,
    List<int> bytes, {
    bool forbidOverwrite = false,
    String? contentType,
    bool gzip = false,
  }) async {
    final err = validateKey(key);
    if (err != null) throw BlobException('BAD_KEY', err);
    final c = await sts.getCredential();

    return _retry(() async {
      final base = await _baseUrl(strong: true);
      final path = _objectPath(c, key);
      final headers = <String, String>{
        'Content-Type': contentType ?? 'application/octet-stream',
        if (gzip) 'Content-Encoding': 'gzip',
        if (forbidOverwrite) 'x-cos-forbid-overwrite': 'true',
      };
      final auth = CosSigner.authorization(
        method: 'PUT',
        path: path,
        query: const {},
        headers: headers,
        secretId: c.tmpSecretId,
        secretKey: c.tmpSecretKey,
      );
      final resp = await _client
          .put(
            Uri.parse('$base${Uri.encodeFull(path)}'),
            headers: {
              ...headers,
              'Authorization': auth,
              'x-cos-security-token': c.sessionToken,
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode == 409 || resp.statusCode == 412) return false;
      if (resp.statusCode >= 200 && resp.statusCode < 300) return true;
      throw BlobException(
        'PUT_${resp.statusCode}',
        '写入失败：${resp.statusCode} ${_brief(resp.body)}',
      );
    });
  }

  /// 读取；不存在返回 null。
  Future<List<int>?> get(String key, {bool strong = true}) async {
    final err = validateKey(key);
    if (err != null) throw BlobException('BAD_KEY', err);

    return _retry(() async {
      final c = await sts.getCredential();
      final base = await _baseUrl(strong: strong);
      final path = _objectPath(c, key);
      final auth = CosSigner.authorization(
        method: 'GET',
        path: path,
        query: const {},
        headers: const {},
        secretId: c.tmpSecretId,
        secretKey: c.tmpSecretKey,
      );
      final resp = await _client.get(
        Uri.parse('$base${Uri.encodeFull(path)}'),
        headers: {
          'Authorization': auth,
          'x-cos-security-token': c.sessionToken,
        },
      ).timeout(const Duration(seconds: 60));
      if (resp.statusCode == 404) return null;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return resp.bodyBytes;
      }
      throw BlobException(
        'GET_${resp.statusCode}',
        '读取失败：${resp.statusCode} ${_brief(resp.body)}',
      );
    });
  }

  Future<Map<String, String>?> head(String key) async {
    return _retry(() async {
      final c = await sts.getCredential();
      final base = await _baseUrl(strong: true);
      final path = _objectPath(c, key);
      final auth = CosSigner.authorization(
        method: 'HEAD',
        path: path,
        query: const {},
        headers: const {},
        secretId: c.tmpSecretId,
        secretKey: c.tmpSecretKey,
      );
      final req = http.Request('HEAD', Uri.parse('$base${Uri.encodeFull(path)}'))
        ..headers['Authorization'] = auth
        ..headers['x-cos-security-token'] = c.sessionToken;
      final streamed = await _client.send(req).timeout(
            const Duration(seconds: 30),
          );
      if (streamed.statusCode == 404) return null;
      return streamed.headers;
    });
  }

  Future<void> delete(String key) async {
    await _retry(() async {
      final c = await sts.getCredential();
      final base = await _baseUrl(strong: true);
      final path = _objectPath(c, key);
      final auth = CosSigner.authorization(
        method: 'DELETE',
        path: path,
        query: const {},
        headers: const {},
        secretId: c.tmpSecretId,
        secretKey: c.tmpSecretKey,
      );
      final resp = await _client.delete(
        Uri.parse('$base${Uri.encodeFull(path)}'),
        headers: {
          'Authorization': auth,
          'x-cos-security-token': c.sessionToken,
        },
      ).timeout(const Duration(seconds: 30));
      if (resp.statusCode == 204 ||
          resp.statusCode == 404 ||
          (resp.statusCode >= 200 && resp.statusCode < 300)) {
        return;
      }
      throw BlobException(
        'DEL_${resp.statusCode}',
        '删除失败：${resp.statusCode} ${_brief(resp.body)}',
      );
    });
  }

  /// 列举。自动翻页由调用方决定（提供 cursor 便于界面显示进度）。
  ///
  /// 注意：COS 的桶级请求（list）签名路径必须是 `/`，
  /// 数据前缀只能放在 `prefix` 查询参数里。
  /// 之前误把前缀当成路径去签名，服务端直接回 403 AccessDenied。
  Future<BlobListResult> list({
    String prefix = '',
    String delimiter = '',
    String marker = '',
    int maxKeys = 1000,
    bool strong = true,
  }) async {
    return _retry(() async {
      final c = await sts.getCredential();
      final base = await _baseUrl(strong: strong);

      // 形如 `{resourcePrefix}/{store}/`
      final storeRoot = '${_objectPath(c, '').replaceAll(RegExp(r'/$'), '')}/';
      final fullPrefix =
          '${storeRoot.replaceFirst(RegExp(r'^/'), '')}$prefix';

      final query = <String, String>{
        'prefix': fullPrefix,
        if (delimiter.isNotEmpty) 'delimiter': delimiter,
        if (marker.isNotEmpty) 'marker': marker,
        'max-keys': maxKeys.toString(),
      };

      final auth = CosSigner.authorization(
        method: 'GET',
        path: '/',
        query: query,
        headers: const {},
        secretId: c.tmpSecretId,
        secretKey: c.tmpSecretKey,
      );

      final qs = query.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final resp = await _client.get(
        Uri.parse('$base/?$qs'),
        headers: {
          'Authorization': auth,
          'x-cos-security-token': c.sessionToken,
        },
      ).timeout(const Duration(seconds: 60));

      if (resp.statusCode == 404) {
        return BlobListResult(const [], const [], false, '');
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw BlobException(
          'LIST_${resp.statusCode}',
          '列举失败：${resp.statusCode} ${_brief(resp.body)}',
        );
      }
      return parseListXml(resp.body, stripPrefix: fullPrefix);
    });
  }

  /// 解析 COS 列举结果 XML。
  static BlobListResult parseListXml(String xml, {String stripPrefix = ''}) {
    final items = <BlobItem>[];
    final prefixes = <String>[];

    XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } catch (_) {
      return BlobListResult(const [], const [], false, '');
    }

    String strip(String key) =>
        key.startsWith(stripPrefix) ? key.substring(stripPrefix.length) : key;

    for (final e in doc.findAllElements('Contents')) {
      final key = e.getElement('Key')?.innerText ?? '';
      final etag = e.getElement('ETag')?.innerText ?? '';
      if (key.isNotEmpty) items.add(BlobItem(strip(key), etag));
    }
    for (final e in doc.findAllElements('CommonPrefixes')) {
      final p = e.getElement('Prefix')?.innerText ?? '';
      if (p.isNotEmpty) prefixes.add(strip(p));
    }
    final truncated =
        (doc.findAllElements('IsTruncated').firstOrNull?.innerText ?? '')
                .toLowerCase() ==
            'true';
    final next = doc.findAllElements('NextMarker').firstOrNull?.innerText ?? '';
    return BlobListResult(items, prefixes, truncated, next);
  }

  /// 列举全部（自动翻页）。
  Future<List<BlobItem>> listAll({String prefix = ''}) async {
    final out = <BlobItem>[];
    var marker = '';
    for (var page = 0; page < 200; page++) {
      final r = await list(prefix: prefix, marker: marker, maxKeys: 1000);
      out.addAll(r.items);
      if (!r.truncated || r.nextMarker.isEmpty) break;
      marker = r.nextMarker;
    }
    return out;
  }

  Future<T> _retry<T>(Future<T> Function() action) async {
    if (_closed) throw BlobException('CLOSED', '客户端已关闭');
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      sts.clear();
      try {
        return await action();
      } on BlobException {
        rethrow;
      } catch (e) {
        last = e;
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    throw BlobException('NETWORK', '网络请求失败：$last');
  }

  static String _brief(String s) {
    final t = s.replaceAll('\n', ' ').trim();
    return t.length > 160 ? t.substring(0, 160) : t;
  }

  void close() {
    _closed = true;
    _client.close();
  }
}

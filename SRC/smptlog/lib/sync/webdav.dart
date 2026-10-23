/// 坚果云 / 通用 WebDAV 客户端。
///
/// 坚果云配置：
/// - 地址：https://dav.jianguoyun.com/dav/
/// - 用户名：注册邮箱
/// - 密码：**应用密码**（网页端 设置 → 安全选项 → 第三方应用管理 里生成），
///   不是登录密码。
///
/// 注意：坚果云免费版为上传 1GB/月、下载 3GB/月，且有请求频率限制，
/// 因此同步只传增量，不做全量重传。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class WebDavException implements Exception {
  WebDavException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'WebDavException($code): $message';
}

/// PROPFIND 返回的条目。
class WebDavEntry {
  WebDavEntry(this.name, this.isDir);
  final String name;
  final bool isDir;
}

class WebDavClient {
  WebDavClient({
    required String baseUrl,
    required this.username,
    required this.password,
    http.Client? client,
  })  : baseUrl = baseUrl.trim().endsWith('/')
            ? baseUrl.trim()
            : '${baseUrl.trim()}/',
        _client = client ?? http.Client();

  final String baseUrl;
  final String username;
  final String password;
  final http.Client _client;

  String get _auth =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  Uri _uri(String path) {
    final p = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$baseUrl${Uri.encodeFull(p)}');
  }

  Map<String, String> get _headers => {
        'Authorization': _auth,
        'User-Agent': 'SMPTLOG/1.0',
      };

  /// 连通性测试：对根目录做 Depth:0 的 PROPFIND。
  Future<String> test() async {
    final resp = await _client
        .send(http.Request('PROPFIND', _uri(''))
          ..headers.addAll({..._headers, 'Depth': '0'}))
        .timeout(const Duration(seconds: 20));
    await resp.stream.drain<void>();
    if (resp.statusCode == 401) {
      throw WebDavException('AUTH', '用户名或应用密码不正确');
    }
    if (resp.statusCode == 404) {
      throw WebDavException('NOT_FOUND', '地址不对，坚果云应为 https://dav.jianguoyun.com/dav/');
    }
    if (resp.statusCode >= 200 && resp.statusCode < 300 ||
        resp.statusCode == 207) {
      return '连接成功（${Uri.parse(baseUrl).host}）';
    }
    throw WebDavException(
      'HTTP_${resp.statusCode}',
      '连接失败：${resp.statusCode}',
    );
  }

  /// 逐级创建目录（已存在返回 405，视为成功）。
  Future<void> ensureDir(String dirPath) async {
    final parts = dirPath.split('/').where((e) => e.isNotEmpty).toList();
    var current = '';
    for (final p in parts) {
      current = current.isEmpty ? p : '$current/$p';
      final resp = await _client.send(
        http.Request('MKCOL', _uri(current))..headers.addAll(_headers),
      ).timeout(const Duration(seconds: 20));
      await resp.stream.drain<void>();
      if (resp.statusCode == 201 ||
          resp.statusCode == 405 ||
          resp.statusCode == 301) {
        continue;
      }
      throw WebDavException(
        'MKCOL_${resp.statusCode}',
        '创建目录失败：$current（${resp.statusCode}）',
      );
    }
  }

  Future<bool> put(String path, List<int> bytes) async {
    final dir = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/'))
        : '';
    if (dir.isNotEmpty) await ensureDir(dir);

    final resp = await _client.put(
      _uri(path),
      headers: {..._headers, 'Content-Type': 'application/octet-stream'},
      body: bytes,
    ).timeout(const Duration(seconds: 90));

    if (resp.statusCode >= 200 && resp.statusCode < 300) return true;
    if (resp.statusCode == 507) {
      throw WebDavException('QUOTA', '坚果云空间或流量已用尽');
    }
    throw WebDavException(
      'PUT_${resp.statusCode}',
      '上传失败：${resp.statusCode} ${_brief(resp.body)}',
    );
  }

  Future<List<int>?> get(String path) async {
    final resp = await _client
        .get(_uri(path), headers: _headers)
        .timeout(const Duration(seconds: 90));
    if (resp.statusCode == 404) return null;
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return resp.bodyBytes;
    }
    if (resp.statusCode == 401) {
      throw WebDavException('AUTH', '用户名或应用密码不正确');
    }
    throw WebDavException(
      'GET_${resp.statusCode}',
      '下载失败：${resp.statusCode}',
    );
  }

  Future<void> delete(String path) async {
    final resp = await _client
        .delete(_uri(path), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode == 204 ||
        resp.statusCode == 200 ||
        resp.statusCode == 404) {
      return;
    }
    throw WebDavException(
      'DEL_${resp.statusCode}',
      '删除失败：${resp.statusCode}',
    );
  }

  /// 列出某目录下的直接子项。
  Future<List<WebDavEntry>> list(String dirPath, {int depth = 1}) async {
    final normalized =
        dirPath.isEmpty ? '' : (dirPath.endsWith('/') ? dirPath : '$dirPath/');
    final resp = await _client
        .send(http.Request('PROPFIND', _uri(normalized))
          ..headers.addAll({..._headers, 'Depth': '$depth'}))
        .timeout(const Duration(seconds: 60));
    final body = await resp.stream.bytesToString();

    if (resp.statusCode == 404) return const [];
    if (resp.statusCode == 401) {
      throw WebDavException('AUTH', '用户名或应用密码不正确');
    }
    if (resp.statusCode != 207 &&
        !(resp.statusCode >= 200 && resp.statusCode < 300)) {
      throw WebDavException(
        'PROPFIND_${resp.statusCode}',
        '列举失败：${resp.statusCode}',
      );
    }

    final entries = <WebDavEntry>[];
    XmlDocument doc;
    try {
      doc = XmlDocument.parse(body);
    } catch (_) {
      return entries;
    }

    // 只取本地名，忽略命名空间前缀差异
    String local(XmlElement e) => e.name.local;

    final basePath = Uri.parse(baseUrl).path;
    final selfPath = '$basePath${normalized.replaceFirst(RegExp(r'^/'), '')}';

    for (final node in doc.descendants.whereType<XmlElement>()) {
      if (local(node) != 'response') continue;

      String? href;
      var isDir = false;
      for (final child in node.descendants.whereType<XmlElement>()) {
        if (local(child) == 'href') href = child.innerText.trim();
        if (local(child) == 'collection') isDir = true;
      }
      if (href == null || href.isEmpty) continue;

      var path = href;
      try {
        path = Uri.decodeFull(Uri.parse(href).path);
      } catch (_) {}
      if (path == selfPath || '$path/' == selfPath) continue;

      final name = path.endsWith('/')
          ? path.substring(0, path.length - 1).split('/').last
          : path.split('/').last;
      if (name.isEmpty) continue;
      entries.add(WebDavEntry(name, isDir));
    }
    return entries;
  }

  /// 递归列出所有文件（相对指定前缀的完整相对路径）。
  Future<List<String>> listFiles(String prefix) async {
    final out = <String>[];
    await _walk(prefix, out, 0);
    return out;
  }

  Future<void> _walk(String dir, List<String> out, int depth) async {
    if (depth > 6) return;
    final entries = await list(dir);
    for (final e in entries) {
      final childPath = dir.endsWith('/') ? '$dir${e.name}' : '$dir/${e.name}';
      if (e.isDir) {
        await _walk('$childPath/', out, depth + 1);
      } else {
        out.add(childPath);
      }
    }
  }

  /// 列出某个父目录下的直接子目录名。
  Future<List<String>> listDirs(String prefix) async {
    final entries = await list(prefix);
    return entries.where((e) => e.isDir).map((e) => e.name).toList();
  }

  static String _brief(String s) {
    final t = s.replaceAll('\n', ' ').trim();
    return t.length > 140 ? t.substring(0, 140) : t;
  }

  void close() => _client.close();
}

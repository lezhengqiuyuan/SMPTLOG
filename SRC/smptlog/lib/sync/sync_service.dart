/// 同步编排：后端可插拔（EdgeOne Blob / 坚果云 WebDAV）。
///
/// 云端布局（两种后端一致）：
/// ```
/// qso/dev/{deviceId}/meta
/// qso/dev/{deviceId}/shard/{yyyyMM}/{seq}
/// qso/dev/{deviceId}/oplog/{ts}
/// ```
/// 为什么不用全局 manifest：EdgeOne Blob 只提供「禁止覆盖已存在键」，
/// 没有 If-Match 条件写，无法做 CAS；而「每设备只写自己前缀」天然无写冲突。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/db.dart';
import '../core/models.dart';
import 'cos.dart';
import 'secure.dart';
import 'webdav.dart';

/// 同步后端类型。三者互斥：关闭 / EdgeOne / 坚果云。
class SyncBackendType {
  static const off = 'off';
  static const edgeone = 'edgeone';
  static const webdav = 'webdav';

  static const all = <String>[off, edgeone, webdav];

  static String label(String v) {
    switch (v) {
      case webdav:
        return '坚果云';
      case edgeone:
        return 'EdgeOne Blob';
      default:
        return '关闭';
    }
  }
}

enum SyncPhase {
  idle,
  discovering,
  pulling,
  merging,
  pushing,
  compacting,
  done,
  failed,
}

class SyncProgress {
  SyncProgress(this.phase, this.message, {this.current = 0, this.total = 0});
  final SyncPhase phase;
  final String message;
  final int current;
  final int total;

  double get ratio => total <= 0 ? 0 : (current / total).clamp(0.0, 1.0);
}

/// 同步配置。凭据只存本机（DPAPI / Keystore），不进数据库。
class SyncConfig {
  SyncConfig({
    required this.backend,
    this.projectId = '',
    this.apiToken = '',
    this.davUrl = '',
    this.davUser = '',
    this.davPassword = '',
    this.davRoot = 'SMPTLOG',
    required this.deviceId,
    this.encryptionEnabled = false,
    this.encryptionKey,
    this.encryptionSalt,
  });

  final String backend;
  final String projectId;
  final String apiToken;
  final String davUrl;
  final String davUser;
  final String davPassword;
  final String davRoot;
  final String deviceId;
  final bool encryptionEnabled;
  final Uint8List? encryptionKey;
  final Uint8List? encryptionSalt;

  bool get isWebDav => backend == SyncBackendType.webdav;

  bool get isOff => backend == SyncBackendType.off;

  bool get isConfigured {
    if (isOff) return false;
    return isWebDav
        ? davUrl.trim().isNotEmpty &&
            davUser.trim().isNotEmpty &&
            davPassword.trim().isNotEmpty
        : projectId.trim().isNotEmpty && apiToken.trim().isNotEmpty;
  }

  static Future<SyncConfig> load() async {
    final m = await SecretsVault.read();
    final key = (m['syncKey'] ?? '').toString();
    final salt = (m['syncSalt'] ?? '').toString();
    final backend = (m['backend'] ?? SyncBackendType.edgeone).toString();
    return SyncConfig(
      backend: backend,
      projectId: (m['projectId'] ?? '').toString(),
      apiToken: (m['apiToken'] ?? '').toString(),
      davUrl: (m['davUrl'] ?? 'https://dav.jianguoyun.com/dav/').toString(),
      davUser: (m['davUser'] ?? '').toString(),
      davPassword: (m['davPassword'] ?? '').toString(),
      davRoot: (m['davRoot'] ?? 'SMPTLOG').toString(),
      deviceId: (m['deviceId'] ?? '').toString(),
      encryptionEnabled: (m['encryptionEnabled'] ?? false) == true,
      encryptionKey: key.isEmpty ? null : base64Decode(key),
      encryptionSalt: salt.isEmpty ? null : base64Decode(salt),
    );
  }
}

// ---------------------------------------------------------------- 后端抽象

abstract class SyncBackend {
  Future<String> test();
  Future<void> put(String key, List<int> bytes);
  Future<List<int>?> get(String key);
  Future<void> delete(String key);

  /// 返回该前缀下的直接子目录名。
  Future<List<String>> listDirs(String prefix);

  /// 返回该前缀下的全部文件键（含前缀）。
  Future<List<String>> listFiles(String prefix);

  void close();
}

class BlobBackend implements SyncBackend {
  BlobBackend(this.client);
  final BlobClient client;

  @override
  Future<String> test() async {
    final cred = await client.sts.getCredential(force: true);
    await client.list(prefix: 'qso/dev/', maxKeys: 10);
    final region = cred.edgeRegion.isEmpty ? '未知' : cred.edgeRegion;
    return '连接成功（区域：$region）';
  }

  @override
  Future<void> put(String key, List<int> bytes) =>
      client.put(key, bytes, contentType: 'application/octet-stream');

  @override
  Future<List<int>?> get(String key) => client.get(key, strong: true);

  @override
  Future<void> delete(String key) => client.delete(key);

  @override
  Future<List<String>> listDirs(String prefix) async {
    final r = await client.list(prefix: prefix, delimiter: '/');
    return r.prefixes
        .map((p) => p.endsWith('/') ? p.substring(0, p.length - 1) : p)
        .map((p) => p.split('/').last)
        .where((e) => e.isNotEmpty)
        .toList();
  }

  @override
  Future<List<String>> listFiles(String prefix) async {
    final items = await client.listAll(prefix: prefix);
    return items.map((e) => '$prefix${e.key}').toList();
  }

  @override
  void close() => client.close();
}

class WebDavBackend implements SyncBackend {
  WebDavBackend(this.client, this.root);

  final WebDavClient client;
  final String root;

  String _full(String key) {
    final r = root.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final k = key.replaceFirst(RegExp(r'^/+'), '');
    return r.isEmpty ? k : '$r/$k';
  }

  String _strip(String full) {
    final r = root.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    if (r.isEmpty) return full;
    return full.startsWith('$r/') ? full.substring(r.length + 1) : full;
  }

  @override
  Future<String> test() => client.test();

  @override
  Future<void> put(String key, List<int> bytes) async {
    await client.put(_full(key), bytes);
  }

  @override
  Future<List<int>?> get(String key) => client.get(_full(key));

  @override
  Future<void> delete(String key) => client.delete(_full(key));

  @override
  Future<List<String>> listDirs(String prefix) => client.listDirs(_full(prefix));

  @override
  Future<List<String>> listFiles(String prefix) async {
    final files = await client.listFiles(_full(prefix));
    return files.map(_strip).toList();
  }

  @override
  void close() => client.close();
}

// ------------------------------------------------------------------ 元数据

class _DeviceMeta {
  _DeviceMeta({
    required this.deviceId,
    required this.rev,
    required this.count,
    required this.updatedAt,
    required this.shards,
  });

  final String deviceId;
  final int rev;
  final int count;
  final DateTime updatedAt;
  final List<String> shards;

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'rev': rev,
        'count': count,
        'updated_at': updatedAt.toUtc().millisecondsSinceEpoch,
        'shards': shards,
      };

  static _DeviceMeta fromJson(Map<String, dynamic> j) => _DeviceMeta(
        deviceId: (j['device_id'] ?? '').toString(),
        rev: (j['rev'] as num?)?.toInt() ?? 0,
        count: (j['count'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (j['updated_at'] as num?)?.toInt() ?? 0,
          isUtc: true,
        ),
        shards: (j['shards'] is List)
            ? (j['shards'] as List).map((e) => e.toString()).toList()
            : <String>[],
      );
}

// ------------------------------------------------------------------ 服务

class SyncService {
  SyncService(this.db);

  static const String storeName = 'smptlog';
  static const int shardSize = 500;

  final AppDb db;

  SyncBackend? _backend;
  String _deviceId = '';

  SyncBackend _makeBackend(SyncConfig cfg) {
    if (cfg.isOff) {
      throw BlobException('SYNC_OFF', '云同步已关闭（仅本地模式）');
    }
    if (cfg.isWebDav) {
      return WebDavBackend(
        WebDavClient(
          baseUrl: cfg.davUrl,
          username: cfg.davUser,
          password: cfg.davPassword,
        ),
        cfg.davRoot,
      );
    }
    return BlobBackend(
      BlobClient(
        sts: StsClient(projectId: cfg.projectId, apiToken: cfg.apiToken),
        storeName: storeName,
      ),
    );
  }

  void _ensureBackend(SyncConfig cfg) {
    _deviceId = cfg.deviceId;
    _backend ??= _makeBackend(cfg);
  }

  void resetClient() {
    _backend?.close();
    _backend = null;
  }

  /// 连通性测试（不写入任何数据）。
  Future<String> testConnection(SyncConfig cfg) async {
    final backend = _makeBackend(cfg);
    try {
      return await backend.test();
    } on BlobException catch (e) {
      throw BlobException(e.code, e.message);
    } on WebDavException catch (e) {
      throw BlobException(e.code, e.message);
    } finally {
      backend.close();
    }
  }

  Future<void> sync(
    SyncConfig cfg, {
    void Function(SyncProgress)? onProgress,
  }) async {
    if (!cfg.isConfigured) {
      throw BlobException('NOT_CONFIGURED', '尚未填写同步配置');
    }
    _ensureBackend(cfg);

    const datasets = <String>['qso', 'repeater', 'station'];

    onProgress?.call(SyncProgress(SyncPhase.discovering, '正在发现其他设备…'));

    final devices = <String, Set<String>>{};
    for (final ds in datasets) {
      final dirs = await _backend!.listDirs('$ds/dev/');
      devices[ds] = dirs.where((e) => e.isNotEmpty).toSet();
    }

    var pulled = 0;
    for (final ds in datasets) {
      for (final id in devices[ds] ?? <String>{}) {
        onProgress?.call(SyncProgress(
          SyncPhase.pulling,
          '正在读取设备 ${id.length > 6 ? id.substring(0, 6) : id}…',
        ));
        pulled += await _pullDevice(ds, id, cfg);
      }
    }

    onProgress?.call(SyncProgress(SyncPhase.merging, '合并完成，共 $pulled 条更新'));

    for (final ds in datasets) {
      onProgress?.call(SyncProgress(SyncPhase.pushing, '正在上传本地变更（$ds）…'));
      await _pushDataset(ds, cfg);
    }

    for (final ds in datasets) {
      onProgress?.call(SyncProgress(SyncPhase.compacting, '正在整理云端分片（$ds）…'));
      await _compact(ds, cfg);
    }

    db.kvSet(
      'last_sync_at',
      DateTime.now().toUtc().millisecondsSinceEpoch.toString(),
    );
    onProgress?.call(SyncProgress(SyncPhase.done, '同步完成'));
  }

  String _metaKey(String ds, String deviceId) => '$ds/dev/$deviceId/meta';

  Future<int> _pullDevice(String ds, String deviceId, SyncConfig cfg) async {
    final metaBytes = await _backend!.get(_metaKey(ds, deviceId));
    if (metaBytes == null) return 0;

    final meta = _DeviceMeta.fromJson(
      jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>,
    );

    final seenKey = 'seen_${ds}_$deviceId';
    final seenRev = int.tryParse(db.kvGet(seenKey) ?? '0') ?? 0;
    if (meta.rev <= seenRev && meta.shards.isEmpty) return 0;

    var applied = 0;

    for (final prefix in [
      '$ds/dev/$deviceId/oplog/',
      '$ds/dev/$deviceId/shard/',
    ]) {
      final keys = await _backend!.listFiles(prefix);
      for (final key in keys) {
        if (db.kvGet('${seenKey}_$key') == '1') continue;
        final bytes = await _backend!.get(key);
        if (bytes == null) continue;
        applied += _applyPayload(ds, _decode(bytes, cfg), deviceId);
        db.kvSet('${seenKey}_$key', '1');
      }
    }

    db.kvSet(seenKey, meta.rev.toString());
    return applied;
  }

  List<Map<String, dynamic>> _decode(List<int> bytes, SyncConfig cfg) {
    var raw = bytes;
    if (raw.length > 2 && raw[0] == 0x1f && raw[1] == 0x8b) {
      raw = gzip.decode(raw);
    }
    if (cfg.encryptionEnabled) {
      final key = cfg.encryptionKey;
      if (key == null) {
        throw BlobException('NO_KEY', '已开启端到端加密，但本地缺少密钥，请重新输入密码');
      }
      if (raw.length > 32 && raw[0] == 0x53 && raw[1] == 0x4c) {
        final iv = raw.sublist(20, 32);
        final body = raw.sublist(32);
        raw = CipherBox.decryptWithKey(key, iv, body);
      }
    }
    final list = jsonDecode(utf8.decode(raw));
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (list is Map<String, dynamic>) {
      final items = list['items'];
      if (items is List) {
        return items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return <Map<String, dynamic>>[];
  }

  Uint8List _encode(List<Map<String, dynamic>> items, SyncConfig cfg) {
    var raw = utf8.encode(jsonEncode(items));
    if (cfg.encryptionEnabled) {
      final key = cfg.encryptionKey;
      final salt = cfg.encryptionSalt;
      if (key == null || salt == null) {
        throw BlobException('NO_KEY', '开启端到端加密时必须先设置密码');
      }
      raw = CipherBox.encryptWithKey(key, salt, raw);
    }
    return Uint8List.fromList(gzip.encode(raw));
  }

  int _applyPayload(
    String ds,
    List<Map<String, dynamic>> items,
    String sourceDevice,
  ) {
    var n = 0;
    for (final j in items) {
      if (ds == 'qso') {
        n += _mergeQso(Qso.fromJson(j), sourceDevice) ? 1 : 0;
      } else if (ds == 'repeater') {
        n += _mergeRepeater(Repeater.fromJson(j), sourceDevice) ? 1 : 0;
      } else {
        n += _mergeStation(StationProfile.fromJson(j), sourceDevice) ? 1 : 0;
      }
    }
    return n;
  }

  bool _mergeQso(Qso remote, String sourceDevice) {
    final local = db.getQsoIncludeDeleted(remote.uuid);
    if (local == null) {
      db.upsertQso(remote, log: false);
      return true;
    }
    if (remote.updatedAt.isAfter(local.updatedAt)) {
      if (!local.deleted) {
        db.addConflict(
          dataset: 'qso',
          uuid: local.uuid,
          loser: local.toJson(),
          winnerUpdatedAt: remote.updatedAt,
          loserUpdatedAt: local.updatedAt,
          sourceDevice: sourceDevice,
        );
      }
      db.upsertQso(remote, log: false);
      return true;
    }
    return false;
  }

  bool _mergeRepeater(Repeater remote, String sourceDevice) {
    final local = db.getRepeater(remote.id);
    if (local == null) {
      db.upsertRepeater(remote, log: false);
      return true;
    }
    if (remote.updatedAt.isAfter(local.updatedAt)) {
      db.addConflict(
        dataset: 'repeater',
        uuid: local.id,
        loser: local.toJson(),
        winnerUpdatedAt: remote.updatedAt,
        loserUpdatedAt: local.updatedAt,
        sourceDevice: sourceDevice,
      );
      db.upsertRepeater(remote, log: false);
      return true;
    }
    return false;
  }

  bool _mergeStation(StationProfile remote, String sourceDevice) {
    StationProfile? local;
    for (final s in db.allStations()) {
      if (s.id == remote.id) {
        local = s;
        break;
      }
    }
    if (local == null) {
      db.upsertStation(remote, log: false);
      return true;
    }
    if (remote.updatedAt.isAfter(local.updatedAt)) {
      db.upsertStation(remote, log: false);
      return true;
    }
    return false;
  }

  Future<void> _pushDataset(String ds, SyncConfig cfg) async {
    final entries = db.oplogEntries(ds);
    if (entries.isEmpty) return;

    final ts = DateTime.now().toUtc().millisecondsSinceEpoch;
    final key = '$ds/dev/$_deviceId/oplog/$ts';

    final payload = entries
        .map((e) => jsonDecode(e['payload'] as String) as Map<String, dynamic>)
        .toList();

    await _backend!.put(key, _encode(payload, cfg));

    final maxSeq =
        entries.map((e) => e['seq'] as int).reduce((a, b) => a > b ? a : b);
    // 先写 meta 再清 oplog：若 meta 写失败，oplog 仍在，下次还能重传；
    // 反过来（先清后写）一旦 meta 失败，数据就永久丢了。
    await _writeMeta(ds, cfg);
    db.clearOplogUpTo(ds, maxSeq);
  }

  Future<void> _writeMeta(String ds, SyncConfig cfg) async {
    final meta = _DeviceMeta(
      deviceId: _deviceId,
      rev: db.localRev(ds),
      count: db.oplogCount(ds),
      updatedAt: DateTime.now().toUtc(),
      shards: const [],
    );
    await _backend!.put(
      _metaKey(ds, _deviceId),
      utf8.encode(jsonEncode(meta.toJson())),
    );
  }

  Future<void> _compact(String ds, SyncConfig cfg) async {
    if (db.oplogCount(ds) < shardSize) return;

    final entries = db.oplogEntries(ds, limit: 5000);
    if (entries.isEmpty) return;

    final payload = entries
        .map((e) => jsonDecode(e['payload'] as String) as Map<String, dynamic>)
        .toList();

    final now = DateTime.now().toUtc();
    final ym = '${now.year}${now.month.toString().padLeft(2, '0')}';
    final key = '$ds/dev/$_deviceId/shard/$ym/${now.millisecondsSinceEpoch}';

    await _backend!.put(key, _encode(payload, cfg));

    final maxSeq =
        entries.map((e) => e['seq'] as int).reduce((a, b) => a > b ? a : b);
    await _writeMeta(ds, cfg);
    db.clearOplogUpTo(ds, maxSeq);
  }

  void restoreConflict(ConflictEntry c) {
    if (c.dataset == 'qso') {
      db.upsertQso(Qso.fromJson(c.loserJson).copyWith(
        updatedAt: DateTime.now().toUtc(),
        deleted: false,
      ));
    } else if (c.dataset == 'repeater') {
      db.upsertRepeater(Repeater.fromJson(c.loserJson).copyWith(
        updatedAt: DateTime.now().toUtc(),
        deleted: false,
      ));
    }
    db.removeConflict(c.id);
  }

  DateTime? get lastSyncAt {
    final raw = db.kvGet('last_sync_at');
    if (raw == null) return null;
    final ms = int.tryParse(raw);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
}

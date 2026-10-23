/// 全局状态控制器（provider + ChangeNotifier）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'core/adif.dart';
import 'core/backup.dart';
import 'core/db.dart';
import 'core/models.dart';
import 'core/util.dart';
import 'sync/cos.dart';
import 'sync/secure.dart';
import 'sync/sync_service.dart';

/// 应用级设置（只存非敏感项）。
class AppSettings {
  AppSettings({
    this.themeMode = ThemeMode.system,
    this.adifFreqPolicy = 'down',
    this.dupWindowMinutes = 5,
    this.freqPolicyAsk = false,
  });

  final ThemeMode themeMode;
  final String adifFreqPolicy; // down / up
  final int dupWindowMinutes;
  final bool freqPolicyAsk;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? adifFreqPolicy,
    int? dupWindowMinutes,
    bool? freqPolicyAsk,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        adifFreqPolicy: adifFreqPolicy ?? this.adifFreqPolicy,
        dupWindowMinutes: dupWindowMinutes ?? this.dupWindowMinutes,
        freqPolicyAsk: freqPolicyAsk ?? this.freqPolicyAsk,
      );

  Map<String, dynamic> toJson() => {
        'theme': themeMode.name,
        'adif_freq_policy': adifFreqPolicy,
        'dup_window': dupWindowMinutes,
        'freq_policy_ask': freqPolicyAsk,
      };

  static AppSettings fromJson(Map<String, dynamic> j) => AppSettings(
        themeMode: ThemeMode.values.firstWhere(
          (e) => e.name == (j['theme'] ?? 'system'),
          orElse: () => ThemeMode.system,
        ),
        adifFreqPolicy: (j['adif_freq_policy'] ?? 'down').toString(),
        dupWindowMinutes: (j['dup_window'] as num?)?.toInt() ?? 5,
        freqPolicyAsk: (j['freq_policy_ask'] ?? false) == true,
      );
}

/// 全局状态。
class AppState extends ChangeNotifier {
  AppState(this.db);

  final AppDb db;

  AppSettings settings = AppSettings();
  String deviceId = '';

  /// 默认中继台（打开「通过中继」时自动带入）
  String defaultRepeaterId = '';

  // 同步状态
  bool syncConfigured = false;
  String syncBackend = SyncBackendType.edgeone;
  bool encryptionEnabled = false;
  String syncMessage = '';
  bool syncing = false;
  double syncRatio = 0;
  DateTime? lastSyncAt;
  int conflictCount = 0;

  // 列表状态
  QsoFilter filter = const QsoFilter();
  List<Qso> qsos = [];
  int totalCount = 0;
  bool loading = false;
  bool hasMore = false;
  Set<String> selected = {};

  // 重复检测缓存
  Set<String> dupUuids = {};

  late SyncService syncService;

  Future<void> init() async {
    syncService = SyncService(db);

    final raw = db.kvGet('settings');
    if (raw != null && raw.isNotEmpty) {
      try {
        settings = AppSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {}
    }

    final secrets = await SecretsVault.read();
    deviceId = (secrets['deviceId'] ?? '').toString();
    if (deviceId.isEmpty) {
      deviceId = IdGen.short();
      secrets['deviceId'] = deviceId;
      await SecretsVault.write(secrets);
    }

    syncBackend = (secrets['backend'] ?? SyncBackendType.edgeone).toString();
    syncConfigured = _isConfigured(secrets);
    encryptionEnabled = (secrets['encryptionEnabled'] ?? false) == true;

    lastSyncAt = syncService.lastSyncAt;
    conflictCount = db.conflictCount;
    defaultRepeaterId = db.kvGet('default_repeater_id') ?? '';

    await reload();
  }

  // ------------------------------------------------------------- 列表

  Future<void> reload() async {
    loading = true;
    notifyListeners();
    totalCount = db.countQsos(filter);
    qsos = db.queryQsos(filter, limit: 200);
    hasMore = qsos.length < totalCount;
    await refreshDupFlags();
    loading = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (!hasMore || qsos.isEmpty) return;
    final last = qsos.last;
    final more = db.queryQsos(
      filter,
      limit: 200,
      cursor: (
        timeMs: last.qsoTimeUtc.millisecondsSinceEpoch,
        uuid: last.uuid,
      ),
    );
    if (more.isEmpty) {
      hasMore = false;
    } else {
      qsos = [...qsos, ...more];
      hasMore = qsos.length < totalCount;
    }
    notifyListeners();
  }

  void setFilter(QsoFilter f) {
    filter = f;
    selected = {};
    reload();
  }

  void toggleSelect(String uuid) {
    if (selected.contains(uuid)) {
      selected.remove(uuid);
    } else {
      selected.add(uuid);
    }
    notifyListeners();
  }

  void clearSelection() {
    selected = {};
    notifyListeners();
  }

  Future<void> refreshDupFlags() async {
    if (settings.dupWindowMinutes <= 0) {
      dupUuids = {};
      return;
    }
    final flags = <String>{};
    final seen = <String, List<Qso>>{};
    for (final q in qsos) {
      final k = DupDetector.key(call: q.call, band: q.band, mode: q.mode);
      final list = seen.putIfAbsent(k, () => []);
      for (final other in list) {
        if (DupDetector.isDup(
          a: q.qsoTimeUtc,
          b: other.qsoTimeUtc,
          windowMinutes: settings.dupWindowMinutes,
        )) {
          flags.add(q.uuid);
          flags.add(other.uuid);
        }
      }
      list.add(q);
    }
    dupUuids = flags;
  }

  // ------------------------------------------------------------- 写操作

  Future<void> saveQso(Qso q, {bool touchRepeater = true}) async {
    final existing = db.getQsoIncludeDeleted(q.uuid);
    final isNew = existing == null;
    db.upsertQso(q.copyWith(deviceId: deviceId));
    if (isNew && q.repeaterId.isNotEmpty && touchRepeater) {
      db.touchRepeater(q.repeaterId);
    }
    await reload();
    notifyListeners();
  }

  Future<void> deleteQso(String uuid) async {
    db.deleteQso(uuid, deviceId: deviceId);
    await reload();
  }

  Future<void> deleteSelected() async {
    for (final id in selected) {
      db.deleteQso(id, deviceId: deviceId);
    }
    selected = {};
    await reload();
  }

  Future<void> setQslForSelected(int status) async {
    db.bulkUpdateQsl(selected.toList(), status, deviceId: deviceId);
    selected = {};
    await reload();
  }

  // ------------------------------------------------------------- 设置

  /// 设置 / 取消默认中继台（传空字符串为取消）。
  Future<void> setDefaultRepeater(String id) async {
    defaultRepeaterId = id;
    db.kvSet('default_repeater_id', id);
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings s) async {
    settings = s;
    db.kvSet('settings', jsonEncode(s.toJson()));
    notifyListeners();
  }

  // ------------------------------------------------------------- 同步

  Future<void> reloadSecrets() async {
    final secrets = await SecretsVault.read();
    syncBackend = (secrets['backend'] ?? SyncBackendType.edgeone).toString();
    syncConfigured = _isConfigured(secrets);
    encryptionEnabled = (secrets['encryptionEnabled'] ?? false) == true;
    notifyListeners();
  }

  bool _isConfigured(Map<String, dynamic> s) {
    final backend = (s['backend'] ?? SyncBackendType.edgeone).toString();
    if (backend == SyncBackendType.off) return false;
    if (backend == SyncBackendType.webdav) {
      return (s['davUrl'] ?? '').toString().isNotEmpty &&
          (s['davUser'] ?? '').toString().isNotEmpty &&
          (s['davPassword'] ?? '').toString().isNotEmpty;
    }
    return (s['projectId'] ?? '').toString().isNotEmpty &&
        (s['apiToken'] ?? '').toString().isNotEmpty;
  }

  Future<String> testSync({
    required String backend,
    String projectId = '',
    String token = '',
    String davUrl = '',
    String davUser = '',
    String davPassword = '',
  }) async {
    final cfg = SyncConfig(
      backend: backend,
      projectId: projectId,
      apiToken: token,
      davUrl: davUrl,
      davUser: davUser,
      davPassword: davPassword,
      deviceId: deviceId,
    );
    return syncService.testConnection(cfg);
  }

  Future<void> saveSyncConfig({
    required String backend,
    String projectId = '',
    String token = '',
    String davUrl = '',
    String davUser = '',
    String davPassword = '',
  }) async {
    final secrets = await SecretsVault.read();
    secrets['backend'] = backend;
    secrets['projectId'] = projectId;
    secrets['apiToken'] = token;
    secrets['davUrl'] = davUrl;
    secrets['davUser'] = davUser;
    secrets['davPassword'] = davPassword;
    await SecretsVault.write(secrets);
    syncService.resetClient();
    await reloadSecrets();
  }

  /// 开启/关闭端到端加密。开启需要密码。
  Future<void> configureEncryption(String? password) async {
    final secrets = await SecretsVault.read();
    if (password == null || password.isEmpty) {
      secrets['encryptionEnabled'] = false;
      secrets.remove('syncKey');
      secrets.remove('syncSalt');
      await SecretsVault.write(secrets);
      encryptionEnabled = false;
      syncService.resetClient();
      notifyListeners();
      return;
    }
    final derived = CipherBox.deriveKey(password);
    secrets['encryptionEnabled'] = true;
    secrets['syncKey'] = base64Encode(derived.key);
    secrets['syncSalt'] = base64Encode(derived.salt);
    await SecretsVault.write(secrets);
    encryptionEnabled = true;
    syncService.resetClient();
    notifyListeners();
  }

  Future<void> runSync() async {
    if (syncing) return;
    if (syncBackend == SyncBackendType.off) {
      syncMessage = '云同步已关闭（仅本地模式）';
      notifyListeners();
      return;
    }
    syncing = true;
    syncRatio = 0;
    syncMessage = '准备中…';
    notifyListeners();

    try {
      final cfg = await SyncConfig.load();
      await syncService.sync(
        cfg,
        onProgress: (p) {
          syncMessage = p.message;
          syncRatio = p.ratio;
          notifyListeners();
        },
      );
      lastSyncAt = DateTime.now().toUtc();
      conflictCount = db.conflictCount;
      syncMessage = '同步完成';
      await reload();
    } on BlobException catch (e) {
      syncMessage = _humanError(e);
    } catch (e) {
      syncMessage = '同步失败：$e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  String _humanError(BlobException e) {
    switch (e.code) {
      case 'NOT_CONFIGURED':
        return '尚未配置同步';
      case 'SYNC_OFF':
        return '云同步已关闭（仅本地模式）';
      case 'BAD_PROJECT':
        return e.message;
      case 'AUTH':
        return '账号或密码/Token 无效，请重新填写';
      case 'NOT_FOUND':
        return '地址不正确：坚果云应填 https://dav.jianguoyun.com/dav/';
      case 'QUOTA':
        return e.message.contains('坚果云') ? e.message : '云端容量已超限（免费版 1 GB）';
      case 'RATE_LIMIT':
        return '请求过于频繁，请稍后再试';
      case 'NETWORK':
        return '网络不可达，请检查网络连接';
      case 'NO_KEY':
        return '端到端加密密钥缺失，请重新设置同步密码';
      default:
        return e.message;
    }
  }

  Future<void> restoreConflict(ConflictEntry c) async {
    syncService.restoreConflict(c);
    conflictCount = db.conflictCount;
    await reload();
  }

  Future<void> dismissConflict(ConflictEntry c) async {
    db.removeConflict(c.id);
    conflictCount = db.conflictCount;
    notifyListeners();
  }

  // ------------------------------------------------------- 导入导出

  Future<ImportResult> importAdifText(
    String text, {
    DupPolicy policy = DupPolicy.keepAll,
    void Function(int, int)? onProgress,
  }) async {
    final svc = ImportService(db);
    // 大文件解析放到后台 Isolate，避免界面卡死。
    final result = await svc.importAdif(
      text,
      deviceId: deviceId,
      policy: policy,
      windowMinutes: settings.dupWindowMinutes,
      onProgress: onProgress,
    );
    await reload();
    return result;
  }

  String exportAdif({String myCall = ''}) => AdifWriter.write(
        db.allQsos(),
        freqPolicy: settings.adifFreqPolicy,
        myCall: myCall,
      );

  String exportJson() => ImportService(db).exportJson();

  String exportCsv() => ImportService(db).exportCsv();

  // --------------------------------------------------------- 路径工具

  /// 桌面端直接写文件；Android 走 SAF（由原生通道处理）。
  static Future<String> defaultExportDir() async {
    if (Platform.isWindows) {
      final docs = Platform.environment['USERPROFILE'] ?? '.';
      return '$docs\\Documents';
    }
    return Directory.systemTemp.path;
  }

  Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));
}

/// SQLite 持久层（sqlite3 直连，手写 SQL，无代码生成）。
///
/// 设计要点：
/// - 全部写操作走事务；批量导入分批提交。
/// - 删除一律写墓碑（deleted=1），供同步识别。
/// - 所有变更同时写入 oplog 表，作为同步增量来源。
/// - 索引按实际查询路径建立，见 _createSchema。
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart';

import 'models.dart';
import 'util.dart';

/// 查询筛选条件。
class QsoFilter {
  const QsoFilter({
    this.search = '',
    this.band = '',
    this.mode = '',
    this.qslStatus = -1,
    this.repeaterId = '',
    this.viaRepeaterOnly = false,
    this.sortBy = 'time_desc',
  });

  final String search;
  final String band;
  final String mode;
  final int qslStatus;
  final String repeaterId;
  final bool viaRepeaterOnly;
  final String sortBy; // time_desc / time_asc / call_asc / freq_desc

  bool get isEmpty =>
      search.isEmpty &&
      band.isEmpty &&
      mode.isEmpty &&
      qslStatus < 0 &&
      repeaterId.isEmpty &&
      !viaRepeaterOnly;

  QsoFilter copyWith({
    String? search,
    String? band,
    String? mode,
    int? qslStatus,
    String? repeaterId,
    bool? viaRepeaterOnly,
    String? sortBy,
  }) =>
      QsoFilter(
        search: search ?? this.search,
        band: band ?? this.band,
        mode: mode ?? this.mode,
        qslStatus: qslStatus ?? this.qslStatus,
        repeaterId: repeaterId ?? this.repeaterId,
        viaRepeaterOnly: viaRepeaterOnly ?? this.viaRepeaterOnly,
        sortBy: sortBy ?? this.sortBy,
      );
}

/// 日志总览统计结果。
class LogStats {
  LogStats({
    required this.total,
    required this.distinctCalls,
    required this.repeaterCount,
    required this.qslConfirmed,
    required this.bandCounts,
    required this.modeCounts,
    required this.last30Days,
  });

  final int total;
  final int distinctCalls;
  final int repeaterCount;
  final int qslConfirmed;
  final Map<String, int> bandCounts;
  final Map<String, int> modeCounts;
  final List<int> last30Days;
}

class AppDb {
  AppDb._(this._db, this.dataDir);

  final Database _db;
  final Directory dataDir;

  static AppDb? _instance;
  static AppDb get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('数据库尚未初始化，请先调用 AppDb.open()');
    }
    return i;
  }

  static bool get ready => _instance != null;

  static Future<AppDb> open() async {
    if (_instance != null) return _instance!;

    Directory dir;
    if (Platform.isWindows) {
      final base = Platform.environment['LOCALAPPDATA'] ??
          (await getApplicationSupportDirectory()).path;
      dir = Directory('$base\\SMPTLOG\\data');
    } else {
      final base = await getApplicationSupportDirectory();
      dir = Directory('${base.path}/data');
    }
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final dbFile = '${dir.path}${Platform.pathSeparator}smptlog.db';

    // Windows：部分机器开启了「智能应用控制（Smart App Control）」，
    // 会阻止加载随包发布的未签名 sqlite3.dll（错误码 4551）。
    // 改用系统自带的 winsqlite3.dll（微软签名，一定放行）。
    if (Platform.isWindows) {
      sqlite_open.open.overrideFor(
        sqlite_open.OperatingSystem.windows,
        () => ffi.DynamicLibrary.open('winsqlite3.dll'),
      );
    }

    final db = sqlite3.open(dbFile);
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA synchronous=NORMAL');
    db.execute('PRAGMA foreign_keys=ON');

    final app = AppDb._(db, dir);
    app._migrate();
    _instance = app;
    return app;
  }

  void _migrate() {
    final v = _db.select('PRAGMA user_version').first.values.first as int;
    if (v >= 1) return;

    _db.execute('BEGIN');
    try {
      _createSchema();
      _db.execute('PRAGMA user_version=1');
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _createSchema() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS qsos (
        uuid TEXT PRIMARY KEY,
        call TEXT NOT NULL DEFAULT '',
        call_norm TEXT NOT NULL DEFAULT '',
        qso_time INTEGER NOT NULL DEFAULT 0,
        freq_mhz REAL NOT NULL DEFAULT 0,
        band TEXT NOT NULL DEFAULT '',
        mode TEXT NOT NULL DEFAULT '',
        rst_sent TEXT NOT NULL DEFAULT '',
        rst_rcvd TEXT NOT NULL DEFAULT '',
        pwr_sent TEXT NOT NULL DEFAULT '',
        pwr_rcvd TEXT NOT NULL DEFAULT '',
        antenna TEXT NOT NULL DEFAULT '',
        rig TEXT NOT NULL DEFAULT '',
        qth TEXT NOT NULL DEFAULT '',
        country TEXT NOT NULL DEFAULT '',
        my_grid TEXT NOT NULL DEFAULT '',
        grid TEXT NOT NULL DEFAULT '',
        qsl_status INTEGER NOT NULL DEFAULT 0,
        remark TEXT NOT NULL DEFAULT '',
        weather TEXT NOT NULL DEFAULT '',
        repeater_id TEXT NOT NULL DEFAULT '',
        repeater_call TEXT NOT NULL DEFAULT '',
        repeater_downlink REAL NOT NULL DEFAULT 0,
        repeater_offset REAL NOT NULL DEFAULT 0,
        tone TEXT NOT NULL DEFAULT '',
        station_id TEXT NOT NULL DEFAULT '',
        station_name TEXT NOT NULL DEFAULT '',
        my_call TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        device_id TEXT NOT NULL DEFAULT ''
      )
    ''');

    _db.execute('CREATE INDEX IF NOT EXISTS idx_qso_time ON qsos(qso_time)');
    _db.execute(
        'CREATE INDEX IF NOT EXISTS idx_qso_call_time ON qsos(call_norm, qso_time)');
    _db.execute(
        'CREATE INDEX IF NOT EXISTS idx_qso_band_mode ON qsos(band, mode)');
    _db.execute(
        'CREATE INDEX IF NOT EXISTS idx_qso_updated ON qsos(updated_at)');
    _db.execute(
        'CREATE INDEX IF NOT EXISTS idx_qso_repeater ON qsos(repeater_id)');
    _db.execute(
        'CREATE INDEX IF NOT EXISTS idx_qso_dup ON qsos(call_norm, band, mode, qso_time)');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS repeaters (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        call TEXT NOT NULL DEFAULT '',
        downlink REAL NOT NULL DEFAULT 0,
        offset_mhz REAL NOT NULL DEFAULT 0,
        tx_tone TEXT NOT NULL DEFAULT '',
        rx_tone TEXT NOT NULL DEFAULT '',
        mode TEXT NOT NULL DEFAULT '',
        band TEXT NOT NULL DEFAULT '',
        color_code TEXT NOT NULL DEFAULT '',
        reflector TEXT NOT NULL DEFAULT '',
        qth TEXT NOT NULL DEFAULT '',
        locator TEXT NOT NULL DEFAULT '',
        open_time TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        is_favorite INTEGER NOT NULL DEFAULT 0,
        times_used INTEGER NOT NULL DEFAULT 0,
        last_used INTEGER,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        device_id TEXT NOT NULL DEFAULT ''
      )
    ''');
    _db.execute(
        'CREATE INDEX IF NOT EXISTS idx_rep_fav ON repeaters(is_favorite, name)');
    _db.execute(
        'CREATE INDEX IF NOT EXISTS idx_rep_band ON repeaters(band)');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS stations (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        my_call TEXT NOT NULL DEFAULT '',
        my_grid TEXT NOT NULL DEFAULT '',
        rig TEXT NOT NULL DEFAULT '',
        antenna TEXT NOT NULL DEFAULT '',
        power TEXT NOT NULL DEFAULT '',
        qth TEXT NOT NULL DEFAULT '',
        is_default INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        device_id TEXT NOT NULL DEFAULT ''
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS conflicts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dataset TEXT NOT NULL DEFAULT 'qso',
        uuid TEXT NOT NULL DEFAULT '',
        loser_json TEXT NOT NULL DEFAULT '{}',
        winner_updated_at INTEGER NOT NULL DEFAULT 0,
        loser_updated_at INTEGER NOT NULL DEFAULT 0,
        source_device TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS kv (
        k TEXT PRIMARY KEY,
        v TEXT NOT NULL DEFAULT ''
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS oplog (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        dataset TEXT NOT NULL DEFAULT 'qso',
        uuid TEXT NOT NULL DEFAULT '',
        rev INTEGER NOT NULL DEFAULT 0,
        kind TEXT NOT NULL DEFAULT 'upsert',
        payload TEXT NOT NULL DEFAULT '{}',
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    _db.execute(
        'CREATE INDEX IF NOT EXISTS idx_oplog_ds ON oplog(dataset, seq)');
  }

  // ---------------------------------------------------------------- QSO

  Qso? getQso(String uuid) {
    final rs = _db.select('SELECT * FROM qsos WHERE uuid=?', [uuid]);
    if (rs.isEmpty) return null;
    return _qsoFromRow(rs.first);
  }

  Qso? getQsoIncludeDeleted(String uuid) {
    final rs = _db.select('SELECT * FROM qsos WHERE uuid=?', [uuid]);
    if (rs.isEmpty) return null;
    return _qsoFromRow(rs.first);
  }

  /// 写入一条 QSO。若本地记录的 updatedAt 更新则拒绝覆盖（保护本地新数据）。
  bool upsertQso(Qso q, {bool log = true}) {
    final existing = _db.select(
      'SELECT updated_at FROM qsos WHERE uuid=?',
      [q.uuid],
    );
    if (existing.isNotEmpty) {
      final old = existing.first['updated_at'] as int;
      if (old > q.updatedAt.millisecondsSinceEpoch) return false;
    }
    _db.execute('''
      INSERT INTO qsos (uuid, call, call_norm, qso_time, freq_mhz, band, mode,
        rst_sent, rst_rcvd, pwr_sent, pwr_rcvd, antenna, rig, qth, country,
        my_grid, grid, qsl_status, remark, weather, repeater_id, repeater_call,
        repeater_downlink, repeater_offset, tone, station_id, station_name,
        my_call, created_at, updated_at, deleted, device_id)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(uuid) DO UPDATE SET
        call=excluded.call, call_norm=excluded.call_norm, qso_time=excluded.qso_time,
        freq_mhz=excluded.freq_mhz, band=excluded.band, mode=excluded.mode,
        rst_sent=excluded.rst_sent, rst_rcvd=excluded.rst_rcvd,
        pwr_sent=excluded.pwr_sent, pwr_rcvd=excluded.pwr_rcvd,
        antenna=excluded.antenna, rig=excluded.rig, qth=excluded.qth,
        country=excluded.country, my_grid=excluded.my_grid, grid=excluded.grid,
        qsl_status=excluded.qsl_status, remark=excluded.remark,
        weather=excluded.weather, repeater_id=excluded.repeater_id,
        repeater_call=excluded.repeater_call,
        repeater_downlink=excluded.repeater_downlink,
        repeater_offset=excluded.repeater_offset, tone=excluded.tone,
        station_id=excluded.station_id, station_name=excluded.station_name,
        my_call=excluded.my_call, updated_at=excluded.updated_at,
        deleted=excluded.deleted, device_id=excluded.device_id
    ''', [
      q.uuid,
      q.call,
      Callsign.base(q.call),
      q.qsoTimeUtc.millisecondsSinceEpoch,
      q.freqMhz,
      q.band,
      q.mode,
      q.rstSent,
      q.rstRcvd,
      q.pwrSent,
      q.pwrRcvd,
      q.antenna,
      q.rig,
      q.qth,
      q.country,
      q.myGrid,
      q.grid,
      q.qslStatus,
      q.remark,
      q.weather,
      q.repeaterId,
      q.repeaterCall,
      q.repeaterDownlink,
      q.repeaterOffset,
      q.tone,
      q.stationId,
      q.stationName,
      q.myCall,
      q.createdAt.millisecondsSinceEpoch,
      q.updatedAt.millisecondsSinceEpoch,
      q.deleted ? 1 : 0,
      q.deviceId,
    ]);
    if (log) _appendOplog('qso', q.uuid, q.toJson());
    return true;
  }

  /// 批量写入（单事务）。返回实际写入条数。
  int upsertQsos(List<Qso> list, {bool log = true}) {
    if (list.isEmpty) return 0;
    var n = 0;
    _db.execute('BEGIN');
    try {
      for (final q in list) {
        if (upsertQso(q, log: log)) n++;
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return n;
  }

  /// 软删除。
  void deleteQso(String uuid, {String deviceId = ''}) {
    final q = getQso(uuid);
    if (q == null) return;
    upsertQso(q.copyWith(
      deleted: true,
      updatedAt: DateTime.now().toUtc(),
      deviceId: deviceId,
    ));
  }

  void restoreQso(String uuid, {String deviceId = ''}) {
    final q = getQso(uuid);
    if (q == null) return;
    upsertQso(q.copyWith(
      deleted: false,
      updatedAt: DateTime.now().toUtc(),
      deviceId: deviceId,
    ));
  }

  /// 彻底清除已删除记录（压缩时使用）。
  void purgeDeleted({int olderThanDays = 90}) {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: olderThanDays))
        .millisecondsSinceEpoch;
    _db.execute(
      'DELETE FROM qsos WHERE deleted=1 AND updated_at < ?',
      [cutoff],
    );
  }

  void bulkUpdateQsl(List<String> uuids, int status, {String deviceId = ''}) {
    if (uuids.isEmpty) return;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    _db.execute('BEGIN');
    try {
      for (final id in uuids) {
        final q = getQso(id);
        if (q == null) continue;
        upsertQso(q.copyWith(
          qslStatus: status,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
          deviceId: deviceId,
        ));
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  ({String where, List<Object?> args}) _buildWhere(QsoFilter f) {
    final conds = <String>['deleted=0'];
    final args = <Object?>[];
    if (f.search.trim().isNotEmpty) {
      final s = '%${f.search.trim().toUpperCase()}%';
      conds.add(
        '(call_norm LIKE ? OR qth LIKE ? OR remark LIKE ? OR country LIKE ? OR repeater_call LIKE ?)',
      );
      args.addAll([s, '%${f.search.trim()}%', '%${f.search.trim()}%',
          '%${f.search.trim()}%', s]);
    }
    if (f.band.isNotEmpty) {
      conds.add('band=?');
      args.add(f.band);
    }
    if (f.mode.isNotEmpty) {
      conds.add('mode=?');
      args.add(f.mode);
    }
    if (f.qslStatus >= 0) {
      conds.add('qsl_status=?');
      args.add(f.qslStatus);
    }
    if (f.repeaterId.isNotEmpty) {
      conds.add('repeater_id=?');
      args.add(f.repeaterId);
    }
    if (f.viaRepeaterOnly) {
      conds.add("(repeater_id<>'' OR repeater_call<>'')");
    }
    return (where: conds.join(' AND '), args: args);
  }

  String _orderBy(String sortBy) {
    switch (sortBy) {
      case 'time_asc':
        return 'qso_time ASC, uuid ASC';
      case 'call_asc':
        return 'call_norm ASC, qso_time DESC';
      case 'freq_desc':
        return 'freq_mhz DESC, qso_time DESC';
      default:
        return 'qso_time DESC, uuid DESC';
    }
  }

  /// 游标分页查询，避免 OFFSET 深翻页退化。
  List<Qso> queryQsos(
    QsoFilter filter, {
    int limit = 50,
    ({int timeMs, String uuid})? cursor,
  }) {
    final w = _buildWhere(filter);
    var where = w.where;
    final args = List<Object?>.from(w.args);

    if (cursor != null) {
      if (filter.sortBy == 'time_asc') {
        where += ' AND (qso_time > ? OR (qso_time = ? AND uuid > ?))';
      } else if (filter.sortBy == 'call_asc') {
        where += ' AND call_norm > ?';
        args.add(filter.search);
      } else {
        where += ' AND (qso_time < ? OR (qso_time = ? AND uuid < ?))';
      }
      if (filter.sortBy != 'call_asc') {
        args.addAll([cursor.timeMs, cursor.timeMs, cursor.uuid]);
      }
    }

    final rs = _db.select(
      'SELECT * FROM qsos WHERE $where ORDER BY ${_orderBy(filter.sortBy)} LIMIT ?',
      [...args, limit],
    );
    return rs.map(_qsoFromRow).toList();
  }

  int countQsos(QsoFilter filter) {
    final w = _buildWhere(filter);
    final rs = _db.select(
      'SELECT COUNT(*) AS c FROM qsos WHERE ${w.where}',
      w.args,
    );
    return rs.first['c'] as int;
  }

  /// 找出与给定 QSO 疑似重复的记录（同呼号+波段+模式+时间窗）。
  List<Qso> findDuplicates(Qso target, int windowMinutes) {
    if (windowMinutes <= 0) return const [];
    final t = target.qsoTimeUtc.millisecondsSinceEpoch;
    final win = Duration(minutes: windowMinutes).inMilliseconds;
    final rs = _db.select('''
      SELECT * FROM qsos
      WHERE deleted=0 AND call_norm=? AND band=? AND mode=?
        AND qso_time BETWEEN ? AND ? AND uuid<>?
      ORDER BY qso_time DESC LIMIT 20
    ''', [
      Callsign.base(target.call),
      target.band,
      target.mode,
      t - win,
      t + win,
      target.uuid,
    ]);
    return rs.map(_qsoFromRow).toList();
  }

  /// 一次性返回全部未删除记录（用于判重批量标记、导出）。
  List<Qso> allQsos({bool includeDeleted = false}) {
    final rs = _db.select(
      'SELECT * FROM qsos ${includeDeleted ? '' : 'WHERE deleted=0'} ORDER BY qso_time DESC',
    );
    return rs.map(_qsoFromRow).toList();
  }

  LogStats stats() {
    final total =
        _db.select('SELECT COUNT(*) c FROM qsos WHERE deleted=0').first['c'] as int;
    final distinct = _db
        .select("SELECT COUNT(DISTINCT call_norm) c FROM qsos WHERE deleted=0")
        .first['c'] as int;
    final reps = _db
        .select(
            "SELECT COUNT(*) c FROM qsos WHERE deleted=0 AND (repeater_id<>'' OR repeater_call<>'')")
        .first['c'] as int;
    final confirmed = _db
        .select('SELECT COUNT(*) c FROM qsos WHERE deleted=0 AND qsl_status=3')
        .first['c'] as int;

    final bandCounts = <String, int>{};
    for (final r in _db.select(
        "SELECT band, COUNT(*) c FROM qsos WHERE deleted=0 AND band<>'' GROUP BY band ORDER BY c DESC")) {
      bandCounts[r['band'] as String] = r['c'] as int;
    }

    final modeCounts = <String, int>{};
    for (final r in _db.select(
        "SELECT mode, COUNT(*) c FROM qsos WHERE deleted=0 AND mode<>'' GROUP BY mode ORDER BY c DESC")) {
      modeCounts[r['mode'] as String] = r['c'] as int;
    }

    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final series = List<int>.filled(30, 0);
    final from = today.subtract(const Duration(days: 29));
    final rs = _db.select(
      'SELECT qso_time FROM qsos WHERE deleted=0 AND qso_time>=?',
      [from.millisecondsSinceEpoch],
    );
    for (final r in rs) {
      final t = DateTime.fromMillisecondsSinceEpoch(
        r['qso_time'] as int,
        isUtc: true,
      );
      final day = DateTime.utc(t.year, t.month, t.day);
      final idx = day.difference(from).inDays;
      if (idx >= 0 && idx < 30) series[idx]++;
    }

    return LogStats(
      total: total,
      distinctCalls: distinct,
      repeaterCount: reps,
      qslConfirmed: confirmed,
      bandCounts: bandCounts,
      modeCounts: modeCounts,
      last30Days: series,
    );
  }

  /// 奖状追踪用的聚合数据。
  ({int distinctBands, int distinctModes, int distinctCountries,
      Map<String, int> bandGrids}) awardSummary() {
    final bands = _db
        .select("SELECT COUNT(DISTINCT band) c FROM qsos WHERE deleted=0 AND band<>''")
        .first['c'] as int;
    final modes = _db
        .select("SELECT COUNT(DISTINCT mode) c FROM qsos WHERE deleted=0 AND mode<>''")
        .first['c'] as int;
    final countries = _db
        .select(
            "SELECT COUNT(DISTINCT country) c FROM qsos WHERE deleted=0 AND country<>''")
        .first['c'] as int;

    final bandGrids = <String, int>{};
    for (final r in _db.select(
        "SELECT band, COUNT(DISTINCT grid) c FROM qsos WHERE deleted=0 AND band<>'' AND grid<>'' GROUP BY band")) {
      bandGrids[r['band'] as String] = r['c'] as int;
    }
    return (
      distinctBands: bands,
      distinctModes: modes,
      distinctCountries: countries,
      bandGrids: bandGrids,
    );
  }

  Qso _qsoFromRow(Row r) => Qso(
        uuid: r['uuid'] as String,
        call: r['call'] as String,
        qsoTimeUtc: DateTime.fromMillisecondsSinceEpoch(
          r['qso_time'] as int,
          isUtc: true,
        ),
        freqMhz: (r['freq_mhz'] as num).toDouble(),
        band: r['band'] as String,
        mode: r['mode'] as String,
        rstSent: r['rst_sent'] as String,
        rstRcvd: r['rst_rcvd'] as String,
        pwrSent: r['pwr_sent'] as String,
        pwrRcvd: r['pwr_rcvd'] as String,
        antenna: r['antenna'] as String,
        rig: r['rig'] as String,
        qth: r['qth'] as String,
        country: r['country'] as String,
        myGrid: r['my_grid'] as String,
        grid: r['grid'] as String,
        qslStatus: r['qsl_status'] as int,
        remark: r['remark'] as String,
        weather: r['weather'] as String,
        repeaterId: r['repeater_id'] as String,
        repeaterCall: r['repeater_call'] as String,
        repeaterDownlink: (r['repeater_downlink'] as num).toDouble(),
        repeaterOffset: (r['repeater_offset'] as num).toDouble(),
        tone: r['tone'] as String,
        stationId: r['station_id'] as String,
        stationName: r['station_name'] as String,
        myCall: r['my_call'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          r['created_at'] as int,
          isUtc: true,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          r['updated_at'] as int,
          isUtc: true,
        ),
        deleted: (r['deleted'] as int) == 1,
        deviceId: r['device_id'] as String,
      );

  // ----------------------------------------------------------- Repeater

  void upsertRepeater(Repeater r, {bool log = true}) {
    _db.execute('''
      INSERT INTO repeaters (id, name, call, downlink, offset_mhz, tx_tone,
        rx_tone, mode, band, color_code, reflector, qth, locator, open_time,
        note, is_favorite, times_used, last_used, created_at, updated_at,
        deleted, device_id)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        name=excluded.name, call=excluded.call, downlink=excluded.downlink,
        offset_mhz=excluded.offset_mhz, tx_tone=excluded.tx_tone,
        rx_tone=excluded.rx_tone, mode=excluded.mode, band=excluded.band,
        color_code=excluded.color_code, reflector=excluded.reflector,
        qth=excluded.qth, locator=excluded.locator, open_time=excluded.open_time,
        note=excluded.note, is_favorite=excluded.is_favorite,
        times_used=excluded.times_used, last_used=excluded.last_used,
        updated_at=excluded.updated_at, deleted=excluded.deleted,
        device_id=excluded.device_id
    ''', [
      r.id, r.name, r.call, r.downlink, r.offset, r.txTone, r.rxTone, r.mode,
      r.band, r.colorCode, r.reflector, r.qth, r.locator, r.openTime, r.note,
      r.isFavorite ? 1 : 0, r.timesUsed,
      r.lastUsed?.millisecondsSinceEpoch,
      r.createdAt.millisecondsSinceEpoch,
      r.updatedAt.millisecondsSinceEpoch,
      r.deleted ? 1 : 0, r.deviceId,
    ]);
    if (log) _appendOplog('repeater', r.id, r.toJson());
  }

  List<Repeater> allRepeaters({String search = '', String band = ''}) {
    final conds = <String>['deleted=0'];
    final args = <Object?>[];
    if (search.trim().isNotEmpty) {
      conds.add('(name LIKE ? OR call LIKE ? OR qth LIKE ?)');
      final s = '%${search.trim()}%';
      args.addAll([s, s, s]);
    }
    if (band.isNotEmpty) {
      conds.add('band=?');
      args.add(band);
    }
    final rs = _db.select(
      'SELECT * FROM repeaters WHERE ${conds.join(' AND ')} '
      'ORDER BY is_favorite DESC, times_used DESC, name ASC',
      args,
    );
    return rs.map(_repFromRow).toList();
  }

  Repeater? getRepeater(String id) {
    final rs = _db.select('SELECT * FROM repeaters WHERE id=?', [id]);
    if (rs.isEmpty) return null;
    return _repFromRow(rs.first);
  }

  void deleteRepeater(String id, {String deviceId = ''}) {
    final r = getRepeater(id);
    if (r == null) return;
    upsertRepeater(r.copyWith(
      deleted: true,
      updatedAt: DateTime.now().toUtc(),
    ));
  }

  void touchRepeater(String id) {
    final r = getRepeater(id);
    if (r == null) return;
    upsertRepeater(r.copyWith(
      timesUsed: r.timesUsed + 1,
      lastUsed: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ));
  }

  Repeater _repFromRow(Row r) => Repeater(
        id: r['id'] as String,
        name: r['name'] as String,
        call: r['call'] as String,
        downlink: (r['downlink'] as num).toDouble(),
        offset: (r['offset_mhz'] as num).toDouble(),
        txTone: r['tx_tone'] as String,
        rxTone: r['rx_tone'] as String,
        mode: r['mode'] as String,
        band: r['band'] as String,
        colorCode: r['color_code'] as String,
        reflector: r['reflector'] as String,
        qth: r['qth'] as String,
        locator: r['locator'] as String,
        openTime: r['open_time'] as String,
        note: r['note'] as String,
        isFavorite: (r['is_favorite'] as int) == 1,
        timesUsed: r['times_used'] as int,
        lastUsed: r['last_used'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                r['last_used'] as int,
                isUtc: true,
              ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          r['created_at'] as int,
          isUtc: true,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          r['updated_at'] as int,
          isUtc: true,
        ),
        deleted: (r['deleted'] as int) == 1,
        deviceId: r['device_id'] as String,
      );

  // ------------------------------------------------------------ Station

  void upsertStation(StationProfile s, {bool log = true}) {
    _db.execute('''
      INSERT INTO stations (id, name, my_call, my_grid, rig, antenna, power,
        qth, is_default, created_at, updated_at, deleted, device_id)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        name=excluded.name, my_call=excluded.my_call, my_grid=excluded.my_grid,
        rig=excluded.rig, antenna=excluded.antenna, power=excluded.power,
        qth=excluded.qth, is_default=excluded.is_default,
        updated_at=excluded.updated_at, deleted=excluded.deleted,
        device_id=excluded.device_id
    ''', [
      s.id, s.name, s.myCall, s.myGrid, s.rig, s.antenna, s.power, s.qth,
      s.isDefault ? 1 : 0, s.createdAt.millisecondsSinceEpoch,
      s.updatedAt.millisecondsSinceEpoch, s.deleted ? 1 : 0, s.deviceId,
    ]);
    if (log) _appendOplog('station', s.id, s.toJson());
  }

  List<StationProfile> allStations() {
    final rs = _db.select(
      'SELECT * FROM stations WHERE deleted=0 ORDER BY is_default DESC, name ASC',
    );
    return rs.map(_stationFromRow).toList();
  }

  void deleteStation(String id) {
    StationProfile? s;
    for (final e in allStations()) {
      if (e.id == id) {
        s = e;
        break;
      }
    }
    if (s == null) return;
    upsertStation(s.copyWith(
      deleted: true,
      updatedAt: DateTime.now().toUtc(),
    ));
  }

  StationProfile _stationFromRow(Row r) => StationProfile(
        id: r['id'] as String,
        name: r['name'] as String,
        myCall: r['my_call'] as String,
        myGrid: r['my_grid'] as String,
        rig: r['rig'] as String,
        antenna: r['antenna'] as String,
        power: r['power'] as String,
        qth: r['qth'] as String,
        isDefault: (r['is_default'] as int) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          r['created_at'] as int,
          isUtc: true,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          r['updated_at'] as int,
          isUtc: true,
        ),
        deleted: (r['deleted'] as int) == 1,
        deviceId: r['device_id'] as String,
      );

  // ----------------------------------------------------------- Conflicts

  void addConflict({
    required String dataset,
    required String uuid,
    required Map<String, dynamic> loser,
    required DateTime winnerUpdatedAt,
    required DateTime loserUpdatedAt,
    required String sourceDevice,
  }) {
    _db.execute('''
      INSERT INTO conflicts (dataset, uuid, loser_json, winner_updated_at,
        loser_updated_at, source_device, created_at)
      VALUES (?,?,?,?,?,?,?)
    ''', [
      dataset,
      uuid,
      jsonEncode(loser),
      winnerUpdatedAt.millisecondsSinceEpoch,
      loserUpdatedAt.millisecondsSinceEpoch,
      sourceDevice,
      DateTime.now().toUtc().millisecondsSinceEpoch,
    ]);
  }

  List<ConflictEntry> allConflicts() {
    final rs = _db.select('SELECT * FROM conflicts ORDER BY id DESC LIMIT 200');
    return rs
        .map((r) => ConflictEntry(
              id: r['id'] as int,
              dataset: r['dataset'] as String,
              uuid: r['uuid'] as String,
              loserJson: jsonDecode(r['loser_json'] as String)
                  as Map<String, dynamic>,
              winnerUpdatedAt: DateTime.fromMillisecondsSinceEpoch(
                r['winner_updated_at'] as int,
                isUtc: true,
              ),
              loserUpdatedAt: DateTime.fromMillisecondsSinceEpoch(
                r['loser_updated_at'] as int,
                isUtc: true,
              ),
              sourceDevice: r['source_device'] as String,
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                r['created_at'] as int,
                isUtc: true,
              ),
            ))
        .toList();
  }

  void removeConflict(int id) {
    _db.execute('DELETE FROM conflicts WHERE id=?', [id]);
  }

  int get conflictCount =>
      _db.select('SELECT COUNT(*) c FROM conflicts').first['c'] as int;

  // ----------------------------------------------------------------- kv

  String? kvGet(String key) {
    final rs = _db.select('SELECT v FROM kv WHERE k=?', [key]);
    if (rs.isEmpty) return null;
    return rs.first['v'] as String;
  }

  void kvSet(String key, String value) {
    _db.execute(
      'INSERT INTO kv (k, v) VALUES (?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v',
      [key, value],
    );
  }

  // -------------------------------------------------------------- oplog

  void _appendOplog(String dataset, String uuid, Map<String, dynamic> payload) {
    final rev = DateTime.now().microsecondsSinceEpoch;
    _db.execute(
      'INSERT INTO oplog (dataset, uuid, rev, kind, payload, created_at) '
      'VALUES (?,?,?,?,?,?)',
      [
        dataset,
        uuid,
        rev,
        'upsert',
        jsonEncode(payload),
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  int oplogCount(String dataset) => _db
      .select('SELECT COUNT(*) c FROM oplog WHERE dataset=?', [dataset])
      .first['c'] as int;

  List<Map<String, dynamic>> oplogEntries(String dataset, {int limit = 500}) {
    final rs = _db.select(
      'SELECT * FROM oplog WHERE dataset=? ORDER BY seq ASC LIMIT ?',
      [dataset, limit],
    );
    return rs
        .map((r) => {
              'seq': r['seq'] as int,
              'dataset': r['dataset'] as String,
              'uuid': r['uuid'] as String,
              'rev': r['rev'] as int,
              'kind': r['kind'] as String,
              'payload': r['payload'] as String,
              'created_at': r['created_at'] as int,
            })
        .toList();
  }

  void clearOplogUpTo(String dataset, int maxSeq) {
    _db.execute('DELETE FROM oplog WHERE dataset=? AND seq<=?', [dataset, maxSeq]);
  }

  /// 取某数据集里 updated_at 最大的记录时间，作为推送到云端的 rev。
  int localRev(String dataset) {
    final table = dataset == 'repeater'
        ? 'repeaters'
        : dataset == 'station'
            ? 'stations'
            : 'qsos';
    final rs = _db.select('SELECT MAX(updated_at) m FROM $table');
    return (rs.first['m'] as int?) ?? 0;
  }

  void close() {
    _db.dispose();
    _instance = null;
  }
}

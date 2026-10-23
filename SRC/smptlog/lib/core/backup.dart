/// 备份与导入服务：JSON 全量、CSV 导出、ADIF 导入编排。
///
/// 安全铁律：导出内容**永远不含** API Token、同步密码、加密密钥。
library;

import 'dart:convert';

import 'adif.dart';
import 'db.dart';
import 'models.dart';
import 'util.dart';

/// 备份文件结构。
class BackupBundle {
  BackupBundle({
    required this.qsos,
    required this.repeaters,
    required this.stations,
  });

  final List<Qso> qsos;
  final List<Repeater> repeaters;
  final List<StationProfile> stations;

  Map<String, dynamic> toJson() => {
        'app': 'SMPTLOG',
        'format': 'smptlog-backup',
        'schema_version': 1,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'note': '本文件不含同步 Token 与加密密码，换设备后需重新填写',
        'qsos': qsos.map((e) => e.toJson()).toList(),
        'repeaters': repeaters.map((e) => e.toJson()).toList(),
        'stations': stations.map((e) => e.toJson()).toList(),
      };

  static BackupBundle fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) {
      final raw = j[key];
      if (raw is! List) return <T>[];
      return raw
          .whereType<Map>()
          .map((e) => f(Map<String, dynamic>.from(e)))
          .toList();
    }

    return BackupBundle(
      qsos: list('qsos', Qso.fromJson),
      repeaters: list('repeaters', Repeater.fromJson),
      stations: list('stations', StationProfile.fromJson),
    );
  }
}

/// 导入结果统计。
class ImportResult {
  ImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
    required this.failed,
    required this.duplicates,
    this.errors = const [],
  });

  final int added;
  final int updated;
  final int skipped;
  final int failed;
  final int duplicates;
  final List<AdifParseError> errors;

  int get total => added + updated + skipped + failed;

  Map<String, dynamic> toJson() => {
        'added': added,
        'updated': updated,
        'skipped': skipped,
        'failed': failed,
        'duplicates': duplicates,
        'errors': errors.map((e) => e.toJson()).toList(),
      };
}

/// 重复处理策略。
enum DupPolicy {
  /// 跳过疑似重复
  skip,

  /// 全部保留
  keepAll,

  /// 保留但在备注里打标记
  markKept,
}

class ImportService {
  ImportService(this.db);

  final AppDb db;

  /// 导入 ADIF 文本。
  ///
  /// [onProgress] 回传 (已完成, 总数)。
  /// [windowMinutes] 判重时间窗，0 表示不判重。
  Future<ImportResult> importAdif(
    String text, {
    required String deviceId,
    DupPolicy policy = DupPolicy.keepAll,
    int windowMinutes = 30,
    void Function(int done, int total)? onProgress,
  }) async {
    final parsed = AdifReader.parse(text);
    final records = parsed.records;
    final total = records.length;

    var added = 0;
    var updated = 0;
    var skipped = 0;
    var failed = 0;
    var dup = 0;

    final batch = <Qso>[];

    Future<void> flush() async {
      if (batch.isEmpty) return;
      db.upsertQsos(batch);
      batch.clear();
    }

    for (var i = 0; i < records.length; i++) {
      final q = AdifReader.toQso(records[i], deviceId: deviceId);
      if (q == null) {
        failed++;
      } else {
        final existing = db.getQsoIncludeDeleted(q.uuid);
        if (existing != null) {
          updated++;
        } else {
          added++;
        }

        var toInsert = q;
        if (windowMinutes > 0) {
          final dups = db.findDuplicates(q, windowMinutes);
          if (dups.isNotEmpty) {
            dup++;
            if (policy == DupPolicy.skip) {
              skipped++;
              onProgress?.call(i + 1, total);
              continue;
            }
            if (policy == DupPolicy.markKept) {
              final mark = '[疑似重复 ${Fmt.dateTimeUtc(dups.first.qsoTimeUtc)}]';
              toInsert = q.copyWith(
                remark: q.remark.isEmpty ? mark : '$mark ${q.remark}',
              );
            }
          }
        }
        batch.add(toInsert);
        if (batch.length >= 500) await flush();
      }
      onProgress?.call(i + 1, total);
    }
    await flush();

    return ImportResult(
      added: added,
      updated: updated,
      skipped: skipped,
      failed: failed,
      duplicates: dup,
      errors: parsed.errors,
    );
  }

  /// 导入 JSON 全量备份。
  Future<ImportResult> importJsonBackup(
    String text, {
    void Function(int done, int total)? onProgress,
  }) async {
    final map = jsonDecode(text) as Map<String, dynamic>;
    final bundle = BackupBundle.fromJson(map);
    var added = 0;
    var updated = 0;

    for (var i = 0; i < bundle.qsos.length; i++) {
      final q = bundle.qsos[i];
      final existing = db.getQsoIncludeDeleted(q.uuid);
      if (existing == null) {
        added++;
      } else {
        updated++;
      }
      db.upsertQso(q);
      if (i % 200 == 0) onProgress?.call(i, bundle.qsos.length);
    }
    for (final r in bundle.repeaters) {
      db.upsertRepeater(r);
    }
    for (final s in bundle.stations) {
      db.upsertStation(s);
    }

    return ImportResult(
      added: added,
      updated: updated,
      skipped: 0,
      failed: 0,
      duplicates: 0,
    );
  }

  /// 导出 JSON 全量备份文本。
  String exportJson({
    bool includeDeleted = false,
  }) {
    final bundle = BackupBundle(
      qsos: db.allQsos(includeDeleted: includeDeleted),
      repeaters: db.allRepeaters(),
      stations: db.allStations(),
    );
    return const JsonEncoder.withIndent('  ').convert(bundle.toJson());
  }

  /// 导出 CSV（Excel 友好，带 UTF-8 BOM）。
  String exportCsv({bool includeBom = true}) {
    final sb = StringBuffer();
    if (includeBom) sb.write('\uFEFF');
    sb.writeln(
        '日期时间(UTC),呼号,频率MHz,波段,模式,RST发,RST收,己方功率,对方功率,'
        '天馈,设备,QTH,国家地区,己方网格,对方网格,QSL,中继呼号,下行,上行偏移,亚音,备注');
    for (final q in db.allQsos()) {
      sb.writeln([
        Fmt.dateTimeUtc(q.qsoTimeUtc),
        q.call,
        Fmt.freq(q.freqMhz),
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
        QslStatus.label(q.qslStatus),
        q.repeaterCall,
        q.viaRepeater ? q.repeaterDownlink.toStringAsFixed(4) : '',
        q.repeaterOffset == 0 ? '' : q.repeaterOffset.toStringAsFixed(4),
        q.tone,
        q.remark,
      ].map(_csvCell).join(','));
    }
    return sb.toString();
  }

  String _csvCell(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }
}


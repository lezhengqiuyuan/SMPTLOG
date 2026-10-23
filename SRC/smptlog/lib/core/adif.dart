/// ADIF 读写（ADIF 3.x）。
///
/// 设计要点：
/// - 解析器容错：坏字段跳过一个、坏记录跳过一条，并记录偏移与原因。
/// - 中继相关字段使用 ADIF 规范允许的“下划线开头”自定义字段，
///   其他软件导入时忽略但不报错，本程序可无损还原。
library;

import 'models.dart';
import 'util.dart';

/// 解析出的一条原始记录。
class AdifRecord {
  AdifRecord(this.fields, this.offset);
  final Map<String, String> fields;
  final int offset;
}

/// 解析错误。
class AdifParseError {
  AdifParseError(this.offset, this.snippet, this.reason);
  final int offset;
  final String snippet;
  final String reason;

  Map<String, dynamic> toJson() => {
        'offset': offset,
        'snippet': snippet,
        'reason': reason,
      };
}

class AdifParseResult {
  AdifParseResult(this.header, this.records, this.errors);
  final Map<String, String> header;
  final List<AdifRecord> records;
  final List<AdifParseError> errors;
}

/// ADIF 字段名常量。
class AdifFields {
  static const call = 'CALL';
  static const qsoDate = 'QSO_DATE';
  static const timeOn = 'TIME_ON';
  static const freq = 'FREQ';
  static const band = 'BAND';
  static const mode = 'MODE';
  static const submode = 'SUBMODE';
  static const rstSent = 'RST_SENT';
  static const rstRcvd = 'RST_RCVD';
  static const txPwr = 'TX_PWR';
  static const rxPwr = 'RX_PWR';
  static const myAntenna = 'MY_ANTENNA';
  static const myRig = 'MY_RIG';
  static const qth = 'QTH';
  static const country = 'COUNTRY';
  static const myGridsquare = 'MY_GRID_SQUARE';
  static const gridsquare = 'GRIDSQUARE';
  static const qslSent = 'QSL_SENT';
  static const qslRcvd = 'QSL_RCVD';
  static const comment = 'COMMENT';
  static const notes = 'NOTES';

  // ---- 自定义扩展（下划线开头，ADIF 规范允许）----
  static const xWeather = '_WEATHER';
  static const xRelayCall = '_RELAY_CALL';
  static const xRelayFreq = '_RELAY_FREQ';
  static const xOffset = '_OFFSET';
  static const xCtcss = '_CTCSS';
  static const xCtcssRx = '_CTCSS_RX';
  static const xDcs = '_DCSCODE';
  static const xDmrCc = '_DMR_CC';
  static const xReflector = '_XREFL';
  static const xStation = '_STATION';
  static const xUuid = '_SMPTL_UUID';
}

/// ADIF 解析器。
class AdifReader {
  /// 解析 ADIF 文本。
  static AdifParseResult parse(String text) {
    final header = <String, String>{};
    final records = <AdifRecord>[];
    final errors = <AdifParseError>[];

    var i = 0;
    final n = text.length;
    var current = <String, String>{};
    var recordStart = 0;
    var inHeader = true;

    while (i < n) {
      final lt = text.indexOf('<', i);
      if (lt < 0) break;

      // 找到标签结束的 '>'
      final gt = text.indexOf('>', lt);
      if (gt < 0) {
        errors.add(AdifParseError(lt, _snippet(text, lt), '标签未闭合（缺少 >）'));
        break;
      }

      final spec = text.substring(lt + 1, gt);
      if (spec.isEmpty) {
        i = gt + 1;
        continue;
      }

      final upper = spec.toUpperCase();

      if (upper == 'EOH') {
        inHeader = false;
        recordStart = gt + 1;
        i = gt + 1;
        continue;
      }

      if (upper == 'EOR') {
        if (current.isNotEmpty) {
          records.add(AdifRecord(current, recordStart));
          current = <String, String>{};
        }
        recordStart = gt + 1;
        i = gt + 1;
        continue;
      }

      // 解析 <NAME:len:type>
      final parts = spec.split(':');
      final name = parts[0].toUpperCase();
      int? len;
      if (parts.length >= 2) {
        len = int.tryParse(parts[1].trim());
      }
      if (len == null || len < 0) {
        errors.add(AdifParseError(lt, _snippet(text, lt), '字段长度无法解析：<$spec>'));
        i = gt + 1;
        continue;
      }

      final valueStart = gt + 1;
      if (valueStart + len > n) {
        errors.add(AdifParseError(lt, _snippet(text, lt), '字段内容被截断（声明长度 $len）'));
        break;
      }
      final value = text.substring(valueStart, valueStart + len).trim();

      if (inHeader) {
        header[name] = value;
      } else {
        current[name] = value;
      }
      i = valueStart + len;
    }

    if (current.isNotEmpty) {
      records.add(AdifRecord(current, recordStart));
    }

    return AdifParseResult(header, records, errors);
  }

  static String _snippet(String text, int offset) {
    final start = offset - 20 < 0 ? 0 : offset - 20;
    final end = offset + 40 > text.length ? text.length : offset + 40;
    return text.substring(start, end).replaceAll('\n', ' ');
  }

  /// 把一条 ADIF 记录转成 Qso。
  ///
  /// [deviceId] 与 [fallbackBand] 用于补全缺失信息。
  static Qso? toQso(
    AdifRecord rec, {
    required String deviceId,
    String fallbackBand = '',
  }) {
    final f = rec.fields;
    final call = (f[AdifFields.call] ?? '').trim();
    if (call.isEmpty) return null;

    final date = (f[AdifFields.qsoDate] ?? '').trim();
    final time = (f[AdifFields.timeOn] ?? '').trim();
    final dt = _parseDateTime(date, time);
    if (dt == null) return null;

    final freq = double.tryParse((f[AdifFields.freq] ?? '').trim()) ?? 0;
    final band = (f[AdifFields.band] ?? '').trim().isNotEmpty
        ? f[AdifFields.band]!.trim()
        : (freq > 0 ? Bands.fromFreq(freq) : fallbackBand);

    var mode = (f[AdifFields.mode] ?? '').trim().toUpperCase();
    final sub = (f[AdifFields.submode] ?? '').trim().toUpperCase();
    if (sub.isNotEmpty) {
      // FT8 等数字模式在 ADIF 里常写作 MODE=DATA + SUBMODE=FT8
      mode = sub;
    }
    if (mode == 'DATA' || mode.isEmpty) {
      mode = QsoMode.fm;
    }

    final qslSent = (f[AdifFields.qslSent] ?? '').toUpperCase();
    final qslRcvd = (f[AdifFields.qslRcvd] ?? '').toUpperCase();
    var qsl = QslStatus.none;
    if (qslRcvd.startsWith('Y')) {
      qsl = QslStatus.confirmed;
    } else if (qslSent.startsWith('Y')) {
      qsl = QslStatus.sent;
    }

    final relayFreq = double.tryParse((f[AdifFields.xRelayFreq] ?? '')) ?? 0;
    final downlink = relayFreq > 0 ? relayFreq : freq;
    final offset = double.tryParse((f[AdifFields.xOffset] ?? '')) ?? 0;
    final relayCall = (f[AdifFields.xRelayCall] ?? '').trim();

    final tone = (f[AdifFields.xCtcss] ?? '').isNotEmpty
        ? (f[AdifFields.xCtcss] ?? '')
        : ((f[AdifFields.xDcs] ?? '').isNotEmpty
            ? (f[AdifFields.xDcs] ?? '')
            : '');

    final now = DateTime.now().toUtc();
    final uuid = (f[AdifFields.xUuid] ?? '').trim();

    return Qso(
      uuid: uuid.isNotEmpty ? uuid : IdGen.uuid(),
      call: call,
      qsoTimeUtc: dt,
      freqMhz: freq,
      band: band,
      mode: mode,
      rstSent: (f[AdifFields.rstSent] ?? '').trim(),
      rstRcvd: (f[AdifFields.rstRcvd] ?? '').trim(),
      pwrSent: (f[AdifFields.txPwr] ?? '').trim(),
      pwrRcvd: (f[AdifFields.rxPwr] ?? '').trim(),
      antenna: (f[AdifFields.myAntenna] ?? '').trim(),
      rig: (f[AdifFields.myRig] ?? '').trim(),
      qth: (f[AdifFields.qth] ?? '').trim(),
      country: (f[AdifFields.country] ?? '').trim(),
      myGrid: (f[AdifFields.myGridsquare] ?? '').trim(),
      grid: (f[AdifFields.gridsquare] ?? '').trim(),
      qslStatus: qsl,
      remark: [
        (f[AdifFields.comment] ?? '').trim(),
        (f[AdifFields.notes] ?? '').trim(),
      ].where((e) => e.isNotEmpty).join(' | '),
      weather: (f[AdifFields.xWeather] ?? '').trim(),
      repeaterId: '',
      repeaterCall: relayCall,
      repeaterDownlink: downlink,
      repeaterOffset: offset,
      tone: tone,
      stationName: (f[AdifFields.xStation] ?? '').trim(),
      createdAt: now,
      updatedAt: now,
      deviceId: deviceId,
    );
  }

  static DateTime? _parseDateTime(String date, String time) {
    if (date.length < 8) return null;
    final y = int.tryParse(date.substring(0, 4));
    final m = int.tryParse(date.substring(4, 6));
    final d = int.tryParse(date.substring(6, 8));
    if (y == null || m == null || d == null) return null;

    var hh = 0, mm = 0, ss = 0;
    if (time.length >= 4) {
      hh = int.tryParse(time.substring(0, 2)) ?? 0;
      mm = int.tryParse(time.substring(2, 4)) ?? 0;
      if (time.length >= 6) {
        ss = int.tryParse(time.substring(4, 6)) ?? 0;
      }
    }
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    if (hh > 23 || mm > 59 || ss > 59) return null;
    return DateTime.utc(y, m, d, hh, mm, ss);
  }
}

/// ADIF 导出器。
class AdifWriter {
  /// [freqPolicy] 为 'down' 时 FREQ 写下行频率，为 'up' 时写上行的。
  static String write(
    List<Qso> list, {
    String freqPolicy = 'down',
    String programName = 'SMPTLOG',
    String myCall = '',
  }) {
    final sb = StringBuffer();
    void field(String name, String value, {bool quoted = false}) {
      if (value.isEmpty) return;
      final v = quoted ? '<$value>' : value;
      sb.write('<$name:${v.length}>$v');
    }

    sb.write('SMPTLOG 通联日志导出\n');
    field('ADIF_VER', '3.1.4');
    field('PROGRAMID', programName);
    field('PROGRAMVERSION', '1.0');
    if (myCall.isNotEmpty) field('OPERATOR', myCall);
    field('CREATED_TIMESTAMP', _ts(DateTime.now().toUtc()));
    sb.write('<EOH>\n\n');

    for (final q in list) {
      field(AdifFields.call, q.call);
      field(AdifFields.qsoDate, _date(q.qsoTimeUtc));
      field(AdifFields.timeOn, _time(q.qsoTimeUtc));
      final freq = freqPolicy == 'up' && q.viaRepeater ? q.uplinkMhz : q.freqMhz;
      if (freq > 0) field(AdifFields.freq, freq.toStringAsFixed(6));
      field(AdifFields.band, q.band);
      field(AdifFields.mode, q.mode);
      field(AdifFields.rstSent, q.rstSent);
      field(AdifFields.rstRcvd, q.rstRcvd);
      field(AdifFields.txPwr, q.pwrSent);
      field(AdifFields.rxPwr, q.pwrRcvd);
      field(AdifFields.myAntenna, q.antenna);
      field(AdifFields.myRig, q.rig);
      field(AdifFields.qth, q.qth);
      field(AdifFields.country, q.country);
      field(AdifFields.myGridsquare, q.myGrid);
      field(AdifFields.gridsquare, q.grid);
      field(AdifFields.comment, q.remark);
      field(AdifFields.xWeather, q.weather);
      field(AdifFields.xRelayCall, q.repeaterCall);
      if (q.viaRepeater && q.repeaterDownlink > 0) {
        field(AdifFields.xRelayFreq, q.repeaterDownlink.toStringAsFixed(6));
      }
      if (q.repeaterOffset != 0) {
        field(AdifFields.xOffset, q.repeaterOffset.toStringAsFixed(6));
      }
      field(AdifFields.xCtcss, q.tone);
      field(AdifFields.xStation, q.stationName);
      field(AdifFields.xUuid, q.uuid);

      if (q.qslStatus == QslStatus.sent ||
          q.qslStatus == QslStatus.received ||
          q.qslStatus == QslStatus.confirmed) {
        field(AdifFields.qslSent, 'Y');
      }
      if (q.qslStatus == QslStatus.received ||
          q.qslStatus == QslStatus.confirmed) {
        field(AdifFields.qslRcvd, 'Y');
      }
      sb.write('<EOR>\n');
    }
    return sb.toString();
  }

  static String _date(DateTime t) {
    final u = t.toUtc();
    return '${u.year.toString().padLeft(4, '0')}'
        '${u.month.toString().padLeft(2, '0')}'
        '${u.day.toString().padLeft(2, '0')}';
  }

  static String _time(DateTime t) {
    final u = t.toUtc();
    return '${u.hour.toString().padLeft(2, '0')}'
        '${u.minute.toString().padLeft(2, '0')}'
        '${u.second.toString().padLeft(2, '0')}';
  }

  static String _ts(DateTime t) => '${_date(t)} ${_time(t)}';
}

/// 纯本地计算工具：波段、网格、距离方位角、日出日落、呼号归一化、判重。
///
/// 全部为纯 Dart 实现，不联网、不依赖任何原生插件。
library;

import 'dart:math' as math;

/// 业余波段定义（频率单位 MHz）。
class BandSpec {
  const BandSpec(this.name, this.lowMhz, this.highMhz);
  final String name;
  final double lowMhz;
  final double highMhz;
}

class Bands {
  /// 常用业余波段，按频率从高到低排列。
  static const List<BandSpec> all = [
    BandSpec('23cm', 1240.0, 1300.0),
    BandSpec('70cm', 430.0, 440.0),
    BandSpec('2m', 144.0, 148.0),
    BandSpec('6m', 50.0, 54.0),
    BandSpec('10m', 28.0, 29.7),
    BandSpec('12m', 24.89, 24.99),
    BandSpec('15m', 21.0, 21.45),
    BandSpec('17m', 18.068, 18.168),
    BandSpec('20m', 14.0, 14.35),
    BandSpec('30m', 10.1, 10.15),
    BandSpec('40m', 7.0, 7.2),
    BandSpec('60m', 5.3515, 5.3665),
    BandSpec('80m', 3.5, 3.9),
    BandSpec('160m', 1.8, 2.0),
  ];

  /// 由频率推导波段名；不在任何业余波段内则返回“未知”。
  static String fromFreq(double mhz) {
    if (mhz <= 0) return '';
    for (final b in all) {
      if (mhz >= b.lowMhz && mhz <= b.highMhz) return b.name;
    }
    return '未知';
  }

  /// 中继常用频段（含公众对讲与业务段，便于记录非业余通联）。
  static String fromFreqLoose(double mhz) {
    final strict = fromFreq(mhz);
    if (strict.isNotEmpty && strict != '未知') return strict;
    if (mhz >= 400 && mhz <= 470) return '70cm';
    if (mhz >= 136 && mhz <= 174) return '2m';
    return '未知';
  }

  static List<String> get names => all.map((e) => e.name).toList()..sort();
}

/// Maidenhead 网格定位（4 位 / 6 位）。
class GridLocator {
  /// 网格转经纬度（取网格中心点）。
  /// 返回 [纬度, 经度]，单位度；非法输入返回 null。
  static List<double>? toLatLon(String grid) {
    final g = grid.trim().toUpperCase();
    if (g.length != 4 && g.length != 6 && g.length != 8) return null;
    if (g.length == 4) {
      if (!_isAlpha(g[0]) || !_isAlpha(g[1])) return null;
      if (!_isDigit(g[2]) || !_isDigit(g[3])) return null;
    } else {
      // 6 位 / 8 位：前两位字母、三四位数字、五六位字母、七八位数字
      if (!_isAlpha(g[0]) || !_isAlpha(g[1])) return null;
      if (!_isDigit(g[2]) || !_isDigit(g[3])) return null;
      if (!_isAlpha(g[4]) || !_isAlpha(g[5])) return null;
      if (g.length == 8) {
        if (!_isDigit(g[6]) || !_isDigit(g[7])) return null;
      }
    }

    final lon = (g.codeUnitAt(0) - 65) * 20.0 - 180.0;
    final lat = (g.codeUnitAt(1) - 65) * 10.0 - 90.0;
    var lonOut = lon + (int.parse(g[2])) * 2.0;
    var latOut = lat + (int.parse(g[3])) * 1.0;

    if (g.length >= 6) {
      lonOut += (g.codeUnitAt(4) - 65) * (2.0 / 24.0);
      latOut += (g.codeUnitAt(5) - 65) * (1.0 / 24.0);
      // 取子方格中心
      lonOut += (2.0 / 24.0) / 2;
      latOut += (1.0 / 24.0) / 2;
      return [latOut, lonOut];
    }
    // 4 位网格取中心
    return [latOut + 0.5, lonOut + 1.0];
  }

  /// 经纬度转 6 位网格。
  static String fromLatLon(double lat, double lon) {
    var l = lon + 180.0;
    var b = lat + 90.0;
    if (l < 0 || l >= 360 || b < 0 || b >= 180) return '';

    final lonField = (l / 20).floor();
    final latField = (b / 10).floor();
    l -= lonField * 20;
    b -= latField * 10;

    final lonSquare = (l / 2).floor();
    final latSquare = (b / 1).floor();
    l -= lonSquare * 2;
    b -= latSquare * 1;

    final lonSub = (l / (2 / 24)).floor();
    final latSub = (b / (1 / 24)).floor();

    String alpha(int i) => String.fromCharCode(65 + i);

    return '${alpha(lonField)}${alpha(latField)}'
        '${lonSquare}${latSquare}'
        '${alpha(lonSub.clamp(0, 23))}${alpha(latSub.clamp(0, 23))}';
  }

  static bool _isAlpha(String c) => c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90;
  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
}

/// 大圆距离与方位角。
class Geo {
  static const double earthRadiusKm = 6371.0088;

  /// Haversine 距离（公里）。
  static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// 初始方位角（度，0=正北，顺时针）。
  static double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
    final dLon = _rad(lon2 - lon1);
    final y = math.sin(dLon) * math.cos(_rad(lat2));
    final x = math.cos(_rad(lat1)) * math.sin(_rad(lat2)) -
        math.sin(_rad(lat1)) * math.cos(_rad(lat2)) * math.cos(dLon);
    final deg = _deg(math.atan2(y, x));
    return (deg + 360) % 360;
  }

  /// 由两个网格计算距离与方位角。
  static ({double distanceKm, double bearing})? betweenGrids(String g1, String g2) {
    final a = GridLocator.toLatLon(g1);
    final b = GridLocator.toLatLon(g2);
    if (a == null || b == null) return null;
    return (
      distanceKm: distanceKm(a[0], a[1], b[0], b[1]),
      bearing: bearingDeg(a[0], a[1], b[0], b[1]),
    );
  }

  static String bearingLabel(double deg) {
    const dirs = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    final idx = (((deg % 360) + 22.5) ~/ 45) % 8;
    return dirs[idx];
  }

  static double _rad(double d) => d * math.pi / 180.0;
  static double _deg(double r) => r * 180.0 / math.pi;
}

/// 太阳位置、日出日落与明暗线（本地算法，不联网）。
class Solar {
  /// 返回当日日出/日落（UTC）。极昼极夜返回 null。
  static ({DateTime? sunrise, DateTime? sunset}) riseSet(
    DateTime dateUtc,
    double lat,
    double lon,
  ) {
    final dayOfYear = _dayOfYear(dateUtc);
    final lngHour = lon / 15.0;

    DateTime? calc(bool rising) {
      final t = dayOfYear + ((rising ? 6 : 18) - lngHour) / 24.0;
      final m = 0.9856 * t - 3.289;
      var l = m +
          1.916 * math.sin(_rad(m)) +
          0.020 * math.sin(_rad(2 * m)) +
          282.634;
      l = (l + 360) % 360;

      var ra = _deg(math.atan(0.91764 * math.tan(_rad(l))));
      ra = (ra + 360) % 360;
      final lQuadrant = (l / 90).floor() * 90.0;
      final raQuadrant = (ra / 90).floor() * 90.0;
      ra = ra + (lQuadrant - raQuadrant);
      ra = ra / 15.0;

      final sinDec = 0.39782 * math.sin(_rad(l));
      final cosDec = math.cos(math.asin(sinDec));
      final cosH =
          (math.cos(_rad(90.833)) - sinDec * math.sin(_rad(lat))) /
              (cosDec * math.cos(_rad(lat)));
      if (cosH > 1 || cosH < -1) return null;

      final h = rising ? 360 - _deg(math.acos(cosH)) : _deg(math.acos(cosH));
      final hh = h / 15.0;
      final tt = hh + ra - 0.06571 * t - 6.622;
      var ut = (tt - lngHour) % 24;
      if (ut < 0) ut += 24;

      final base = DateTime.utc(
        dateUtc.toUtc().year,
        dateUtc.toUtc().month,
        dateUtc.toUtc().day,
      );
      return base.add(Duration(seconds: (ut * 3600).round()));
    }

    return (sunrise: calc(true), sunset: calc(false));
  }

  /// 太阳直射点经纬度（用于绘制明暗线）。
  static List<double> subsolarPoint(DateTime tUtc) {
    final utc = tUtc.toUtc();
    final doy = _dayOfYear(utc);
    final decl = -23.44 * math.cos(_rad(360.0 / 365.0 * (doy + 10)));
    final minutes = utc.hour * 60 + utc.minute + utc.second / 60.0;
    var lon = 180.0 - minutes / 4.0;
    if (lon < -180) lon += 360;
    return [decl, lon];
  }

  static int _dayOfYear(DateTime d) {
    final utc = d.toUtc();
    return utc.difference(DateTime.utc(utc.year)).inDays + 1;
  }

  static double _rad(double d) => d * math.pi / 180.0;

  static double _deg(double r) => r * 180.0 / math.pi;
}

/// 呼号处理。
class Callsign {
  /// 归一化：去空格、转大写。
  static String normalize(String raw) =>
      raw.trim().toUpperCase().replaceAll(' ', '');

  /// 去掉 /P、/M、/MM、/AM、/QRP 等操作后缀，以及前缀形式 P/。
  static String base(String raw) {
    var s = normalize(raw);
    if (s.isEmpty) return s;
    final parts = s.split('/');
    if (parts.length == 1) return s;
    // 取最长的一段作为主呼号
    parts.sort((a, b) => b.length.compareTo(a.length));
    var best = parts.first;
    for (final p in parts) {
      if (p.length >= best.length) best = p;
    }
    // 纯数字段（如 /1 区域号）不作为主呼号
    if (RegExp(r'^\d+$').hasMatch(best)) {
      best = parts.firstWhere(
        (p) => !RegExp(r'^\d+$').hasMatch(p),
        orElse: () => s,
      );
    }
    return best;
  }

  /// 粗略判断是否为中国呼号（B/BD/BG/BH/BI/BY 开头）。
  static bool isChina(String raw) {
    final b = base(raw);
    return RegExp(r'^B[YZIDGH]?[A-Z]?\d').hasMatch(b) || b.startsWith('B');
  }
}

/// 重复 QSO 判定。
class DupDetector {
  /// 判重键：归一化呼号 + 波段 + 模式。
  static String key({
    required String call,
    required String band,
    required String mode,
  }) =>
      '${Callsign.base(call)}|$band|$mode';

  /// 阈值分钟数，0 表示不判重。
  static bool isDup({
    required DateTime a,
    required DateTime b,
    required int windowMinutes,
  }) {
    if (windowMinutes <= 0) return false;
    return a.difference(b).abs() <= Duration(minutes: windowMinutes);
  }
}

/// 通用格式化与工具。
class Fmt {
  static String two(int v) => v < 10 ? '0$v' : '$v';

  static String dateUtc(DateTime t) {
    final u = t.toUtc();
    return '${u.year}-${two(u.month)}-${two(u.day)}';
  }

  static String timeUtc(DateTime t) {
    final u = t.toUtc();
    return '${two(u.hour)}:${two(u.minute)}';
  }

  static String dateTimeUtc(DateTime t) => '${dateUtc(t)} ${timeUtc(t)}';

  static String local(DateTime t) {
    final l = t.toLocal();
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  /// 频率显示：至少 3 位小数，最多 6 位。
  static String freq(double mhz) {
    if (mhz <= 0) return '';
    var s = mhz.toStringAsFixed(6);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = '${s}0';
    final dot = s.indexOf('.');
    if (dot >= 0 && s.length - dot - 1 < 3) {
      s = s.padRight(dot + 4, '0');
    }
    return s;
  }

  static String distance(double km) {
    if (km <= 0) return '';
    return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
  }
}

/// 轻量 UUID（v4 形式），不引入 uuid 包。
class IdGen {
  static final math.Random _r = math.Random.secure();

  static String uuid() {
    final b = List<int>.generate(16, (_) => _r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final hex = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  static String short() => uuid().replaceAll('-', '').substring(0, 12);
}

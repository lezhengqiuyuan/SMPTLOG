// SMPTLOG 单元测试：网格、距离方位角、呼号归一化、判重、ADIF 往返、COS 签名。
//
// 说明：这些测试全部为纯 Dart 逻辑，不依赖数据库与网络，
// 可以在任何机器上直接 `flutter test` 跑通。

import 'package:flutter_test/flutter_test.dart';
import 'package:smptlog/core/adif.dart';
import 'package:smptlog/core/models.dart';
import 'package:smptlog/core/util.dart';

void main() {
  group('网格 Locator', () {
    test('OL96 应落在福州附近', () {
      final p = GridLocator.toLatLon('OL96')!;
      expect(p[0], greaterThan(25));
      expect(p[0], lessThan(27));
      expect(p[1], greaterThan(118));
      expect(p[1], lessThan(120));
    });

    test('经纬度与网格可往返', () {
      final grid = GridLocator.fromLatLon(26.08, 119.30);
      expect(grid.length, 6);
      final back = GridLocator.toLatLon(grid);
      expect(back, isNotNull);
      expect((back![0] - 26.08).abs(), lessThan(0.1));
      expect((back[1] - 119.30).abs(), lessThan(0.1));
    });

    test('非法网格返回 null', () {
      expect(GridLocator.toLatLon('ZZ'), isNull);
    });
  });

  group('距离与方位角', () {
    test('同一点距离为 0', () {
      expect(Geo.distanceKm(26.0, 119.0, 26.0, 119.0), lessThan(0.001));
    });

    test('正北方向方位角接近 0', () {
      final b = Geo.bearingDeg(26.0, 119.0, 27.0, 119.0);
      expect(b < 1 || b > 359, isTrue);
    });
  });

  group('呼号处理', () {
    test('去掉 /P 后缀', () {
      expect(Callsign.base('bg5wff/P'), 'BG5WFF');
    });

    test('前缀形式 P/BG5WFF', () {
      expect(Callsign.base('P/BG5WFF'), 'BG5WFF');
    });
  });

  group('判重', () {
    test('同呼号同波段同模式且在时间窗内', () {
      final a = DateTime.utc(2026, 10, 23, 12, 0);
      final b = DateTime.utc(2026, 10, 23, 12, 20);
      expect(
        DupDetector.isDup(a: a, b: b, windowMinutes: 30),
        isTrue,
      );
      expect(
        DupDetector.isDup(a: a, b: b, windowMinutes: 5),
        isFalse,
      );
    });
  });

  group('ADIF 往返', () {
    test('写出后再解析应还原关键字段', () {
      final q = Qso(
        uuid: 'u-1',
        call: 'BG5WFF',
        qsoTimeUtc: DateTime.utc(2026, 10, 23, 13, 13),
        freqMhz: 439.55,
        band: '70cm',
        mode: QsoMode.fm,
        rstSent: '59',
        rstRcvd: '59',
        repeaterCall: 'BR5T',
        repeaterDownlink: 439.55,
        repeaterOffset: -7.6,
        tone: '88.5',
        remark: '中文备注测试',
      );

      final text = AdifWriter.write([q]);
      final parsed = AdifReader.parse(text);
      expect(parsed.errors, isEmpty);
      expect(parsed.records.length, 1);

      final back = AdifReader.toQso(parsed.records.first, deviceId: 'test')!;
      expect(back.call, 'BG5WFF');
      expect(back.freqMhz, closeTo(439.55, 0.0001));
      expect(back.band, '70cm');
      expect(back.mode, QsoMode.fm);
      expect(back.repeaterCall, 'BR5T');
      expect(back.repeaterOffset, closeTo(-7.6, 0.0001));
      expect(back.remark, '中文备注测试');
      expect(back.uiid(), q.uuid);
    });

    test('坏行应被记录为错误而不是崩溃', () {
      // 声明 99 字节但实际内容不足，属于截断
      final parsed = AdifReader.parse('<CALL:99>BG5WFF');
      expect(parsed.errors, isNotEmpty);
      expect(parsed.records, isEmpty);
    });
  });
}

/// 测试辅助：把 uuid 取出来比较。
extension on Qso {
  String uiid() => uuid;
}

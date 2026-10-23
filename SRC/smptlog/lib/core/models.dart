/// SMPTLOG 数据模型层。
///
/// 所有模型手写 toJson/fromJson，不依赖 build_runner 代码生成，
/// 保证任何一次构建都不会因为生成器版本变化而失败。
library;

/// 通联模式常量。
class QsoMode {
  static const am = 'AM';
  static const fm = 'FM';
  static const ssb = 'SSB';
  static const usb = 'USB';
  static const lsb = 'LSB';
  static const cw = 'CW';
  static const rtty = 'RTTY';
  static const ft8 = 'FT8';
  static const ft4 = 'FT4';
  static const dmr = 'DMR';
  static const dstar = 'D-STAR';
  static const c4fm = 'C4FM';
  static const p25 = 'P25';
  static const tetra = 'TETRA';
  static const fsk4 = 'FSK4';
  static const olivia = 'OLIVIA';

  static const all = <String>[
    am, fm, ssb, usb, lsb, cw, rtty, ft8, ft4,
    dmr, dstar, c4fm, p25, tetra, fsk4, olivia,
  ];
}

/// QSL 卡片状态。
class QslStatus {
  static const none = 0;
  static const sent = 1;
  static const received = 2;
  static const confirmed = 3;

  static const all = <int>[none, sent, received, confirmed];

  static String label(int v) {
    switch (v) {
      case sent:
        return '已发出';
      case received:
        return '已收到';
      case confirmed:
        return '已确认';
      default:
        return '未确认';
    }
  }
}

String _str(dynamic v, [String def = '']) => v == null ? def : v.toString();

int _int(dynamic v, [int def = 0]) {
  if (v == null) return def;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? def;
}

double _dbl(dynamic v, [double def = 0]) {
  if (v == null) return def;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? def;
}

bool _bool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

DateTime _utc(dynamic v) =>
    DateTime.fromMillisecondsSinceEpoch(_int(v), isUtc: true);

/// 一条通联记录。`updatedAt` 是同步合并的唯一裁决依据。
class Qso {
  Qso({
    required this.uuid,
    required this.call,
    required this.qsoTimeUtc,
    required this.freqMhz,
    required this.band,
    required this.mode,
    this.rstSent = '',
    this.rstRcvd = '',
    this.pwrSent = '',
    this.pwrRcvd = '',
    this.antenna = '',
    this.rig = '',
    this.qth = '',
    this.country = '',
    this.myGrid = '',
    this.grid = '',
    this.qslStatus = QslStatus.none,
    this.remark = '',
    this.weather = '',
    this.repeaterId = '',
    this.repeaterCall = '',
    this.repeaterDownlink = 0,
    this.repeaterOffset = 0,
    this.tone = '',
    this.stationId = '',
    this.stationName = '',
    this.myCall = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deleted = false,
    this.deviceId = '',
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String uuid;
  final String call;
  final DateTime qsoTimeUtc;
  final double freqMhz;
  final String band;
  final String mode;
  final String rstSent;
  final String rstRcvd;
  final String pwrSent;
  final String pwrRcvd;
  final String antenna;
  final String rig;
  final String qth;
  final String country;
  final String myGrid;
  final String grid;
  final int qslStatus;
  final String remark;
  final String weather;
  final String repeaterId;
  final String repeaterCall;
  final double repeaterDownlink;
  final double repeaterOffset;
  final String tone;
  final String stationId;
  final String stationName;
  final String myCall;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;
  final String deviceId;

  /// 上行频率 = 下行 + 偏移。
  double get uplinkMhz => repeaterDownlink + repeaterOffset;

  bool get viaRepeater => repeaterId.isNotEmpty || repeaterCall.isNotEmpty;

  Qso copyWith({
    String? call,
    DateTime? qsoTimeUtc,
    double? freqMhz,
    String? band,
    String? mode,
    String? rstSent,
    String? rstRcvd,
    String? pwrSent,
    String? pwrRcvd,
    String? antenna,
    String? rig,
    String? qth,
    String? country,
    String? myGrid,
    String? grid,
    int? qslStatus,
    String? remark,
    String? weather,
    String? repeaterId,
    String? repeaterCall,
    double? repeaterDownlink,
    double? repeaterOffset,
    String? tone,
    String? stationId,
    String? stationName,
    String? myCall,
    DateTime? updatedAt,
    bool? deleted,
    String? deviceId,
  }) {
    return Qso(
      uuid: uuid,
      call: call ?? this.call,
      qsoTimeUtc: qsoTimeUtc ?? this.qsoTimeUtc,
      freqMhz: freqMhz ?? this.freqMhz,
      band: band ?? this.band,
      mode: mode ?? this.mode,
      rstSent: rstSent ?? this.rstSent,
      rstRcvd: rstRcvd ?? this.rstRcvd,
      pwrSent: pwrSent ?? this.pwrSent,
      pwrRcvd: pwrRcvd ?? this.pwrRcvd,
      antenna: antenna ?? this.antenna,
      rig: rig ?? this.rig,
      qth: qth ?? this.qth,
      country: country ?? this.country,
      myGrid: myGrid ?? this.myGrid,
      grid: grid ?? this.grid,
      qslStatus: qslStatus ?? this.qslStatus,
      remark: remark ?? this.remark,
      weather: weather ?? this.weather,
      repeaterId: repeaterId ?? this.repeaterId,
      repeaterCall: repeaterCall ?? this.repeaterCall,
      repeaterDownlink: repeaterDownlink ?? this.repeaterDownlink,
      repeaterOffset: repeaterOffset ?? this.repeaterOffset,
      tone: tone ?? this.tone,
      stationId: stationId ?? this.stationId,
      stationName: stationName ?? this.stationName,
      myCall: myCall ?? this.myCall,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'call': call,
        'qso_time_utc': qsoTimeUtc.toUtc().millisecondsSinceEpoch,
        'freq_mhz': freqMhz,
        'band': band,
        'mode': mode,
        'rst_sent': rstSent,
        'rst_rcvd': rstRcvd,
        'pwr_sent': pwrSent,
        'pwr_rcvd': pwrRcvd,
        'antenna': antenna,
        'rig': rig,
        'qth': qth,
        'country': country,
        'my_grid': myGrid,
        'grid': grid,
        'qsl_status': qslStatus,
        'remark': remark,
        'weather': weather,
        'repeater_id': repeaterId,
        'repeater_call': repeaterCall,
        'repeater_downlink': repeaterDownlink,
        'repeater_offset': repeaterOffset,
        'tone': tone,
        'station_id': stationId,
        'station_name': stationName,
        'my_call': myCall,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'updated_at': updatedAt.toUtc().millisecondsSinceEpoch,
        'deleted': deleted,
        'device_id': deviceId,
      };

  static Qso fromJson(Map<String, dynamic> j) => Qso(
        uuid: _str(j['uuid']),
        call: _str(j['call']),
        qsoTimeUtc: _utc(j['qso_time_utc']),
        freqMhz: _dbl(j['freq_mhz']),
        band: _str(j['band']),
        mode: _str(j['mode']),
        rstSent: _str(j['rst_sent']),
        rstRcvd: _str(j['rst_rcvd']),
        pwrSent: _str(j['pwr_sent']),
        pwrRcvd: _str(j['pwr_rcvd']),
        antenna: _str(j['antenna']),
        rig: _str(j['rig']),
        qth: _str(j['qth']),
        country: _str(j['country']),
        myGrid: _str(j['my_grid']),
        grid: _str(j['grid']),
        qslStatus: _int(j['qsl_status']),
        remark: _str(j['remark']),
        weather: _str(j['weather']),
        repeaterId: _str(j['repeater_id']),
        repeaterCall: _str(j['repeater_call']),
        repeaterDownlink: _dbl(j['repeater_downlink']),
        repeaterOffset: _dbl(j['repeater_offset']),
        tone: _str(j['tone']),
        stationId: _str(j['station_id']),
        stationName: _str(j['station_name']),
        myCall: _str(j['my_call']),
        createdAt: _utc(j['created_at']),
        updatedAt: _utc(j['updated_at']),
        deleted: _bool(j['deleted']),
        deviceId: _str(j['device_id']),
      );
}

/// 中继台档案。
class Repeater {
  Repeater({
    required this.id,
    required this.name,
    this.call = '',
    required this.downlink,
    this.offset = 0,
    this.txTone = '',
    this.rxTone = '',
    this.mode = QsoMode.fm,
    this.band = '',
    this.colorCode = '',
    this.reflector = '',
    this.qth = '',
    this.locator = '',
    this.openTime = '',
    this.note = '',
    this.isFavorite = false,
    this.timesUsed = 0,
    this.lastUsed,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deleted = false,
    this.deviceId = '',
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final String name;
  final String call;
  final double downlink;
  final double offset;
  final String txTone;
  final String rxTone;
  final String mode;
  final String band;
  final String colorCode;
  final String reflector;
  final String qth;
  final String locator;
  final String openTime;
  final String note;
  final bool isFavorite;
  final int timesUsed;
  final DateTime? lastUsed;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;
  final String deviceId;

  double get uplink => downlink + offset;

  Repeater copyWith({
    String? name,
    String? call,
    double? downlink,
    double? offset,
    String? txTone,
    String? rxTone,
    String? mode,
    String? band,
    String? colorCode,
    String? reflector,
    String? qth,
    String? locator,
    String? openTime,
    String? note,
    bool? isFavorite,
    int? timesUsed,
    DateTime? lastUsed,
    DateTime? updatedAt,
    bool? deleted,
  }) =>
      Repeater(
        id: id,
        name: name ?? this.name,
        call: call ?? this.call,
        downlink: downlink ?? this.downlink,
        offset: offset ?? this.offset,
        txTone: txTone ?? this.txTone,
        rxTone: rxTone ?? this.rxTone,
        mode: mode ?? this.mode,
        band: band ?? this.band,
        colorCode: colorCode ?? this.colorCode,
        reflector: reflector ?? this.reflector,
        qth: qth ?? this.qth,
        locator: locator ?? this.locator,
        openTime: openTime ?? this.openTime,
        note: note ?? this.note,
        isFavorite: isFavorite ?? this.isFavorite,
        timesUsed: timesUsed ?? this.timesUsed,
        lastUsed: lastUsed ?? this.lastUsed,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
        deviceId: deviceId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'call': call,
        'downlink': downlink,
        'offset': offset,
        'tx_tone': txTone,
        'rx_tone': rxTone,
        'mode': mode,
        'band': band,
        'color_code': colorCode,
        'reflector': reflector,
        'qth': qth,
        'locator': locator,
        'open_time': openTime,
        'note': note,
        'is_favorite': isFavorite,
        'times_used': timesUsed,
        'last_used': lastUsed?.toUtc().millisecondsSinceEpoch,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'updated_at': updatedAt.toUtc().millisecondsSinceEpoch,
        'deleted': deleted,
        'device_id': deviceId,
      };

  static Repeater fromJson(Map<String, dynamic> j) {
    final lu = j['last_used'];
    return Repeater(
      id: _str(j['id']),
      name: _str(j['name']),
      call: _str(j['call']),
      downlink: _dbl(j['downlink']),
      offset: _dbl(j['offset']),
      txTone: _str(j['tx_tone']),
      rxTone: _str(j['rx_tone']),
      mode: _str(j['mode'], QsoMode.fm),
      band: _str(j['band']),
      colorCode: _str(j['color_code']),
      reflector: _str(j['reflector']),
      qth: _str(j['qth']),
      locator: _str(j['locator']),
      openTime: _str(j['open_time']),
      note: _str(j['note']),
      isFavorite: _bool(j['is_favorite']),
      timesUsed: _int(j['times_used']),
      lastUsed: lu == null ? null : _utc(lu),
      createdAt: _utc(j['created_at']),
      updatedAt: _utc(j['updated_at']),
      deleted: _bool(j['deleted']),
      deviceId: _str(j['device_id']),
    );
  }
}

/// 电台档案（手持机 / 车台 / 基地台 / 代录）。
class StationProfile {
  StationProfile({
    required this.id,
    required this.name,
    this.myCall = '',
    this.myGrid = '',
    this.rig = '',
    this.antenna = '',
    this.power = '',
    this.qth = '',
    this.isDefault = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deleted = false,
    this.deviceId = '',
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final String name;
  final String myCall;
  final String myGrid;
  final String rig;
  final String antenna;
  final String power;
  final String qth;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;
  final String deviceId;

  StationProfile copyWith({
    String? name,
    String? myCall,
    String? myGrid,
    String? rig,
    String? antenna,
    String? power,
    String? qth,
    bool? isDefault,
    DateTime? updatedAt,
    bool? deleted,
  }) =>
      StationProfile(
        id: id,
        name: name ?? this.name,
        myCall: myCall ?? this.myCall,
        myGrid: myGrid ?? this.myGrid,
        rig: rig ?? this.rig,
        antenna: antenna ?? this.antenna,
        power: power ?? this.power,
        qth: qth ?? this.qth,
        isDefault: isDefault ?? this.isDefault,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
        deviceId: deviceId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'my_call': myCall,
        'my_grid': myGrid,
        'rig': rig,
        'antenna': antenna,
        'power': power,
        'qth': qth,
        'is_default': isDefault,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'updated_at': updatedAt.toUtc().millisecondsSinceEpoch,
        'deleted': deleted,
        'device_id': deviceId,
      };

  static StationProfile fromJson(Map<String, dynamic> j) => StationProfile(
        id: _str(j['id']),
        name: _str(j['name']),
        myCall: _str(j['my_call']),
        myGrid: _str(j['my_grid']),
        rig: _str(j['rig']),
        antenna: _str(j['antenna']),
        power: _str(j['power']),
        qth: _str(j['qth']),
        isDefault: _bool(j['is_default']),
        createdAt: _utc(j['created_at']),
        updatedAt: _utc(j['updated_at']),
        deleted: _bool(j['deleted']),
        deviceId: _str(j['device_id']),
      );
}

/// 冲突副本：同步时被覆盖的一方留底，供人工裁决。
class ConflictEntry {
  ConflictEntry({
    required this.id,
    required this.dataset,
    required this.uuid,
    required this.loserJson,
    required this.winnerUpdatedAt,
    required this.loserUpdatedAt,
    required this.sourceDevice,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  final int id;
  final String dataset;
  final String uuid;
  final Map<String, dynamic> loserJson;
  final DateTime winnerUpdatedAt;
  final DateTime loserUpdatedAt;
  final String sourceDevice;
  final DateTime createdAt;
}

/// 同步水位与设备信息。
class SyncState {
  SyncState({
    this.deviceId = '',
    this.lastSyncAt,
    this.lastError = '',
    this.remoteRev = 0,
  });

  final String deviceId;
  final DateTime? lastSyncAt;
  final String lastError;
  final int remoteRev;

  SyncState copyWith({
    String? deviceId,
    DateTime? lastSyncAt,
    String? lastError,
    int? remoteRev,
  }) =>
      SyncState(
        deviceId: deviceId ?? this.deviceId,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        lastError: lastError ?? this.lastError,
        remoteRev: remoteRev ?? this.remoteRev,
      );
}

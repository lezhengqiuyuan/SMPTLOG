/// 新建 / 编辑通联记录。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/util.dart';
import '../state.dart';
import 'common.dart';
import 'theme.dart';

class QsoEditPage extends StatefulWidget {
  const QsoEditPage({super.key, this.initial});

  final Qso? initial;

  @override
  State<QsoEditPage> createState() => _QsoEditPageState();
}

class _QsoEditPageState extends State<QsoEditPage> {
  late final TextEditingController _call;
  late final TextEditingController _freq;
  late final TextEditingController _rstSent;
  late final TextEditingController _rstRcvd;
  late final TextEditingController _pwrSent;
  late final TextEditingController _pwrRcvd;
  late final TextEditingController _antenna;
  late final TextEditingController _rig;
  late final TextEditingController _qth;
  late final TextEditingController _country;
  late final TextEditingController _myGrid;
  late final TextEditingController _grid;
  late final TextEditingController _remark;
  late final TextEditingController _weather;

  final _callFocus = FocusNode();
  final _freqFocus = FocusNode();
  final _rstFocus = FocusNode();

  DateTime _timeUtc = DateTime.now().toUtc();
  String _mode = QsoMode.fm;
  int _qsl = QslStatus.none;
  bool _viaRepeater = false;
  String _repeaterId = '';
  String _repeaterCall = '';
  double _downlink = 0;
  double _offset = 0;
  String _tone = '';
  String _stationId = '';
  String _stationName = '';

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final q = widget.initial;
    _call = TextEditingController(text: q?.call ?? '');
    _freq = TextEditingController(text: q == null ? '' : Fmt.freq(q.freqMhz));
    _rstSent = TextEditingController(text: q?.rstSent ?? '59');
    _rstRcvd = TextEditingController(text: q?.rstRcvd ?? '59');
    _pwrSent = TextEditingController(text: q?.pwrSent ?? '');
    _pwrRcvd = TextEditingController(text: q?.pwrRcvd ?? '');
    _antenna = TextEditingController(text: q?.antenna ?? '');
    _rig = TextEditingController(text: q?.rig ?? '');
    _qth = TextEditingController(text: q?.qth ?? '');
    _country = TextEditingController(text: q?.country ?? '');
    _myGrid = TextEditingController(text: q?.myGrid ?? '');
    _grid = TextEditingController(text: q?.grid ?? '');
    _remark = TextEditingController(text: q?.remark ?? '');
    _weather = TextEditingController(text: q?.weather ?? '');

    if (q != null) {
      _timeUtc = q.qsoTimeUtc;
      _mode = q.mode;
      _qsl = q.qslStatus;
      _viaRepeater = q.viaRepeater;
      _repeaterId = q.repeaterId;
      _repeaterCall = q.repeaterCall;
      _downlink = q.repeaterDownlink;
      _offset = q.repeaterOffset;
      _tone = q.tone;
      _stationId = q.stationId;
      _stationName = q.stationName;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final stations = context.read<AppState>().db.allStations();
        final def = stations.where((e) => e.isDefault).toList();
        if (def.isNotEmpty) {
          setState(() {
            _stationId = def.first.id;
            _stationName = def.first.name;
            _myGrid.text = def.first.myGrid;
            _rig.text = def.first.rig;
            _antenna.text = def.first.antenna;
            _pwrSent.text = def.first.power;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      _call, _freq, _rstSent, _rstRcvd, _pwrSent, _pwrRcvd, _antenna,
      _rig, _qth, _country, _myGrid, _grid, _remark, _weather,
    ]) {
      c.dispose();
    }
    _callFocus.dispose();
    _freqFocus.dispose();
    _rstFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final repeaters = app.db.allRepeaters();
    final stations = app.db.allStations();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑通联' : '新建通联'),
        actions: [
          if (!_isEdit)
            TextButton.icon(
              onPressed: _saveAndContinue,
              icon: const Icon(Icons.playlist_add, size: 18),
              label: const Text('保存并继续'),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 12),
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('保存'),
            ),
          ),
        ],
      ),
      body: PageBody(
        maxWidth: 1040,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            SectionCard(
              title: '基本信息',
              child: FormGrid(
                children: [
                  LabeledField(
                    label: '日期（UTC）',
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(Fmt.dateUtc(_timeUtc)),
                      ),
                    ),
                  ),
                  LabeledField(
                    label: '时间（UTC）',
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('${Fmt.timeUtc(_timeUtc)} UTC'),
                      ),
                    ),
                  ),
                  LabeledField(
                    label: '天气（可选）',
                    child: TextField(
                      controller: _weather,
                      decoration: const InputDecoration(hintText: '例如 晴'),
                    ),
                  ),
                  LabeledField(
                    label: '电台档案',
                    child: AppDropdown<String>(
                      value: _stationId.isEmpty ? null : _stationId,
                      hint: '不指定',
                      items: [
                        const DropdownMenuItem(value: '', child: Text('不指定')),
                        ...stations.map(
                          (s) => DropdownMenuItem(value: s.id, child: Text(s.name)),
                        ),
                      ],
                      onChanged: (v) => _applyStation(v ?? '', stations),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: '通联信息',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FormGrid(
                    children: [
                      LabeledField(
                        label: '对方呼号',
                        child: TextField(
                          controller: _call,
                          focusNode: _callFocus,
                          autofocus: !_isEdit,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(hintText: '例如 BG5WFF'),
                          onSubmitted: (_) => _freqFocus.requestFocus(),
                        ),
                      ),
                      LabeledField(
                        label: '频率',
                        child: TextField(
                          controller: _freq,
                          focusNode: _freqFocus,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            hintText: '例如 438.500',
                            suffixText: 'MHz',
                            helperText: '波段：${_bandOf(_freq.text)}',
                          ),
                          onChanged: (_) => _syncFreqToRepeater(),
                          onSubmitted: (_) => _rstFocus.requestFocus(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '模式',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSub),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: QsoMode.all
                        .map(
                          (m) => ChoiceChip(
                            label: Text(m),
                            selected: _mode == m,
                            onSelected: (_) => setState(() => _mode = m),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: '中继台',
              trailing: Switch(
                value: _viaRepeater,
                onChanged: (v) => _toggleRepeater(v, repeaters),
              ),
              child: _viaRepeater
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LabeledField(
                          label: '选择中继台',
                          child: AppDropdown<String>(
                            value: _repeaterId.isEmpty ? null : _repeaterId,
                            hint: '手动填写',
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('手动填写'),
                              ),
                              ...repeaters.map(
                                (r) => DropdownMenuItem(
                                  value: r.id,
                                  child: Text(
                                    '${r.name}  ${Fmt.freq(r.downlink)} '
                                    '(${r.offset >= 0 ? '+' : ''}'
                                    '${r.offset.toStringAsFixed(3)})',
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (v) => _applyRepeater(v ?? '', repeaters),
                            optionBuilder: (item) {
                              if (item.value == '') {
                                return const AppPickerOption(
                                  value: '',
                                  label: '手动填写',
                                  subtitle: '不关联中继台档案，直接填频率与亚音',
                                );
                              }
                              final rep = repeaters.firstWhere(
                                (e) => e.id == item.value,
                                orElse: () => repeaters.first,
                              );
                              final isDef =
                                  app.defaultRepeaterId == rep.id;
                              return AppPickerOption(
                                value: item.value as String,
                                label: rep.name,
                                subtitle: '下行 ${Fmt.freq(rep.downlink)} MHz'
                                    ' · 偏移 ${rep.offset >= 0 ? '+' : ''}'
                                    '${rep.offset.toStringAsFixed(3)}'
                                    '${rep.txTone.isEmpty ? '' : ' · 亚音 ${rep.txTone}'}',
                                badge: isDef
                                    ? '默认'
                                    : (rep.isFavorite ? '常用' : null),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        FormGrid(
                          minItemWidth: 200,
                          maxColumns: 3,
                          children: [
                            LabeledField(
                              label: '中继呼号',
                              child: TextField(
                                controller: TextEditingController(
                                  text: _repeaterCall,
                                ),
                                decoration: const InputDecoration(isDense: true),
                                onChanged: (v) => _repeaterCall = v,
                              ),
                            ),
                            LabeledField(
                              label: '下行 MHz',
                              child: TextField(
                                controller: TextEditingController(
                                  text: _downlink == 0
                                      ? ''
                                      : _downlink.toStringAsFixed(4),
                                ),
                                decoration: const InputDecoration(isDense: true),
                                onChanged: (v) =>
                                    _downlink = double.tryParse(v) ?? 0,
                              ),
                            ),
                            LabeledField(
                              label: '上行偏移 MHz',
                              child: TextField(
                                controller: TextEditingController(
                                  text: _offset == 0
                                      ? ''
                                      : _offset.toStringAsFixed(4),
                                ),
                                decoration: const InputDecoration(isDense: true),
                                onChanged: (v) =>
                                    _offset = double.tryParse(v) ?? 0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: LabeledField(
                                label: '亚音 / 色码',
                                child: TextField(
                                  controller: TextEditingController(text: _tone),
                                  decoration:
                                      const InputDecoration(isDense: true),
                                  onChanged: (v) => _tone = v,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Padding(
                              padding: const EdgeInsets.only(top: 22),
                              child: TagPill(
                                '上行 ${(_downlink + _offset).toStringAsFixed(4)} MHz',
                                color: AppColors.accent,
                                dense: false,
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Text(
                      _defaultRepeaterHint(app),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSub,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: '信号报告与功率',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FormGrid(
                    minItemWidth: 160,
                    maxColumns: 4,
                    children: [
                      LabeledField(
                        label: 'RST 己方发',
                        child: TextField(
                          controller: _rstSent,
                          focusNode: _rstFocus,
                          decoration: const InputDecoration(isDense: true),
                          onSubmitted: (_) => _saveAndContinue(),
                        ),
                      ),
                      LabeledField(
                        label: 'RST 对方发',
                        child: TextField(
                          controller: _rstRcvd,
                          decoration: const InputDecoration(isDense: true),
                        ),
                      ),
                      LabeledField(
                        label: '功率 己方 (W)',
                        child: TextField(
                          controller: _pwrSent,
                          decoration: const InputDecoration(isDense: true),
                        ),
                      ),
                      LabeledField(
                        label: '功率 对方 (W)',
                        child: TextField(
                          controller: _pwrRcvd,
                          decoration: const InputDecoration(isDense: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final v in ['59', '599'])
                        ActionChip(
                          label: Text(v),
                          onPressed: () => setState(() {
                            _rstSent.text = v;
                            _rstRcvd.text = v;
                          }),
                        ),
                      const SizedBox(width: 8),
                      for (final v in ['5', '25', '100'])
                        ActionChip(
                          label: Text('${v}W'),
                          onPressed: () => setState(() {
                            if (_pwrSent.text.isEmpty) {
                              _pwrSent.text = v;
                            } else {
                              _pwrRcvd.text = v;
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: '其他信息',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FormGrid(
                    children: [
                      LabeledField(
                        label: '天馈',
                        child: TextField(
                          controller: _antenna,
                          decoration: const InputDecoration(
                            hintText: '例如 车载 / 玻璃钢',
                            isDense: true,
                          ),
                        ),
                      ),
                      LabeledField(
                        label: '设备',
                        child: TextField(
                          controller: _rig,
                          decoration: const InputDecoration(
                            hintText: '例如 UV-5R',
                            isDense: true,
                          ),
                        ),
                      ),
                      LabeledField(
                        label: '对方位置 QTH',
                        child: TextField(
                          controller: _qth,
                          decoration: const InputDecoration(isDense: true),
                        ),
                      ),
                      LabeledField(
                        label: '对方网格',
                        child: TextField(
                          controller: _grid,
                          decoration: const InputDecoration(
                            hintText: '例如 OL96',
                            isDense: true,
                          ),
                        ),
                      ),
                      LabeledField(
                        label: '国家 / 地区',
                        child: TextField(
                          controller: _country,
                          decoration: const InputDecoration(
                            hintText: '例如 中国 福建',
                            isDense: true,
                          ),
                        ),
                      ),
                      LabeledField(
                        label: '己方网格',
                        child: TextField(
                          controller: _myGrid,
                          decoration: const InputDecoration(
                            hintText: '例如 OL96',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'QSL 状态',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSub),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: QslStatus.all
                        .map(
                          (s) => ChoiceChip(
                            label: Text(QslStatus.label(s)),
                            selected: _qsl == s,
                            onSelected: (_) => setState(() => _qsl = s),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  LabeledField(
                    label: '备注',
                    child: TextField(
                      controller: _remark,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: '通联内容、设备状态、约定事项…',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _bandOf(String freq) {
    final v = double.tryParse(freq) ?? 0;
    return v <= 0 ? '未知' : Bands.fromFreqLoose(v);
  }

  /// 开关「通过中继」：打开时若已设默认中继，自动带入。
  void _toggleRepeater(bool v, List<Repeater> repeaters) {
    setState(() {
      _viaRepeater = v;
      if (!v) {
        _repeaterId = '';
        _repeaterCall = '';
        _downlink = 0;
        _offset = 0;
        _tone = '';
      }
    });
    if (v && _repeaterId.isEmpty) {
      final def = context.read<AppState>().defaultRepeaterId;
      if (def.isNotEmpty) _applyRepeater(def, repeaters);
    }
  }

  String _defaultRepeaterHint(AppState app) {
    if (app.defaultRepeaterId.isEmpty) {
      return '打开右侧开关可关联中继台，录入时自动带出频率、模式与亚音。';
    }
    final list = app.db
        .allRepeaters()
        .where((e) => e.id == app.defaultRepeaterId)
        .toList();
    final name = list.isEmpty ? '已设置的默认中继' : list.first.name;
    return '打开右侧开关会自动带入默认中继：$name（可在「中继台」页更换）。';
  }

  void _applyStation(String id, List<StationProfile> stations) {
    setState(() {
      _stationId = id;
      for (final s in stations) {
        if (s.id == id) {
          _stationName = s.name;
          if (s.myGrid.isNotEmpty) _myGrid.text = s.myGrid;
          if (s.rig.isNotEmpty) _rig.text = s.rig;
          if (s.antenna.isNotEmpty) _antenna.text = s.antenna;
          if (s.power.isNotEmpty) _pwrSent.text = s.power;
          break;
        }
      }
    });
  }

  void _applyRepeater(String id, List<Repeater> repeaters) {
    setState(() {
      _repeaterId = id;
      if (id.isEmpty) return;
      for (final r in repeaters) {
        if (r.id == id) {
          _repeaterCall = r.call;
          _downlink = r.downlink;
          _offset = r.offset;
          _tone = r.txTone.isNotEmpty ? r.txTone : r.rxTone;
          _mode = r.mode;
          _freq.text = Fmt.freq(r.downlink);
          break;
        }
      }
    });
  }

  void _syncFreqToRepeater() {
    if (_viaRepeater && _repeaterId.isEmpty) {
      setState(() => _downlink = double.tryParse(_freq.text) ?? 0);
    } else {
      setState(() {});
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _timeUtc.toLocal(),
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _timeUtc = DateTime.utc(
        picked.year,
        picked.month,
        picked.day,
        _timeUtc.hour,
        _timeUtc.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _timeUtc.hour, minute: _timeUtc.minute),
    );
    if (picked == null) return;
    setState(() {
      _timeUtc = DateTime.utc(
        _timeUtc.year,
        _timeUtc.month,
        _timeUtc.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Qso? _build() {
    final call = _call.text.trim().toUpperCase();
    if (call.isEmpty) {
      _toast('请填写对方呼号');
      return null;
    }
    final freq = double.tryParse(_freq.text.trim()) ?? 0;
    final base = widget.initial;
    return Qso(
      uuid: base?.uuid ?? IdGen.uuid(),
      call: call,
      qsoTimeUtc: _timeUtc,
      freqMhz: freq,
      band: Bands.fromFreqLoose(freq),
      mode: _mode,
      rstSent: _rstSent.text.trim(),
      rstRcvd: _rstRcvd.text.trim(),
      pwrSent: _pwrSent.text.trim(),
      pwrRcvd: _pwrRcvd.text.trim(),
      antenna: _antenna.text.trim(),
      rig: _rig.text.trim(),
      qth: _qth.text.trim(),
      country: _country.text.trim(),
      myGrid: _myGrid.text.trim(),
      grid: _grid.text.trim(),
      qslStatus: _qsl,
      remark: _remark.text.trim(),
      weather: _weather.text.trim(),
      repeaterId: _viaRepeater ? _repeaterId : '',
      repeaterCall: _viaRepeater ? _repeaterCall : '',
      repeaterDownlink: _viaRepeater ? (_downlink > 0 ? _downlink : freq) : 0,
      repeaterOffset: _viaRepeater ? _offset : 0,
      tone: _viaRepeater ? _tone : '',
      stationId: _stationId,
      stationName: _stationName,
      createdAt: base?.createdAt,
      updatedAt: DateTime.now().toUtc(),
      deleted: false,
    );
  }

  Future<void> _save() async {
    final q = _build();
    if (q == null) return;
    await context.read<AppState>().saveQso(q);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _saveAndContinue() async {
    final q = _build();
    if (q == null) return;
    await context.read<AppState>().saveQso(q);
    if (!mounted) return;
    _toast('已保存 ${q.call}');
    setState(() {
      _call.clear();
      _freq.clear();
      _rstSent.text = '59';
      _rstRcvd.text = '59';
      _remark.clear();
      _grid.clear();
      _qth.clear();
      _timeUtc = DateTime.now().toUtc();
      if (_repeaterId.isEmpty) {
        _viaRepeater = false;
        _repeaterCall = '';
        _downlink = 0;
        _offset = 0;
        _tone = '';
      }
    });
    _callFocus.requestFocus();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

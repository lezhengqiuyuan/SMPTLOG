/// 中继台管理：列表、编辑、反向关联。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/db.dart';
import '../core/models.dart';
import '../core/util.dart';
import '../state.dart';
import 'common.dart';
import 'theme.dart';

class RepeaterPage extends StatefulWidget {
  const RepeaterPage({super.key});

  @override
  State<RepeaterPage> createState() => _RepeaterPageState();
}

class _RepeaterPageState extends State<RepeaterPage> {
  String _search = '';
  String _band = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list = app.db.allRepeaters(search: _search, band: _band);
    final wide = MediaQuery.of(context).size.width >= Breakpoints.tablet;
    final myGrid = _defaultGrid(app);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: wide ? 260 : double.infinity,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: '搜索中继名称、呼号、位置…',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            AppDropdown<String>(
              value: _band.isEmpty ? null : _band,
              hint: '全部波段',
              width: 136,
              items: [
                const DropdownMenuItem(value: '', child: Text('全部波段')),
                ...Bands.names.map(
                  (b) => DropdownMenuItem(value: b, child: Text(b)),
                ),
              ],
              onChanged: (v) => setState(() => _band = v ?? ''),
            ),
            FilledButton.icon(
              onPressed: () => _edit(context, null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建中继台'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.cell_tower,
                  text: '还没有中继台',
                  hint: '先建立中继台档案，录入通联时可一键带出频率与亚音',
                  action: FilledButton.icon(
                    onPressed: () => _edit(context, null),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新建中继台'),
                  ),
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _card(context, list[i], myGrid),
                ),
        ),
      ],
    );
  }

  String _defaultGrid(AppState app) {
    final stations = app.db.allStations();
    for (final s in stations) {
      if (s.isDefault && s.myGrid.isNotEmpty) return s.myGrid;
    }
    return stations.isNotEmpty ? stations.first.myGrid : '';
  }

  Widget _card(BuildContext context, Repeater r, String myGrid) {
    final isDefault = context.watch<AppState>().defaultRepeaterId == r.id;
    String? distance;
    if (myGrid.isNotEmpty && r.locator.isNotEmpty) {
      final g = Geo.betweenGrids(myGrid, r.locator);
      if (g != null) {
        distance = '${Fmt.distance(g.distanceKm)} · '
            '${g.bearing.round()}° ${Geo.bearingLabel(g.bearing)}';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        r.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (r.call.isNotEmpty) TagPill(r.call, dense: false),
                    if (isDefault) ...[
                      const SizedBox(width: 6),
                      const TagPill('默认', color: AppColors.primary, dense: false),
                    ],
                    if (r.isFavorite) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.star, size: 15, color: AppColors.warning),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _kv('下行', '${Fmt.freq(r.downlink)}'),
                    _kv(
                      '偏移',
                      '${r.offset >= 0 ? '+' : ''}${r.offset.toStringAsFixed(3)}',
                    ),
                    _kv('上行', '${Fmt.freq(r.uplink)}'),
                    if (r.txTone.isNotEmpty) _kv('亚音', r.txTone),
                    if (r.mode.isNotEmpty) _kv('模式', r.mode),
                    if (r.band.isNotEmpty) _kv('波段', r.band),
                    if (r.locator.isNotEmpty) _kv('网格', r.locator),
                    if (distance != null) _kv('距离', distance),
                  ],
                ),
                if (r.qth.isNotEmpty || r.note.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    [r.qth, r.note].where((e) => e.isNotEmpty).join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textSub,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _showRelated(context, r),
                      icon: const Icon(Icons.link, size: 15),
                      label: const Text('相关通联'),
                    ),
                    const Spacer(),
                    if (r.openTime.isNotEmpty)
                      Text(
                        '开放：${r.openTime}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Text(
                '${r.timesUsed} 次',
                style: const TextStyle(fontSize: 11, color: AppColors.textHint),
              ),
              IconButton(
                tooltip: r.isFavorite ? '取消置顶' : '常用置顶',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  r.isFavorite ? Icons.star : Icons.star_border,
                  size: 18,
                  color: r.isFavorite ? AppColors.warning : AppColors.textSub,
                ),
                onPressed: () {
                  context.read<AppState>().db.upsertRepeater(
                        r.copyWith(
                          isFavorite: !r.isFavorite,
                          updatedAt: DateTime.now().toUtc(),
                        ),
                      );
                  setState(() {});
                },
              ),
              IconButton(
                tooltip: isDefault ? '取消默认中继' : '设为默认中继',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  isDefault ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 17,
                  color: isDefault ? AppColors.primary : AppColors.textSub,
                ),
                onPressed: () async {
                  await context
                      .read<AppState>()
                      .setDefaultRepeater(isDefault ? '' : r.id);
                  if (mounted) setState(() {});
                },
              ),
              IconButton(
                tooltip: '编辑',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 17),
                onPressed: () => _edit(context, r),
              ),
              IconButton(
                tooltip: '删除',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 17),
                color: AppColors.danger,
                onPressed: () => _delete(context, r),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$k ',
          style: const TextStyle(fontSize: 11, color: AppColors.textHint),
        ),
        Text(
          v,
          style: const TextStyle(
            fontSize: 12.5,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, Repeater r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: '删除中继台',
        width: 400,
        child: Text(
          '${r.name}\n历史通联记录不会受影响。',
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    context.read<AppState>().db.deleteRepeater(r.id);
    setState(() {});
  }

  Future<void> _showRelated(BuildContext context, Repeater r) async {
    final app = context.read<AppState>();
    final list = app.db.queryQsos(QsoFilter(repeaterId: r.id), limit: 100);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title: '经由 ${r.name} 的通联（${list.length}）',
        child: SizedBox(
          height: list.isEmpty ? 90 : 340,
          child: list.isEmpty
              ? const Center(
                  child: Text(
                    '还没有经由这个中继台的通联',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSub),
                  ),
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final q = list[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: TagPill(q.mode),
                      title: Text(
                        q.call,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${Fmt.dateTimeUtc(q.qsoTimeUtc)} UTC · '
                        '${Fmt.freq(q.freqMhz)} MHz',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, Repeater? r) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RepeaterEditPage(initial: r)),
    );
    if (mounted) setState(() {});
  }
}

/// 中继台编辑页。
class RepeaterEditPage extends StatefulWidget {
  const RepeaterEditPage({super.key, this.initial});

  final Repeater? initial;

  @override
  State<RepeaterEditPage> createState() => _RepeaterEditPageState();
}

class _RepeaterEditPageState extends State<RepeaterEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _call;
  late final TextEditingController _downlink;
  late final TextEditingController _offset;
  late final TextEditingController _txTone;
  late final TextEditingController _rxTone;
  late final TextEditingController _colorCode;
  late final TextEditingController _reflector;
  late final TextEditingController _qth;
  late final TextEditingController _locator;
  late final TextEditingController _openTime;
  late final TextEditingController _note;

  String _mode = QsoMode.fm;
  bool _favorite = false;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _name = TextEditingController(text: r?.name ?? '');
    _call = TextEditingController(text: r?.call ?? '');
    _downlink = TextEditingController(
      text: r == null ? '' : Fmt.freq(r.downlink),
    );
    _offset = TextEditingController(
      text: r == null ? '-7.600' : r.offset.toStringAsFixed(3),
    );
    _txTone = TextEditingController(text: r?.txTone ?? '');
    _rxTone = TextEditingController(text: r?.rxTone ?? '');
    _colorCode = TextEditingController(text: r?.colorCode ?? '');
    _reflector = TextEditingController(text: r?.reflector ?? '');
    _qth = TextEditingController(text: r?.qth ?? '');
    _locator = TextEditingController(text: r?.locator ?? '');
    _openTime = TextEditingController(text: r?.openTime ?? '');
    _note = TextEditingController(text: r?.note ?? '');
    _mode = r?.mode ?? QsoMode.fm;
    _favorite = r?.isFavorite ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      _name, _call, _downlink, _offset, _txTone, _rxTone, _colorCode,
      _reflector, _qth, _locator, _openTime, _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑中继台' : '新建中继台'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _favorite ? '已置顶常用' : '常用置顶',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSub,
                    ),
                  ),
                  Switch(
                    value: _favorite,
                    onChanged: (v) => setState(() => _favorite = v),
                  ),
                ],
              ),
              child: FormGrid(
                children: [
                  LabeledField(
                    label: '名称（必填）',
                    child: TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        hintText: '例如 福州鼓岭 R3',
                      ),
                    ),
                  ),
                  LabeledField(
                    label: '中继呼号',
                    child: TextField(
                      controller: _call,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(hintText: '例如 BR5UNI'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: '频率与模式',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FormGrid(
                    children: [
                      LabeledField(
                        label: '下行频率',
                        child: TextField(
                          controller: _downlink,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            hintText: '例如 439.550',
                            suffixText: 'MHz',
                          ),
                        ),
                      ),
                      LabeledField(
                        label: '上行偏移',
                        helper: '上行频率 = 下行频率 + 偏移',
                        child: TextField(
                          controller: _offset,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            hintText: '例如 -7.600',
                            suffixText: 'MHz',
                          ),
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
              title: '亚音与数字设置',
              child: FormGrid(
                children: [
                  LabeledField(
                    label: '发射亚音',
                    child: TextField(
                      controller: _txTone,
                      decoration: const InputDecoration(
                        hintText: 'CTCSS 88.5 或 DCS D025N',
                        isDense: true,
                      ),
                    ),
                  ),
                  LabeledField(
                    label: '接收亚音',
                    child: TextField(
                      controller: _rxTone,
                      decoration: const InputDecoration(
                        hintText: '可留空',
                        isDense: true,
                      ),
                    ),
                  ),
                  LabeledField(
                    label: 'DMR 色码',
                    child: TextField(
                      controller: _colorCode,
                      decoration: const InputDecoration(
                        hintText: '例如 CC1',
                        isDense: true,
                      ),
                    ),
                  ),
                  LabeledField(
                    label: '网关 / 反射器 / 通话组',
                    child: TextField(
                      controller: _reflector,
                      decoration: const InputDecoration(
                        hintText: 'D-STAR 反射器、C4FM 房间号、DMR TG',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: '位置与说明',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FormGrid(
                    children: [
                      LabeledField(
                        label: '位置',
                        child: TextField(
                          controller: _qth,
                          decoration: const InputDecoration(
                            hintText: '例如 福州鼓岭',
                            isDense: true,
                          ),
                        ),
                      ),
                      LabeledField(
                        label: '网格',
                        helper: '填写网格后可自动计算距离与方位角',
                        child: TextField(
                          controller: _locator,
                          decoration: const InputDecoration(
                            hintText: '例如 OL96',
                            isDense: true,
                          ),
                        ),
                      ),
                      LabeledField(
                        label: '开放时间',
                        child: TextField(
                          controller: _openTime,
                          decoration: const InputDecoration(
                            hintText: '例如 全天',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LabeledField(
                    label: '备注',
                    child: TextField(
                      controller: _note,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: '覆盖范围、注意事项…',
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

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写中继台名称')));
      return;
    }
    final downlink = double.tryParse(_downlink.text.trim()) ?? 0;
    final offset = double.tryParse(_offset.text.trim()) ?? 0;
    final base = widget.initial;
    final r = Repeater(
      id: base?.id ?? IdGen.uuid(),
      name: name,
      call: _call.text.trim().toUpperCase(),
      downlink: downlink,
      offset: offset,
      txTone: _txTone.text.trim(),
      rxTone: _rxTone.text.trim(),
      mode: _mode,
      band: Bands.fromFreqLoose(downlink),
      colorCode: _colorCode.text.trim(),
      reflector: _reflector.text.trim(),
      qth: _qth.text.trim(),
      locator: _locator.text.trim().toUpperCase(),
      openTime: _openTime.text.trim(),
      note: _note.text.trim(),
      isFavorite: _favorite,
      timesUsed: base?.timesUsed ?? 0,
      lastUsed: base?.lastUsed,
      createdAt: base?.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    if (!mounted) return;
    context.read<AppState>().db.upsertRepeater(r);
    Navigator.of(context).pop();
  }
}

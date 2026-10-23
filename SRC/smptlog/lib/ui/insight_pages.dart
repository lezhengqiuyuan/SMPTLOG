/// 日志总览、奖状追踪、数据分析三个页面。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/db.dart';
import '../core/models.dart';
import '../core/util.dart';
import '../state.dart';
import 'common.dart';
import 'theme.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.db.stats();

    final maxBand = s.bandCounts.values.isEmpty
        ? 1
        : s.bandCounts.values.reduce((a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 1000
                ? 4
                : c.maxWidth >= 620
                    ? 2
                    : 1;
            const gap = 12.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            final cards = <Widget>[
              StatCard(
                label: '总通联数',
                value: '${s.total}',
                sub: '本地数据库',
                icon: Icons.list_alt,
              ),
              StatCard(
                label: '独立呼号',
                value: '${s.distinctCalls}',
                sub: '去重后',
                icon: Icons.people_outline,
              ),
              StatCard(
                label: '经由中继',
                value: '${s.repeaterCount}',
                sub: '含中继关联',
                icon: Icons.cell_tower,
              ),
              StatCard(
                label: 'QSL 已确认',
                value: '${s.qslConfirmed}',
                sub: '含 LoTW / eQSL',
                icon: Icons.verified_outlined,
                color: AppColors.accent,
              ),
            ];
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in cards) SizedBox(width: w, child: card),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '近 30 天通联趋势',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TrendChart(values: s.last30Days),
              const SizedBox(height: 8),
              Text(
                '合计 ${s.last30Days.fold<int>(0, (a, b) => a + b)} 条',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSub,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '波段分布',
          child: s.bandCounts.isEmpty
              ? const Text(
                  '暂无数据',
                  style: TextStyle(color: AppColors.textSub, fontSize: 12),
                )
              : Column(
                  children: s.bandCounts.entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(width: 54, child: Text(e.key)),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: e.value / maxBand,
                                minHeight: 8,
                                backgroundColor:
                                    AppColors.primary.withValues(alpha: 0.08),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 44,
                            child: Text(
                              '${e.value}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '模式分布',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: s.modeCounts.entries
                .map((e) => TagPill('${e.key} ${e.value}', dense: false))
                .toList(),
          ),
        ),
      ],
    );
  }
}

/// 奖状追踪。
///
/// 按需求已从导航下线（一期不需要），实现保留以便后续恢复：
/// 重新在 app.dart 的 _navItems 与 _body 中挂回去即可。
class AwardsPage extends StatelessWidget {
  const AwardsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final a = app.db.awardSummary();
    final stats = app.db.stats();

    final items = <({String name, int current, int target, String desc})>[
      (
        name: '波段覆盖',
        current: a.distinctBands,
        target: 14,
        desc: '在 14 个业余波段中通联过的数量',
      ),
      (
        name: '模式覆盖',
        current: a.distinctModes,
        target: 10,
        desc: '使用过的不同通联模式数量',
      ),
      (
        name: 'DXCC 地区',
        current: a.distinctCountries,
        target: 100,
        desc: '通联到的不同国家/地区数量',
      ),
      (
        name: '中继通联',
        current: stats.repeaterCount,
        target: 100,
        desc: '经由中继台完成的通联数量',
      ),
      (
        name: 'QSL 确认',
        current: stats.qslConfirmed,
        target: 100,
        desc: '已确认的 QSL 数量',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const NoticeBar(
          text: '奖状进度按本地数据实时统计，数据来源为通联日志与中继台档案。',
          color: AppColors.primary,
        ),
        const SizedBox(height: 12),
        ...items.map((e) {
          final ratio = e.target == 0 ? 0.0 : (e.current / e.target).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SectionCard(
              title: e.name,
              trailing: Text(
                '${e.current} / ${e.target}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 10,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.desc,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSub,
                    ),
                  ),
                  if (ratio >= 1)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: TagPill('已达成', color: AppColors.accent),
                    ),
                ],
              ),
            ),
          );
        }),
        SectionCard(
          title: '各波段网格数',
          child: a.bandGrids.isEmpty
              ? const Text(
                  '暂无网格数据',
                  style: TextStyle(color: AppColors.textSub, fontSize: 12),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: a.bandGrids.entries
                      .map((e) => TagPill('${e.key} ${e.value} 格', dense: false))
                      .toList(),
                ),
        ),
      ],
    );
  }
}

/// 数据分析。
class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final all = app.db.allQsos();
    final stats = app.db.stats();

    // 时段分布（UTC 小时）
    final hours = List<int>.filled(24, 0);
    final years = <String, int>{};
    final calls = <String, int>{};
    final bands = stats.bandCounts;

    for (final q in all) {
      hours[q.qsoTimeUtc.hour]++;
      final y = q.qsoTimeUtc.year.toString();
      years[y] = (years[y] ?? 0) + 1;
      final c = Callsign.base(q.call);
      calls[c] = (calls[c] ?? 0) + 1;
    }

    final topCalls = calls.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxHour = hours.reduce((a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        SectionCard(
          title: '通联时段分布（UTC）',
          child: SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(24, (i) {
                final v = hours[i];
                final h = maxHour == 0 ? 0.0 : (v / maxHour) * 110;
                return Expanded(
                  child: Tooltip(
                    message: '$i 时：$v 条',
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: h <= 0 ? 0 : h,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '按年份统计',
          child: years.isEmpty
              ? const Text('暂无数据', style: TextStyle(fontSize: 12))
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: (years.entries.toList()
                        ..sort((a, b) => b.key.compareTo(a.key)))
                      .map((e) => TagPill('${e.key} 年 ${e.value} 条', dense: false))
                      .toList(),
                ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '最常通联的呼号 Top 10',
          child: topCalls.isEmpty
              ? const Text('暂无数据', style: TextStyle(fontSize: 12))
              : Column(
                  children: topCalls.take(10).map((e) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.key),
                      trailing: Text(
                        '${e.value} 次',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSub,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '波段 / 模式汇总',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: bands.entries
                    .map((e) => TagPill('${e.key} ${e.value}'))
                    .toList(),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: stats.modeCounts.entries
                    .map((e) =>
                        TagPill('${e.key} ${e.value}', color: AppColors.accent))
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

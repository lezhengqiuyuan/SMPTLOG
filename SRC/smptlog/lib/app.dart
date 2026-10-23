/// 应用外壳：四档响应式导航 + 桌面快捷键。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/update_checker.dart';
import 'state.dart';
import 'ui/about_page.dart';
import 'ui/common.dart';
import 'ui/insight_pages.dart';
import 'ui/logbook_page.dart';
import 'ui/qso_edit_page.dart';
import 'ui/repeater_page.dart';
import 'ui/settings_page.dart';
import 'ui/theme.dart';

class SmptlogApp extends StatelessWidget {
  const SmptlogApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return MaterialApp(
      title: 'SMPTLOG 通联日志',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: app.settings.themeMode,
      locale: const Locale('zh', 'CN'),
      home: const ShellPage(),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _navItems = <_NavItem>[
  _NavItem('日志总览', Icons.dashboard_outlined, Icons.dashboard),
  _NavItem('通联日志', Icons.list_alt_outlined, Icons.list_alt),
  _NavItem('中继台', Icons.cell_tower_outlined, Icons.cell_tower),
  _NavItem('数据分析', Icons.insights_outlined, Icons.insights),
  _NavItem('设置', Icons.settings_outlined, Icons.settings),
  _NavItem('关于', Icons.info_outline, Icons.info),
];

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _index = 1;
  bool _collapsed = false;
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  Widget _body() {
    switch (_index) {
      case 0:
        return const OverviewPage();
      case 1:
        return const LogbookPage();
      case 2:
        return const RepeaterPage();
      case 3:
        return const AnalyticsPage();
      case 4:
        return const SettingsPage();
      default:
        return const AboutPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final app = context.watch<AppState>();

    final content = Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(_navItems[_index].label),
            const SizedBox(width: 12),
            if (app.syncing)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (app.lastSyncAt != null)
              TagPill(
                '已同步',
                color: AppColors.accent,
              ),
          ],
        ),
        actions: [
          if (w < Breakpoints.tablet)
            IconButton(
              tooltip: '同步',
              onPressed: app.syncing ? null : app.runSync,
              icon: const Icon(Icons.sync, size: 20),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: PageBody(
          child: Column(
            children: [
              if (app.showUpdateBanner) _updateBanner(context, app),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
      floatingActionButton: w < Breakpoints.phone && _index == 1
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QsoEditPage()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('新建通联'),
            )
          : null,
      bottomNavigationBar: w < Breakpoints.phone
          ? NavigationBar(
              height: 64,
              selectedIndex: _index > 4 ? 4 : _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: '总览',
                ),
                NavigationDestination(
                  icon: Icon(Icons.list_alt_outlined),
                  selectedIcon: Icon(Icons.list_alt),
                  label: '日志',
                ),
                NavigationDestination(
                  icon: Icon(Icons.cell_tower_outlined),
                  selectedIcon: Icon(Icons.cell_tower),
                  label: '中继',
                ),
                NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights),
                  label: '分析',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: '设置',
                ),
              ],
            )
          : null,
    );

    Widget shell;
    if (w >= Breakpoints.tablet) {
      shell = Row(
        children: [
          _sidebar(app, collapsed: _collapsed),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ],
      );
    } else if (w >= Breakpoints.phone) {
      shell = Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.radio, color: AppColors.primary),
            ),
            destinations: _navItems
                .map(
                  (e) => NavigationRailDestination(
                    icon: Icon(e.icon, size: 20),
                    selectedIcon: Icon(e.selectedIcon, size: 20),
                    label: Text(e.label, style: const TextStyle(fontSize: 11)),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ],
      );
    } else {
      shell = content;
    }

    return _Shortcuts(
      searchFocus: _searchFocus,
      onNew: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const QsoEditPage()),
      ),
      onSettings: () => setState(() => _index = 5),
      onHelp: () => _showShortcuts(context),
      child: Scaffold(body: shell),
    );
  }

  Widget _sidebar(AppState app, {required bool collapsed}) {
    final width = collapsed ? 72.0 : 240.0;
    final t = Theme.of(context);

    return Container(
      width: width,
      color: t.cardTheme.color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 12, 18),
            child: Row(
              children: [
                const Icon(Icons.radio, color: AppColors.primary, size: 22),
                if (!collapsed) ...[
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SMPTLOG',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          '业余无线电通联日志',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 18),
                    onPressed: () => setState(() => _collapsed = true),
                  ),
                ] else
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 18),
                    onPressed: () => setState(() => _collapsed = false),
                  ),
              ],
            ),
          ),
          const Divider(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              collapsed ? '' : '工作台',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textHint,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < _navItems.length; i++)
            _navTile(i, collapsed, app),
          const Spacer(),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.syncConfigured ? '云同步已配置' : '仅本地模式',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: app.syncing ? null : app.runSync,
                    icon: const Icon(Icons.sync, size: 16),
                    label: Text(app.syncing ? '同步中…' : '同步'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _navTile(int i, bool collapsed, AppState app) {
    final selected = i == _index;
    final item = _navItems[i];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _index = i),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : 12,
              vertical: 11,
            ),
            child: Row(
              mainAxisAlignment:
                  collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 18,
                  color:
                      selected ? AppColors.primary : AppColors.textSub,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 13,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textMain,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (i == 1 && app.conflictCount > 0)
                    TagPill('${app.conflictCount}', color: AppColors.warning),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 顶部更新提醒条：发现新版本时显示，可关闭。
  Widget _updateBanner(BuildContext context, AppState app) {
    final info = app.availableUpdate;
    if (info == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_alt,
              size: 17, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '发现新版本 v${info.latest}（当前 v$kAppVersion）',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textMain,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              try {
                await PlatformLinks.open(info.url);
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('链接已复制：${info.url}')),
                );
              }
            },
            child: const Text('去下载'),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '本次忽略',
            onPressed: app.dismissUpdate,
            icon: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }

  void _showShortcuts(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('桌面快捷键'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('N          新建通联'),
            Text('Ctrl+S   保存当前表单'),
            Text('Esc        取消 / 关闭'),
            Text('Ctrl+F   聚焦搜索框'),
            Text('Ctrl+I    导入文件'),
            Text('Ctrl+E   导出文件'),
            Text('Del        删除选中'),
            Text('↑ ↓       列表行导航'),
            Text('Ctrl+,    打开设置'),
            Text('F1         显示本表'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

/// 全局快捷键。
class _Shortcuts extends StatelessWidget {
  const _Shortcuts({
    required this.child,
    required this.searchFocus,
    required this.onNew,
    required this.onSettings,
    required this.onHelp,
  });

  final Widget child;
  final FocusNode searchFocus;
  final VoidCallback onNew;
  final VoidCallback onSettings;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN): onNew,
        const SingleActivator(LogicalKeyboardKey.f1): onHelp,
        const SingleActivator(LogicalKeyboardKey.comma, control: true):
            onSettings,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

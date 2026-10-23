/// 设置：电台档案、云同步、端到端加密、外观、ADIF、判重、数据管理。
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/update_checker.dart';
import '../core/util.dart';
import '../state.dart';
import '../sync/cos.dart';
import '../sync/secure.dart';
import 'about_page.dart';
import 'common.dart';
import 'sync_guide_page.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _projectId;
  late TextEditingController _token;
  late TextEditingController _password;
  late TextEditingController _davUrl;
  late TextEditingController _davUser;
  late TextEditingController _davPassword;
  String _backend = 'edgeone';
  bool _busy = false;
  String _testResult = '';

  @override
  void initState() {
    super.initState();
    _projectId = TextEditingController();
    _token = TextEditingController();
    _password = TextEditingController();
    _davUrl = TextEditingController(text: 'https://dav.jianguoyun.com/dav/');
    _davUser = TextEditingController();
    _davPassword = TextEditingController();
    _loadSecrets();
  }

  Future<void> _loadSecrets() async {
    final m = await SecretsVault.read();
    if (!mounted) return;
    setState(() {
      _backend = (m['backend'] ?? 'edgeone').toString();
      _projectId.text = (m['projectId'] ?? '').toString();
      _token.text = (m['apiToken'] ?? '').toString();
      final url = (m['davUrl'] ?? '').toString();
      if (url.isNotEmpty) _davUrl.text = url;
      _davUser.text = (m['davUser'] ?? '').toString();
      _davPassword.text = (m['davPassword'] ?? '').toString();
    });
  }

  @override
  void dispose() {
    _projectId.dispose();
    _token.dispose();
    _password.dispose();
    _davUrl.dispose();
    _davUser.dispose();
    _davPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final stations = app.db.allStations();

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        SectionCard(
          title: '电台档案',
          trailing: TextButton.icon(
            onPressed: () => _editStation(context, null),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('新增'),
          ),
          child: stations.isEmpty
              ? const Text(
                  '还没有电台档案。建议先建立“手持机 / 车台 / 基地台”，录入时会自动带出呼号、网格、设备与功率。',
                  style: TextStyle(fontSize: 12, color: AppColors.textSub),
                )
              : Column(
                  children: stations.map((st) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        st.isDefault
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                        color: st.isDefault
                            ? AppColors.accent
                            : AppColors.textHint,
                      ),
                      title: Text(st.name),
                      subtitle: Text(
                        [
                          if (st.myCall.isNotEmpty) st.myCall,
                          if (st.myGrid.isNotEmpty) st.myGrid,
                          if (st.rig.isNotEmpty) st.rig,
                          if (st.power.isNotEmpty) '${st.power}W',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () {
                              app.db.upsertStation(
                                st.copyWith(
                                  isDefault: true,
                                  updatedAt: DateTime.now().toUtc(),
                                ),
                              );
                              setState(() {});
                            },
                            child: const Text('设为默认'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            onPressed: () => _editStation(context, st),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16),
                            onPressed: () {
                              app.db.deleteStation(st.id);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '云同步',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '安全提示：请为本应用单独创建一个 API Token，并设置 90 天过期，'
                  '不要使用账号主 Token。Token 仅保存在本机（Windows 用 DPAPI、'
                  'Android 用 Keystore），不会写入日志数据库，也不会进入任何导出文件。',
                  style: TextStyle(fontSize: 11.5, color: AppColors.warning),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '三选一，同一时间只会使用一个后端。',
                style: TextStyle(fontSize: 12, color: AppColors.textSub),
              ),
              const SizedBox(height: 8),
              _backendSelector(),
              const SizedBox(height: 12),
              if (_backend == 'off') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '当前为仅本地模式',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '所有数据只保存在这台设备上，不会上传任何内容，「立即同步」不可用。\n'
                        '换设备时用：设置 → 数据管理 → 导出 JSON 备份 → 另一台导入。',
                        style: TextStyle(fontSize: 12, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ] else if (_backend == 'edgeone') ...[
                Row(
                  children: [
                    const Text(
                      '不知道 projectId / Token 在哪里拿？',
                      style: TextStyle(fontSize: 12, color: AppColors.textSub),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SyncGuidePage(),
                        ),
                      ),
                      icon: const Icon(Icons.menu_book_outlined, size: 16),
                      label: const Text('看引导教程'),
                    ),
                  ],
                ),
                TextField(
                  controller: _projectId,
                  decoration: const InputDecoration(
                    labelText: 'projectId',
                    hintText: '形如 makers-60tcjerf0vgq（从项目页地址栏复制）',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _token,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Token',
                    hintText: '在 EdgeOne 控制台 → 设置 → API Token 创建',
                    isDense: true,
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '坚果云走 WebDAV：地址固定不用改；用户名是注册邮箱；'
                    '密码必须用「应用密码」（网页端 设置 → 安全选项 → '
                    '第三方应用管理 里生成），不是登录密码。',
                    style: TextStyle(fontSize: 11.5, height: 1.55),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _davUrl,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://dav.jianguoyun.com/dav/',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _davUser,
                  decoration: const InputDecoration(
                    labelText: '账号（注册邮箱）',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _davPassword,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '应用密码',
                    hintText: '在坚果云 设置 → 安全选项 → 第三方应用管理 生成',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => PlatformLinks.open(
                      'https://www.jianguoyun.com/d/login#/safety',
                    ),
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text('去坚果云生成应用密码'),
                  ),
                ),
                const Text(
                  '免费版：上传 1 GB/月、下载 3 GB/月。程序只传增量，日常使用远远够。',
                  style: TextStyle(fontSize: 11, color: AppColors.textSub),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _test,
                    child: const Text('测试连接'),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _saveSync,
                    child: const Text('保存'),
                  ),
                  if (_backend != 'off')
                    FilledButton.icon(
                      onPressed: app.syncing ? null : _syncNow,
                      icon: const Icon(Icons.sync, size: 18),
                      label: Text(app.syncing ? '同步中…' : '立即同步'),
                    ),
                ],
              ),
              if (_testResult.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _testResult,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              if (app.syncing) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: app.syncRatio == 0 ? null : app.syncRatio,
                ),
                const SizedBox(height: 6),
                Text(
                  app.syncMessage,
                  style: const TextStyle(fontSize: 12),
                ),
              ] else if (app.syncMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  app.syncMessage,
                  style: TextStyle(
                    fontSize: 12,
                    color: app.syncMessage.contains('失败') ||
                            app.syncMessage.contains('无效')
                        ? AppColors.danger
                        : AppColors.textSub,
                  ),
                ),
              ],
              if (app.lastSyncAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '上次同步：${Fmt.local(app.lastSyncAt!)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '端到端加密',
          trailing: Switch(
            value: app.encryptionEnabled,
            onChanged: (v) => _toggleEncryption(context, v),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '开启后，上传到云端的日志会先用你的密码加密（AES-256-GCM），'
                '即使 Token 泄露也读不到内容。密码只保存在本机。',
                style: TextStyle(fontSize: 12, color: AppColors.textSub),
              ),
              if (app.encryptionEnabled)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '已开启。更换设备后需要在设置里重新输入同一密码才能解密。',
                    style: TextStyle(fontSize: 11, color: AppColors.accent),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '外观',
          child: Column(
            children: [
              RadioListTile<ThemeMode>(
                value: ThemeMode.system,
                groupValue: s.themeMode,
                dense: true,
                title: const Text('跟随系统'),
                onChanged: (v) => _setTheme(context, v!),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.light,
                groupValue: s.themeMode,
                dense: true,
                title: const Text('浅蓝（默认）'),
                onChanged: (v) => _setTheme(context, v!),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.dark,
                groupValue: s.themeMode,
                dense: true,
                title: const Text('深色'),
                onChanged: (v) => _setTheme(context, v!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '录入与导入',
          child: Column(
            children: [
              FieldRow(
                label: 'ADIF 频率',
                width: 100,
                child: Wrap(
                  spacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('下行频率'),
                      selected: s.adifFreqPolicy == 'down',
                      onSelected: (_) => app.updateSettings(
                        s.copyWith(adifFreqPolicy: 'down'),
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('上行频率'),
                      selected: s.adifFreqPolicy == 'up',
                      onSelected: (_) => app.updateSettings(
                        s.copyWith(adifFreqPolicy: 'up'),
                      ),
                    ),
                  ],
                ),
              ),
              FieldRow(
                label: '判重时间窗',
                width: 100,
                child: Wrap(
                  spacing: 6,
                  children: [0, 5, 30, 60].map((m) {
                    return ChoiceChip(
                      label: Text(m == 0 ? '关闭' : '$m 分钟'),
                      selected: s.dupWindowMinutes == m,
                      onSelected: (_) => app.updateSettings(
                        s.copyWith(dupWindowMinutes: m),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '数据管理',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _export(context, 'adif'),
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('导出 ADIF'),
              ),
              OutlinedButton.icon(
                onPressed: () => _export(context, 'json'),
                icon: const Icon(Icons.backup_outlined, size: 18),
                label: const Text('导出 JSON 备份'),
              ),
              OutlinedButton.icon(
                onPressed: () => _export(context, 'csv'),
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('导出 CSV'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showConflicts(context, app),
                icon: const Icon(Icons.merge_type, size: 18),
                label: Text('冲突副本（${app.conflictCount}）'),
              ),
              OutlinedButton.icon(
                onPressed: () => _purge(context, app),
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: const Text('清理已删除记录'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '桌面快捷键',
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: const [
              'N 新建通联', 'Ctrl+S 保存', 'Esc 取消', 'Ctrl+F 搜索',
              'Ctrl+I 导入', 'Ctrl+E 导出', 'Del 删除选中', '↑↓ 行导航',
              'Ctrl+, 设置', 'F1 快捷键表',
            ].map((e) => TagPill(e, dense: false)).toList(),
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '关于',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SMPTLOG 通联日志助手 · v$kAppVersion',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text(
                '作者呼号 BG5SWK · 博客 www.smallpatch.cn',
                style: TextStyle(fontSize: 12, color: AppColors.textSub),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '启动时自动检查更新',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSub,
                      ),
                    ),
                  ),
                  Switch(
                    value: s.checkUpdateOnStart,
                    onChanged: (v) => app.updateSettings(
                      s.copyWith(checkUpdateOnStart: v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                ),
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('打开关于页'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _backendSelector() {
    const opts = <({String value, String label, IconData icon})>[
      (value: 'off', label: '关闭', icon: Icons.cloud_off_outlined),
      (value: 'edgeone', label: 'EdgeOne', icon: Icons.cloud_outlined),
      (value: 'webdav', label: '坚果云', icon: Icons.folder_shared_outlined),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF3FD),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: opts.map((o) {
          final selected = _backend == o.value;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _backend = o.value),
              child: Container(
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      o.icon,
                      size: 15,
                      color: selected ? AppColors.primary : AppColors.textSub,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      o.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color:
                            selected ? AppColors.primary : AppColors.textSub,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // --------------------------------------------------------------- 动作

  void _setTheme(BuildContext context, ThemeMode m) {
    final app = context.read<AppState>();
    app.updateSettings(app.settings.copyWith(themeMode: m));
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _testResult = '正在连接…';
    });
    try {
      final msg = await context.read<AppState>().testSync(
            backend: _backend,
            projectId: _projectId.text.trim(),
            token: _token.text.trim(),
            davUrl: _davUrl.text.trim(),
            davUser: _davUser.text.trim(),
            davPassword: _davPassword.text,
          );
      if (!mounted) return;
      setState(() => _testResult = msg);
    } on BlobException catch (e) {
      if (!mounted) return;
      setState(() => _testResult = '连接失败：${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = '连接失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveSync() async {
    setState(() => _busy = true);
    try {
      await context.read<AppState>().saveSyncConfig(
            backend: _backend,
            projectId: _projectId.text.trim(),
            token: _token.text.trim(),
            davUrl: _davUrl.text.trim(),
            davUser: _davUser.text.trim(),
            davPassword: _davPassword.text,
          );
      if (!mounted) return;
      setState(() => _testResult = '已保存到本机安全存储');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    await context.read<AppState>().runSync();
    if (!mounted) return;
    final app = context.read<AppState>();
    setState(() => _testResult = app.syncMessage);
  }

  Future<void> _toggleEncryption(BuildContext context, bool on) async {
    final app = context.read<AppState>();
    if (!on) {
      await app.configureEncryption(null);
      return;
    }
    _password.clear();
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置同步密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '请牢记此密码：忘记后云端密文将无法恢复。'
              '切换设备时需要输入同一个密码。',
              style: TextStyle(fontSize: 12, color: AppColors.textSub),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: '密码（至少 8 位）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (_password.text.trim().length < 8) return;
              Navigator.pop(ctx, _password.text.trim());
            },
            child: const Text('启用'),
          ),
        ],
      ),
    );
    if (pw == null || pw.isEmpty) return;
    await app.configureEncryption(pw);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已启用端到端加密，下次同步开始生效')),
    );
  }

  Future<void> _editStation(BuildContext context, StationProfile? st) async {
    final nameCtrl = TextEditingController(text: st?.name ?? '');
    final callCtrl = TextEditingController(text: st?.myCall ?? '');
    final gridCtrl = TextEditingController(text: st?.myGrid ?? '');
    final rigCtrl = TextEditingController(text: st?.rig ?? '');
    final antCtrl = TextEditingController(text: st?.antenna ?? '');
    final pwrCtrl = TextEditingController(text: st?.power ?? '');
    final qthCtrl = TextEditingController(text: st?.qth ?? '');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(st == null ? '新增电台档案' : '编辑电台档案'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '名称（必填）'),
                ),
                TextField(
                  controller: callCtrl,
                  decoration: const InputDecoration(labelText: '己方呼号'),
                ),
                TextField(
                  controller: gridCtrl,
                  decoration: const InputDecoration(labelText: '己方网格'),
                ),
                TextField(
                  controller: rigCtrl,
                  decoration: const InputDecoration(labelText: '设备'),
                ),
                TextField(
                  controller: antCtrl,
                  decoration: const InputDecoration(labelText: '天馈'),
                ),
                TextField(
                  controller: pwrCtrl,
                  decoration: const InputDecoration(labelText: '常用功率 (W)'),
                ),
                TextField(
                  controller: qthCtrl,
                  decoration: const InputDecoration(labelText: '常驻 QTH'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final app = context.read<AppState>();
              app.db.upsertStation(
                StationProfile(
                  id: st?.id ?? IdGen.uuid(),
                  name: name,
                  myCall: callCtrl.text.trim().toUpperCase(),
                  myGrid: gridCtrl.text.trim().toUpperCase(),
                  rig: rigCtrl.text.trim(),
                  antenna: antCtrl.text.trim(),
                  power: pwrCtrl.text.trim(),
                  qth: qthCtrl.text.trim(),
                  isDefault: st?.isDefault ?? false,
                  createdAt: st?.createdAt,
                  updatedAt: DateTime.now().toUtc(),
                  deviceId: app.deviceId,
                ),
              );
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, String kind) async {
    final app = context.read<AppState>();
    String content;
    String name;
    if (kind == 'adif') {
      content = app.exportAdif();
      name = 'smptlog_${DateTime.now().millisecondsSinceEpoch}.adi';
    } else if (kind == 'json') {
      content = app.exportJson();
      name = 'smptlog_backup_${DateTime.now().millisecondsSinceEpoch}.json';
    } else {
      content = app.exportCsv();
      name = 'smptlog_${DateTime.now().millisecondsSinceEpoch}.csv';
    }
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: '保存文件',
        fileName: name,
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (!mounted) return;
      if (uri != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已保存到 ${uri.toString()}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  Future<void> _showConflicts(BuildContext context, AppState app) async {
    final list = app.db.allConflicts();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('冲突副本（${list.length}）'),
        content: SizedBox(
          width: 520,
          height: 320,
          child: list.isEmpty
              ? const Center(child: Text('没有冲突副本'))
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, i) {
                    final c = list[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        '${c.dataset} · ${c.loserJson['call'] ?? c.loserJson['name'] ?? ''}',
                      ),
                      subtitle: Text(
                        '被覆盖方更新于 ${Fmt.dateTimeUtc(c.loserUpdatedAt)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () {
                              app.restoreConflict(c);
                              Navigator.pop(ctx);
                            },
                            child: const Text('恢复'),
                          ),
                          TextButton(
                            onPressed: () {
                              app.dismissConflict(c);
                              Navigator.pop(ctx);
                            },
                            child: const Text('丢弃'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
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

  Future<void> _purge(BuildContext context, AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理已删除记录？'),
        content: const Text('将物理删除 90 天前标记为删除的记录，释放存储空间。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    app.db.purgeDeleted();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已清理')));
    setState(() {});
  }
}

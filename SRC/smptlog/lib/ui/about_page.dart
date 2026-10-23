/// 关于页：应用信息、作者呼号与博客、数据位置、技术栈与免责声明。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/update_checker.dart';
import '../state.dart';
import 'common.dart';
import 'theme.dart';

/// 打开外部链接：Windows 走 rundll32，Android 走原生 Intent。
class PlatformLinks {
  static const _channel = MethodChannel('smptlog/vault');

  static Future<void> open(String url) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('openUrl', {'url': url});
      return;
    }
    if (Platform.isWindows) {
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      return;
    }
    throw UnsupportedError('当前平台不支持打开链接');
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String appName = 'SMPTLOG 通联日志';
  static const String version = kAppVersion;
  static const String callsign = 'BG5SWK';
  static const String blogUrl = 'https://www.smallpatch.cn';
  static const String blogLabel = 'www.smallpatch.cn';
  static const String repoUrl = 'https://github.com/lezhengqiuyuan/SMPTLOG';
  static const String repoLabel = 'github.com/lezhengqiuyuan/SMPTLOG';

  @override
  Widget build(BuildContext context) {
    // 从设置页 push 进来时，没有外壳的 Scaffold，
    // 内容会直接铺在黑色窗口背景上（很丑）；这里自带上标题栏。
    final pushed = Navigator.of(context).canPop();
    final body = _content(context, padded: pushed);

    if (pushed) {
      return Scaffold(
        appBar: AppBar(title: const Text('关于')),
        body: body,
      );
    }
    return body;
  }

  Widget _content(BuildContext context, {required bool padded}) {
    final app = context.watch<AppState>();

    // 显式指定基础文字样式，避免继承到外部（系统/主题）的文字装饰。
    return DefaultTextStyle.merge(
      style: const TextStyle(
        color: AppColors.textMain,
        decoration: TextDecoration.none,
        backgroundColor: Colors.transparent,
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(padded ? 16 : 0, 8, padded ? 16 : 0, 40),
      children: [
        _hero(context),
        const SizedBox(height: 14),
        _authorCard(context),
        const SizedBox(height: 14),
        _opensourceCard(context),
        const SizedBox(height: 14),
        const _UpdateCard(),
        const SizedBox(height: 14),
        _featuresCard(),
        const SizedBox(height: 14),
        _privacyCard(context, app),
        const SizedBox(height: 14),
        _techCard(),
        const SizedBox(height: 14),
        _disclaimerCard(),
        const SizedBox(height: 18),
        Center(
          child: Text(
            'Made with Flutter · v$version · $appName',
            style: const TextStyle(fontSize: 11, color: AppColors.textHint),
          ),
        ),
      ],
      ),
    );
  }

  // ------------------------------------------------------------- 顶部

  Widget _hero(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        // 固定浅蓝，不依赖叠加透明度（否则深色背景下会发黑）
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCFE0FB)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.radio, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  appName,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '业余无线电通联日志助手 · 本地优先',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSub,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: const Text(
              'v$version',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- 作者

  Widget _authorCard(BuildContext context) {
    return SectionCard(
      title: '关于作者',
      child: Column(
        children: [
          _infoRow(
            icon: Icons.badge_outlined,
            label: '业余无线电呼号',
            value: callsign,
            valueStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: AppColors.primary,
            ),
            actions: [
              _iconAction(
                context,
                icon: Icons.copy,
                tooltip: '复制呼号',
                text: callsign,
                toast: '已复制呼号 $callsign',
              ),
            ],
          ),
          const Divider(height: 22),
          _infoRow(
            icon: Icons.public,
            label: '个人博客',
            value: blogLabel,
            valueStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primary,
            ),
            onTapValue: () => _openBlog(context),
            actions: [
              _iconAction(
                context,
                icon: Icons.copy,
                tooltip: '复制链接',
                text: blogUrl,
                toast: '已复制博客链接',
              ),
              IconButton(
                tooltip: '在浏览器中打开',
                visualDensity: VisualDensity.compact,
                onPressed: () => _openBlog(context),
                icon: const Icon(Icons.open_in_new,
                    size: 16, color: AppColors.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _opensourceCard(BuildContext context) {
    return SectionCard(
      title: '开源项目',
      child: Column(
        children: [
          _infoRow(
            icon: Icons.code,
            label: '源码仓库',
            value: repoLabel,
            valueStyle: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primary,
            ),
            onTapValue: () => _openUrl(context, repoUrl),
            actions: [
              _iconAction(
                context,
                icon: Icons.copy,
                tooltip: '复制仓库地址',
                text: repoUrl,
                toast: '已复制仓库地址',
              ),
              IconButton(
                tooltip: '在浏览器中打开',
                visualDensity: VisualDensity.compact,
                onPressed: () => _openUrl(context, repoUrl),
                icon: const Icon(Icons.open_in_new,
                    size: 16, color: AppColors.primary),
              ),
            ],
          ),
          const Divider(height: 22),
          _infoRow(
            icon: Icons.bug_report_outlined,
            label: '问题反馈',
            value: '提交 Issue',
            valueStyle: const TextStyle(
              fontSize: 13.5,
              color: AppColors.primary,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primary,
            ),
            onTapValue: () => _openUrl(context, '$repoUrl/issues'),
            actions: [
              IconButton(
                tooltip: '打开 Issues',
                visualDensity: VisualDensity.compact,
                onPressed: () => _openUrl(context, '$repoUrl/issues'),
                icon: const Icon(Icons.open_in_new,
                    size: 16, color: AppColors.primary),
              ),
            ],
          ),
          const Divider(height: 22),
          _infoRow(
            icon: Icons.description_outlined,
            label: '许可证',
            value: 'Apache-2.0 · 欢迎 Star 与 PR',
            valueStyle: const TextStyle(fontSize: 13, color: AppColors.textMain),
          ),
        ],
      ),
    );
  }

  /// 打开任意外部链接，失败则复制到剪贴板。
  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      await PlatformLinks.open(url);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开浏览器，链接已复制：$url')),
      );
    }
  }

  /// 信息行：宽屏为「标签 + 值 + 操作」，窄屏改为上下两行。
  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    required TextStyle valueStyle,
    List<Widget> actions = const [],
    VoidCallback? onTapValue,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 460;
        final labelLine = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSub),
            ),
          ],
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  labelLine,
                  const Spacer(),
                  ...actions,
                ],
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: onTapValue,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.only(left: 28, bottom: 4),
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: valueStyle,
                  ),
                ),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            SizedBox(
              width: 108,
              child: Text(
                label,
                style:
                    const TextStyle(fontSize: 12.5, color: AppColors.textSub),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: onTapValue,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: valueStyle,
                  ),
                ),
              ),
            ),
            ...actions,
          ],
        );
      },
    );
  }

  Widget _iconAction(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required String text,
    required String toast,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: text));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(toast)));
      },
      icon: Icon(icon, size: 16, color: AppColors.textSub),
    );
  }

  // ------------------------------------------------------------- 功能

  Widget _featuresCard() {
    const items = <String>[
      '通联日志记录',
      'ADIF 导入导出',
      '中继台档案',
      '日志总览',
      '数据分析',
      'JSON / CSV 备份',
      'EdgeOne 云同步',
      '端到端加密',
      '网格与方位角',
      '连续录入模式',
      '桌面快捷键',
      '多端自适应',
    ];

    return SectionCard(
      title: '功能一览',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                e,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- 隐私

  Widget _privacyCard(BuildContext context, AppState app) {
    const points = <String>[
      '默认纯本地运行，不联网、不上传任何数据',
      '只有你主动点「同步」才会把日志上传到你自己的 EdgeOne 空间',
      'API Token 与同步密码只存在本机（Windows DPAPI / Android Keystore）',
      '任何导出文件都不含 Token 与密码',
      '「检查更新」仅在你主动点击时访问 GitHub API，不发送任何本地数据',
      '没有账号、没有统计、没有埋点',
    ];

    return SectionCard(
      title: '数据与隐私',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '数据目录：${app.db.dataDir.path}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textHint,
                  ),
                ),
              ),
              IconButton(
                tooltip: '复制数据目录',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: app.db.dataDir.path),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制数据目录')),
                  );
                },
                icon: const Icon(Icons.copy, size: 15),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final p in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.check_circle,
                        size: 13, color: AppColors.accent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.55,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- 技术

  Widget _techCard() {
    const stacks = <String>[
      'Flutter 3.47',
      'Dart 3.13',
      'SQLite',
      'COS 签名 v1',
      'AES-256-GCM',
      'DPAPI / Keystore',
    ];

    return SectionCard(
      title: '技术栈',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in stacks)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F5FE),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    s,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '界面全部自绘，不使用 WebView 套壳；网格、大圆距离、方位角、'
            '日出日落等算法均为本地实现，不依赖任何在线服务。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: AppColors.textSub,
            ),
          ),
        ],
      ),
    );
  }

  Widget _disclaimerCard() {
    return SectionCard(
      title: '免责声明',
      child: const Text(
        '本程序为业余无线电爱好者自用的日志工具，与任何无线电管理机构无关联。'
        '通联记录的真实性与合法性由使用者自行负责，请遵守所在国家或地区的'
        '无线电管理法规与业余无线电操作规范。',
        style: TextStyle(
          fontSize: 12.5,
          height: 1.6,
          color: AppColors.textSub,
        ),
      ),
    );
  }

  Future<void> _openBlog(BuildContext context) async {
    try {
      await PlatformLinks.open(blogUrl);
    } catch (_) {
      await Clipboard.setData(const ClipboardData(text: blogUrl));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开浏览器，链接已复制：$blogUrl')),
      );
    }
  }
}

/// 软件更新卡片：手动检查 GitHub Releases。
class _UpdateCard extends StatefulWidget {
  const _UpdateCard();

  @override
  State<_UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<_UpdateCard> {
  bool _busy = false;
  String _msg = '';
  bool _newer = false;
  UpdateInfo? _info;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _msg = '';
      _newer = false;
      _info = null;
    });
    try {
      final r = await UpdateChecker.check(AboutPage.version);
      if (!mounted) return;
      if (r == null) {
        setState(() => _msg = '仓库还没有发布版本');
      } else {
        final newer = UpdateChecker.isNewer(r.latest, AboutPage.version);
        setState(() {
          _info = r;
          _newer = newer;
          _msg = newer
              ? '发现新版本 v${r.latest}（当前 v${AboutPage.version}）'
              : '已是最新版本（v${AboutPage.version}）';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = '检查失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRelease() async {
    final url = _info?.url ?? UpdateChecker.releasesPage;
    try {
      await PlatformLinks.open(url);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开浏览器，链接已复制：$url')),
      );
    }
  }

  Future<void> _showNotes() async {
    final info = _info;
    if (info == null) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title: '更新说明 v${info.latest}',
        child: SizedBox(
          height: 280,
          child: SingleChildScrollView(
            child: Text(
              info.notes.isEmpty ? '该版本没有填写更新说明。' : info.notes,
              style: const TextStyle(fontSize: 12.5, height: 1.6),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openRelease();
            },
            child: const Text('去下载'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '软件更新',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '当前版本 v${AboutPage.version}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMain,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _busy ? null : _check,
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: Text(_busy ? '检查中…' : '检查更新'),
              ),
            ],
          ),
          if (_msg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _msg,
              style: TextStyle(
                fontSize: 12.5,
                color: _newer ? AppColors.primary : AppColors.textSub,
              ),
            ),
          ],
          if (_newer && _info != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _openRelease,
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('去下载'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _showNotes,
                  child: const Text('查看更新说明'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

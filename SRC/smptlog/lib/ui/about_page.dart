/// 关于页：应用信息、作者呼号与博客、数据位置、技术栈与免责声明。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
  static const String version = '1.0.0';
  static const String callsign = 'BG5SWK';
  static const String blogUrl = 'https://www.smallpatch.cn';
  static const String blogLabel = 'www.smallpatch.cn';
  static const String repoUrl = 'https://github.com/lezhengqiuyuan/SMPTLOG';
  static const String repoLabel = 'github.com/lezhengqiuyuan/SMPTLOG';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
      children: [
        _hero(context),
        const SizedBox(height: 14),
        _authorCard(context),
        const SizedBox(height: 14),
        _opensourceCard(context),
        const SizedBox(height: 14),
        _featuresCard(),
        const SizedBox(height: 14),
        _privacyCard(app),
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
    );
  }

  // ------------------------------------------------------------- 顶部

  Widget _hero(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
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
            value: 'GPL-3.0 · 欢迎 Star 与 PR',
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

  /// 双行信息行（标签 + 值 + 右侧操作）。
  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    required TextStyle valueStyle,
    List<Widget> actions = const [],
    VoidCallback? onTapValue,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSub),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: onTapValue,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(value, style: valueStyle),
            ),
          ),
        ),
        ...actions,
      ],
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

  Widget _privacyCard(AppState app) {
    const points = <String>[
      '默认纯本地运行，不联网、不上传任何数据',
      '只有你主动点「同步」才会把日志上传到你自己的 EdgeOne 空间',
      'API Token 与同步密码只存在本机（Windows DPAPI / Android Keystore）',
      '任何导出文件都不含 Token 与密码',
      '没有账号、没有统计、没有埋点',
    ];

    return SectionCard(
      title: '数据与隐私',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            '数据目录：${app.db.dataDir.path}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textHint),
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

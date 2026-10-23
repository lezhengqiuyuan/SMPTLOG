/// 云同步引导页：手把手教用户拿到 projectId 与 API Token。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'about_page.dart' show PlatformLinks;
import 'common.dart';
import 'theme.dart';

class SyncGuidePage extends StatelessWidget {
  const SyncGuidePage({super.key});

  static const String consoleUrl = 'https://console.cloud.tencent.com/edgeone';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('如何开通云同步'),
        actions: [
          TextButton.icon(
            onPressed: () => _openConsole(context),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('打开控制台'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _introCard(),
          const SizedBox(height: 12),
          const NoticeBar(
            text: '本教程针对 EdgeOne。若不想用腾讯云，可在设置里把同步后端切换为「坚果云」，'
                '只需邮箱 + 应用密码，无需这个教程。',
            color: AppColors.primary,
          ),
          const SizedBox(height: 12),
          _step(
            context,
            index: '1',
            title: '注册并开通 EdgeOne Makers',
            body: '用微信或 QQ 登录腾讯云，进入 EdgeOne 控制台，'
                '切换到顶部「Makers」标签页，按提示开通免费版。'
                '免费版每月有 1 GB 存储额度，按每条通联约 150 字节估算，够存数万条记录。',
            action: OutlinedButton.icon(
              onPressed: () => _openConsole(context),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('去控制台'),
            ),
          ),
          _step(
            context,
            index: '2',
            title: '获取 projectId',
            body: '项目部署完成后会自动进入项目页。看浏览器地址栏：\n'
                'console.cloud.tencent.com/edgeone/makers/project/\n'
                'makers-60tcjerf0vgq/deployment/...\n\n'
                '中间那段 makers-60tcjerf0vgq 就是 projectId。',
            copyText: 'makers-60tcjerf0vgq',
            warn: '注意两点：① 旧项目可能以 pages- 开头，同样可用；'
                '② 纯数字的 12 位（例如 100020999478）是腾讯云 APPID，不是 projectId，'
                '填错的报错是「Invalid project」。',
          ),
          _step(
            context,
            index: '3',
            title: '创建 API Token',
            body: '在 Makers 控制台 → 顶部「设置」→ 左侧「API Token」→ 点「创建 API Token」。\n\n'
                '描述填 SMPTLOG，过期时间建议选 1 年。创建成功后**只显示一次**，'
                '请立刻复制并粘贴到本应用的输入框里。',
            warn: '不要把 Token 发到群里或截图里。它相当于你账号下这个应用的钥匙。',
          ),
          _step(
            context,
            index: '4',
            title: '回到本应用填写并测试',
            body: '设置 → 云同步：把 projectId 和 API Token 粘贴进去，'
                '点「测试连接」。看到「连接成功」再点「保存」。\n\n'
                '换设备时同样操作一次即可 —— Token 不会自动带过去，这是设计，不是缺陷。',
          ),
          const SizedBox(height: 12),
          _faqCard(),
          const SizedBox(height: 12),
          const NoticeBar(
            text: 'Token 只保存在本机（Windows 用 DPAPI、Android 用 Keystore），'
                '不会写进日志数据库，也不会进入任何导出文件。',
            color: AppColors.accent,
          ),
        ],
      ),
    );
  }

  Widget _introCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '云同步是可选的',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            '不配置也完全能用：所有功能都在本地运行。'
            '配置后，你在手机和电脑上的通联记录会通过你自己的云端空间保持一致。',
            style: TextStyle(fontSize: 12.5, height: 1.6, color: AppColors.textSub),
          ),
        ],
      ),
    );
  }

  Widget _step(
    BuildContext context, {
    required String index,
    required String title,
    required String body,
    Widget? action,
    String? copyText,
    String? warn,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    index,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    body,
                    style: const TextStyle(fontSize: 12.5, height: 1.65),
                  ),
                  if (copyText != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectableText(
                              copyText,
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '复制示例格式',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: copyText),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制格式示例')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 16),
                        ),
                      ],
                    ),
                  ],
                  if (warn != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 15, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              warn,
                              style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.55,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (action != null) ...[
                    const SizedBox(height: 10),
                    action,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _faqCard() {
    return SectionCard(
      title: '常见报错对照',
      child: Column(
        children: const [
          _FaqRow(
            error: 'ProjectId is required',
            meaning: 'projectId 输入框是空的，先填再点测试。',
          ),
          _FaqRow(
            error: 'Invalid project（code=-1）',
            meaning: 'projectId 格式不对。正确格式形如 makers-60tcjerf0vgq，'
                '从项目页地址栏复制；纯数字的 APPID 不行。',
          ),
          _FaqRow(
            error: 'API Token 无效或已过期',
            meaning: 'Token 复制不完整，或已过期 / 被删除，重新创建一个。',
          ),
          _FaqRow(
            error: '云端存储容量已超限',
            meaning: '免费版 1 GB 用完了，先清理云端旧分片或升级套餐。',
          ),
          _FaqRow(
            error: '网络不可达',
            meaning: '检查网络；公司网络或代理可能拦了 blob-sts.edgeone.site。',
          ),
        ],
      ),
    );
  }

  Future<void> _openConsole(BuildContext context) async {
    try {
      await PlatformLinks.open(consoleUrl);
    } catch (_) {
      await Clipboard.setData(const ClipboardData(text: consoleUrl));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开浏览器，链接已复制：$consoleUrl')),
      );
    }
  }
}

class _FaqRow extends StatelessWidget {
  const _FaqRow({required this.error, required this.meaning});

  final String error;
  final String meaning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 210,
            child: Text(
              error,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.danger,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              meaning,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

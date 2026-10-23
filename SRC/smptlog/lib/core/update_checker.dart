/// 检查 GitHub Releases 是否有新版本。
///
/// 只在用户**主动点击「检查更新」**时联网，不做后台轮询、不做自动下载。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// 当前应用版本号（与 pubspec.yaml 保持一致）。
const String kAppVersion = '1.1.1';

class UpdateInfo {
  UpdateInfo({
    required this.latest,
    required this.url,
    this.title = '',
    this.notes = '',
  });

  /// 去掉 v 前缀的版本号，如 1.0.0
  final String latest;

  /// Release 页面地址
  final String url;

  final String title;
  final String notes;
}

class UpdateChecker {
  static const String repo = 'lezhengqiuyuan/SMPTLOG';
  static const String releasesPage =
      'https://github.com/lezhengqiuyuan/SMPTLOG/releases';

  static const String _api =
      'https://api.github.com/repos/$repo/releases/latest';

  /// 查询最新 Release。没有发布记录时返回 null。
  static Future<UpdateInfo?> check(String currentVersion) async {
    final resp = await http.get(
      Uri.parse(_api),
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'SMPTLOG/$currentVersion',
      },
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode == 404) return null;
    if (resp.statusCode == 403) {
      throw Exception('GitHub 访问频率限制，请稍后再试');
    }
    if (resp.statusCode != 200) {
      throw Exception('GitHub 返回 HTTP ${resp.statusCode}');
    }

    final map = jsonDecode(resp.body);
    if (map is! Map<String, dynamic>) return null;

    final tag = (map['tag_name'] ?? '').toString();
    if (tag.isEmpty) return null;

    return UpdateInfo(
      latest: normalize(tag),
      url: (map['html_url'] ?? releasesPage).toString(),
      title: (map['name'] ?? tag).toString(),
      notes: (map['body'] ?? '').toString(),
    );
  }

  /// 把 `v1.2.3` / `V1.2.3` 统一成 `1.2.3`。
  static String normalize(String tag) =>
      tag.trim().replaceFirst(RegExp(r'^[vV]'), '');

  /// 逐段比较版本号，[latest] 更大时返回 true。
  static bool isNewer(String latest, String current) {
    List<int> parts(String v) => v
        .split(RegExp(r'[.\-+]'))
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();

    final a = parts(latest);
    final b = parts(current);
    final n = math.max(a.length, b.length);
    for (var i = 0; i < n; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}

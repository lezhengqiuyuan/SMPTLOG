/// SMPTLOG 通联日志助手 —— 入口。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/db.dart';
import 'state.dart';

/// 把启动异常写到磁盘，便于定位（用户看不到控制台）。
void _logFatal(Object error, StackTrace? st) {
  try {
    final base = Platform.environment['LOCALAPPDATA'] ??
        Directory.systemTemp.path;
    final dir = Directory('$base\\SMPTLOG');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}startup_error.log');
    f.writeAsStringSync(
      '${DateTime.now().toIso8601String()}\n$error\n${st ?? ''}\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {
    // 日志失败不影响主流程
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 数据库初始化失败时给出可读提示，而不是白屏。
  AppDb db;
  try {
    db = await AppDb.open();
  } catch (e, st) {
    _logFatal(e, st);
    runApp(_FatalApp(message: '数据库初始化失败：$e'));
    return;
  }

  final state = AppState(db);
  try {
    await state.init();
  } catch (e, st) {
    // 初始化部分失败仍可进入界面，功能会逐步可用。
    _logFatal(e, st);
    debugPrint('AppState 初始化异常：$e');
  }

  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const SmptlogApp(),
    ),
  );
}

class _FatalApp extends StatelessWidget {
  const _FatalApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'SMPTLOG 启动失败',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

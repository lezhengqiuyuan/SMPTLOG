/// 应用主题：浅蓝为主，深色可选，默认跟随系统。
library;

import 'package:flutter/material.dart';

/// 设计令牌（与需求定稿色板一一对应）。
class AppColors {
  static const primary = Color(0xFF2F6FED);
  static const primaryDark = Color(0xFF1B4FCC);
  static const accent = Color(0xFF00B8A9);
  static const warning = Color(0xFFF5A623);
  static const danger = Color(0xFFE5484D);
  static const bg = Color(0xFFF5F8FE);
  static const card = Color(0xFFFFFFFF);
  static const divider = Color(0xFFE6EEFA);
  static const textMain = Color(0xFF1B2A41);
  static const textSub = Color(0xFF6B7C99);
  static const textHint = Color(0xFFA8B6CC);

  // 深色
  static const darkBg = Color(0xFF0F1626);
  static const darkCard = Color(0xFF17202F);
  static const darkDivider = Color(0xFF243044);
  static const darkTextMain = Color(0xFFE6EDF8);
  static const darkTextSub = Color(0xFF93A3BC);
}

/// 断点。
class Breakpoints {
  static const double phone = 600;
  static const double tablet = 840;
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      error: AppColors.danger,
      surface: AppColors.card,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      dividerColor: AppColors.divider,
      fontFamily: _fontFamily,
      fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'Noto Sans SC'],
      visualDensity: VisualDensity.standard,
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.divider),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: AppColors.textMain,
        titleTextStyle: TextStyle(
          color: AppColors.textMain,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF0F5FE),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        hintStyle: const TextStyle(color: AppColors.textHint),
        labelStyle: const TextStyle(color: AppColors.textSub),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.divider),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFEFF5FF),
        labelStyle: const TextStyle(color: AppColors.textMain, fontSize: 13),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      dataTableTheme: const DataTableThemeData(
        headingTextStyle: TextStyle(
          color: AppColors.textSub,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        dataTextStyle: TextStyle(color: AppColors.textMain, fontSize: 13),
      ),
      textTheme: ThemeData(brightness: Brightness.light).textTheme.apply(
        bodyColor: AppColors.textMain,
        displayColor: AppColors.textMain,
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF6E9BFF),
      secondary: AppColors.accent,
      error: AppColors.danger,
      surface: AppColors.darkCard,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.darkBg,
      dividerColor: AppColors.darkDivider,
      fontFamily: _fontFamily,
      fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'Noto Sans SC'],
      cardTheme: CardThemeData(
        color: AppColors.darkCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.darkDivider),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: AppColors.darkTextMain,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1D2838),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF6E9BFF), width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF1D2838),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      textTheme: ThemeData(brightness: Brightness.dark).textTheme.apply(
        bodyColor: AppColors.darkTextMain,
        displayColor: AppColors.darkTextMain,
      ),
    );
  }

  static String? get _fontFamily => null;
}

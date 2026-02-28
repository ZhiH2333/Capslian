import 'package:flutter/material.dart';

import 'theme_settings.dart';

/// 应用主题集中管理；支持 [ThemeSettings] 可配置项。
class AppTheme {
  AppTheme._();

  static const Color _seedColor = Colors.deepPurple;

  /// 浅色主题。[settings] 为 null 时使用默认配置。
  static ThemeData light([ThemeSettings? settings]) {
    final s = settings ?? const ThemeSettings();
    final colorScheme = ColorScheme.fromSeed(seedColor: _seedColor);
    return _buildTheme(
      colorScheme: colorScheme,
      settings: s,
      brightness: Brightness.light,
    );
  }

  /// 深色主题。[settings] 为 null 时使用默认配置。
  static ThemeData dark([ThemeSettings? settings]) {
    final s = settings ?? const ThemeSettings();
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );
    return _buildTheme(
      colorScheme: colorScheme,
      settings: s,
      brightness: Brightness.dark,
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required ThemeSettings settings,
    required Brightness brightness,
  }) {
    final fontFamily = settings.fontFamilyList.isEmpty ? null : settings.fontFamilyList.first;
    final TextTheme baseTextTheme = brightness == Brightness.dark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;
    final TextTheme textTheme = fontFamily != null
        ? _applyFontFamily(baseTextTheme, fontFamily)
        : baseTextTheme;

    final AppBarTheme appBarTheme = settings.appBarTransparent
        ? AppBarTheme(
            centerTitle: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
            foregroundColor: colorScheme.onSurface,
            iconTheme: IconThemeData(color: colorScheme.onSurface),
          )
        : AppBarTheme(
            centerTitle: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.onSurface,
            iconTheme: IconThemeData(color: colorScheme.onSurface),
            surfaceTintColor: Colors.transparent,
          );

    final Color cardColor = colorScheme.surfaceContainer
        .withOpacity(settings.cardTransparency);
    final CardThemeData cardTheme = CardThemeData(
      color: cardColor,
      elevation: settings.cardTransparency < 1 ? 0 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: EdgeInsets.zero,
    );

    final IconThemeData iconTheme = IconThemeData(
      color: colorScheme.onSurface,
      fill: 0,
      weight: 400,
      opticalSize: 20,
      size: 24,
    );

    final ListTileThemeData listTileTheme = ListTileThemeData(
      contentPadding: const EdgeInsets.only(left: 24, right: 17),
      minLeadingWidth: 48,
    );

    final InputDecorationTheme inputDecorationTheme = InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,
      appBarTheme: appBarTheme,
      cardTheme: cardTheme,
      iconTheme: iconTheme,
      listTileTheme: listTileTheme,
      inputDecorationTheme: inputDecorationTheme,
    );
  }

  static TextTheme _applyFontFamily(TextTheme base, String fontFamily) {
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(fontFamily: fontFamily),
      displayMedium: base.displayMedium?.copyWith(fontFamily: fontFamily),
      displaySmall: base.displaySmall?.copyWith(fontFamily: fontFamily),
      headlineLarge: base.headlineLarge?.copyWith(fontFamily: fontFamily),
      headlineMedium: base.headlineMedium?.copyWith(fontFamily: fontFamily),
      headlineSmall: base.headlineSmall?.copyWith(fontFamily: fontFamily),
      titleLarge: base.titleLarge?.copyWith(fontFamily: fontFamily),
      titleMedium: base.titleMedium?.copyWith(fontFamily: fontFamily),
      titleSmall: base.titleSmall?.copyWith(fontFamily: fontFamily),
      bodyLarge: base.bodyLarge?.copyWith(fontFamily: fontFamily),
      bodyMedium: base.bodyMedium?.copyWith(fontFamily: fontFamily),
      bodySmall: base.bodySmall?.copyWith(fontFamily: fontFamily),
      labelLarge: base.labelLarge?.copyWith(fontFamily: fontFamily),
      labelMedium: base.labelMedium?.copyWith(fontFamily: fontFamily),
      labelSmall: base.labelSmall?.copyWith(fontFamily: fontFamily),
    );
  }
}

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Builds light/dark themes from the user-selected accent color.
/// Note: the Persian-optimised font (e.g. Vazirmatn) is not bundled yet; the
/// platform default font is used until it is added under assets/fonts/.
abstract final class AppTheme {
  static ThemeData build(Brightness brightness, Color accent) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      secondary: AppColors.violet,
      error: AppColors.red,
      surface: dark ? AppColors.surface : AppColors.lightSurface,
    );
    final scaffold = dark ? AppColors.bg0 : AppColors.lightBg;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? AppColors.bg1 : AppColors.lightSurface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: dark ? AppColors.bg1 : AppColors.lightSurface,
      ),
      dividerColor: dark ? AppColors.surface2 : const Color(0xFFD9E0EC),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selectedTileColor: accent.withAlpha(30),
        selectedColor: accent,
      ),
    );
  }
}

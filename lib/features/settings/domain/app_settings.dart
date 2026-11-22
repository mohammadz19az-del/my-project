import 'package:flutter/material.dart';

/// Persisted user preferences (stored in `application_settings`).
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.localeCode = 'en',
    this.accentColorValue = defaultAccent,
    this.animationsEnabled = true,
    this.reducedMotion = false,
    this.notifyCompletion = true,
    this.notifyErrors = true,
    this.notifyAuth = true,
  });

  static const int defaultAccent = 0xFF22D3EE; // electric cyan
  static const List<int> accentChoices = [
    0xFF22D3EE, // cyan
    0xFF3B82F6, // neon blue
    0xFF8B5CF6, // violet
    0xFF10B981, // emerald
  ];

  static const keyThemeMode = 'theme_mode';
  static const keyLocale = 'locale';
  static const keyAccent = 'accent_color';
  static const keyAnimations = 'animations_enabled';
  static const keyReducedMotion = 'reduced_motion';
  static const keyNotifyCompletion = 'notify_completion';
  static const keyNotifyErrors = 'notify_errors';
  static const keyNotifyAuth = 'notify_auth';

  final ThemeMode themeMode;
  final String localeCode; // 'en' | 'fa'
  final int accentColorValue;
  final bool animationsEnabled;
  final bool reducedMotion;

  /// In-app notices (snackbars) for campaign completion, errors and expired credentials.
  final bool notifyCompletion;
  final bool notifyErrors;
  final bool notifyAuth;

  Locale get locale => Locale(localeCode);
  Color get accent => Color(accentColorValue);

  /// Page/route animations run only when enabled and motion is not reduced.
  bool get shouldAnimate => animationsEnabled && !reducedMotion;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? localeCode,
    int? accentColorValue,
    bool? animationsEnabled,
    bool? reducedMotion,
    bool? notifyCompletion,
    bool? notifyErrors,
    bool? notifyAuth,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        localeCode: localeCode ?? this.localeCode,
        accentColorValue: accentColorValue ?? this.accentColorValue,
        animationsEnabled: animationsEnabled ?? this.animationsEnabled,
        reducedMotion: reducedMotion ?? this.reducedMotion,
        notifyCompletion: notifyCompletion ?? this.notifyCompletion,
        notifyErrors: notifyErrors ?? this.notifyErrors,
        notifyAuth: notifyAuth ?? this.notifyAuth,
      );

  factory AppSettings.fromMap(Map<String, String> m) {
    final theme = ThemeMode.values.where((t) => t.name == m[keyThemeMode]);
    final locale = m[keyLocale];
    return AppSettings(
      themeMode: theme.isEmpty ? ThemeMode.dark : theme.first,
      localeCode: (locale == 'fa' || locale == 'en') ? locale! : 'en',
      accentColorValue: int.tryParse(m[keyAccent] ?? '') ?? defaultAccent,
      animationsEnabled: (m[keyAnimations] ?? 'true') == 'true',
      reducedMotion: (m[keyReducedMotion] ?? 'false') == 'true',
      notifyCompletion: (m[keyNotifyCompletion] ?? 'true') == 'true',
      notifyErrors: (m[keyNotifyErrors] ?? 'true') == 'true',
      notifyAuth: (m[keyNotifyAuth] ?? 'true') == 'true',
    );
  }
}

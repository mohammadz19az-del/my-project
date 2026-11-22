import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/app_settings.dart';

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Loads settings from SQLite and persists every change before updating state.
class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final values = await ref.watch(settingsRepositoryProvider).getAll();
    return AppSettings.fromMap(values);
  }

  AppSettings get _current => state.valueOrNull ?? const AppSettings();

  Future<void> _apply(AppSettings next, Map<String, String> changed) async {
    await ref.read(settingsRepositoryProvider).setValues(changed);
    state = AsyncData(next);
  }

  Future<void> setThemeMode(ThemeMode mode) => _apply(
        _current.copyWith(themeMode: mode),
        {AppSettings.keyThemeMode: mode.name},
      );

  Future<void> setLocale(String code) => _apply(
        _current.copyWith(localeCode: code),
        {AppSettings.keyLocale: code},
      );

  Future<void> setAccentColor(int value) => _apply(
        _current.copyWith(accentColorValue: value),
        {AppSettings.keyAccent: '$value'},
      );

  Future<void> setAnimationsEnabled(bool value) => _apply(
        _current.copyWith(animationsEnabled: value),
        {AppSettings.keyAnimations: '$value'},
      );

  Future<void> setNotify(String key, bool value) {
    final c = _current;
    final next = switch (key) {
      AppSettings.keyNotifyCompletion => c.copyWith(notifyCompletion: value),
      AppSettings.keyNotifyErrors => c.copyWith(notifyErrors: value),
      _ => c.copyWith(notifyAuth: value),
    };
    return _apply(next, {key: '$value'});
  }

  Future<void> setReducedMotion(bool value) => _apply(
        _current.copyWith(reducedMotion: value),
        {AppSettings.keyReducedMotion: '$value'},
      );
}

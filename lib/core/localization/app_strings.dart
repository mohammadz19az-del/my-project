import 'package:flutter/widgets.dart';

import 'strings_en.dart';
import 'strings_fa.dart';

/// Lightweight localization resource lookup for English and Persian.
/// All UI text goes through [t]; do not hard-code user-facing strings in widgets.
class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = [Locale('en'), Locale('fa')];
  static const LocalizationsDelegate<AppStrings> delegate = _AppStringsDelegate();

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ?? const AppStrings(Locale('en'));

  Map<String, String> get _table => locale.languageCode == 'fa' ? stringsFa : stringsEn;

  bool has(String key) => _table.containsKey(key) || stringsEn.containsKey(key);

  /// Looks up [key], falling back to English, then to the key itself.
  /// `{name}` placeholders are replaced from [args].
  String t(String key, {Map<String, String> args = const {}}) {
    var value = _table[key] ?? stringsEn[key] ?? key;
    args.forEach((k, v) => value = value.replaceAll('{$k}', v));
    return value;
  }
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppStrings.supportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) async => AppStrings(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppStrings> old) => false;
}

extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStrings.of(this);
  String tr(String key, {Map<String, String> args = const {}}) =>
      strings.t(key, args: args);
}

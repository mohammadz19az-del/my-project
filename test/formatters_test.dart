import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tesla_org/core/localization/app_strings.dart';
import 'package:tesla_org/core/utilities/formatters.dart';

void main() {
  setUpAll(() async => initializeDateFormatting());

  const en = Locale('en');
  const fa = Locale('fa');
  final now = DateTime(2026, 11, 15, 12);

  test('Gregorian to Jalali matches known dates', () {
    expect(gregorianToJalali(2026, 3, 21), (year: 1405, month: 1, day: 1));
    expect(gregorianToJalali(2025, 3, 21), (year: 1404, month: 1, day: 1));
    expect(gregorianToJalali(2024, 3, 20), (year: 1403, month: 1, day: 1));
    expect(gregorianToJalali(2023, 1, 1), (year: 1401, month: 10, day: 11));
  });

  test('Persian dates use Jalali with Persian digits; English stays Gregorian', () {
    expect(formatDateFor(fa, DateTime(2026, 3, 21)), '۱ فروردین ۱۴۰۵');
    expect(formatDateFor(en, DateTime(2026, 3, 21)), isNot(contains('۱')));
    expect(formatDateTimeFor(fa, DateTime(2026, 3, 21, 9, 5)).endsWith('۰۹:۰۵'), isTrue);
  });

  test('text direction follows the first strong letter', () {
    expect(textDirectionFor('سلام hello'), TextDirection.rtl);
    expect(textDirectionFor('hello سلام'), TextDirection.ltr);
    expect(textDirectionFor('123 ...'), TextDirection.ltr);
  });

  test('number formatting follows the locale', () {
    expect(formatNumberFor(en, 1234), '1,234');
    expect(RegExp(r'[۰-۹]').hasMatch(formatNumberFor(fa, 1234)), isTrue);
  });

  test('relative time in English', () {
    const s = AppStrings(en);
    String r(Duration d) => formatRelativeWith(s, en, now.subtract(d), now);
    expect(r(const Duration(seconds: 20)), 'Just now');
    expect(r(const Duration(minutes: 5)), '5 min ago');
    expect(r(const Duration(hours: 3)), '3 h ago');
    expect(r(const Duration(days: 2)), '2 d ago');
    expect(r(const Duration(days: 30)), isNotEmpty);
  });

  test('relative time in Persian uses Persian words and digits', () {
    const s = AppStrings(fa);
    final text = formatRelativeWith(s, fa, now.subtract(const Duration(minutes: 5)), now);
    expect(text.contains('دقیقه'), isTrue);
    expect(RegExp(r'[0-9]').hasMatch(text), isFalse);
  });
}

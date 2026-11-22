import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../localization/app_strings.dart';

/// Locale-aware integer formatting (Persian digits for `fa`).
String formatNumberFor(Locale locale, int value) =>
    NumberFormat.decimalPattern(locale.languageCode).format(value);

String formatNumber(BuildContext context, int value) =>
    formatNumberFor(Localizations.localeOf(context), value);

/// Relative time ("5 min ago"); dates older than a week use a localized date.
/// Requires `initializeDateFormatting()` (done in bootstrap).
/// Note: the Gregorian calendar is used for both languages; Jalali is not implemented.
String formatRelativeWith(AppStrings strings, Locale locale, DateTime time, DateTime now) {
  final diff = now.difference(time);
  String n(int v) => formatNumberFor(locale, v);
  if (diff.inSeconds < 60) return strings.t('time_just_now');
  if (diff.inMinutes < 60) return strings.t('time_minutes_ago', args: {'n': n(diff.inMinutes)});
  if (diff.inHours < 24) return strings.t('time_hours_ago', args: {'n': n(diff.inHours)});
  if (diff.inDays < 7) return strings.t('time_days_ago', args: {'n': n(diff.inDays)});
  return formatDateFor(locale, time.toLocal());
}

String formatRelative(BuildContext context, DateTime time) => formatRelativeWith(
      AppStrings.of(context),
      Localizations.localeOf(context),
      time,
      DateTime.now(),
    );

const List<String> _jalaliMonths = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];

/// Gregorian -> Jalali (Solar Hijri). Pure arithmetic; verified against known dates.
({int year, int month, int day}) gregorianToJalali(int gy, int gm, int gd) {
  const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy2 = gm > 2 ? gy + 1 : gy;
  var days = 355666 +
      (365 * gy) +
      ((gy2 + 3) ~/ 4) -
      ((gy2 + 99) ~/ 100) +
      ((gy2 + 399) ~/ 400) +
      gd +
      gdm[gm - 1];
  var jy = -1595 + (33 * (days ~/ 12053));
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    jy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  final jm = days < 186 ? 1 + days ~/ 31 : 7 + (days - 186) ~/ 30;
  final jd = 1 + (days < 186 ? days % 31 : (days - 186) % 30);
  return (year: jy, month: jm, day: jd);
}

String _persianDigits(String s) =>
    s.replaceAllMapped(RegExp('[0-9]'), (m) => String.fromCharCode(0x06F0 + int.parse(m[0]!)));

/// Persian locale -> Jalali date with Persian digits; otherwise a Gregorian date.
/// Requires `initializeDateFormatting()` for the Gregorian branch.
String formatDateFor(Locale locale, DateTime t) {
  if (locale.languageCode == 'fa') {
    final j = gregorianToJalali(t.year, t.month, t.day);
    return _persianDigits('${j.day} ${_jalaliMonths[j.month - 1]} ${j.year}');
  }
  return DateFormat.yMMMd(locale.languageCode).format(t);
}

String formatDateTimeFor(Locale locale, DateTime t) {
  final local = t.toLocal();
  final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  final text = '${formatDateFor(locale, local)} $time';
  return locale.languageCode == 'fa' ? _persianDigits(text) : text;
}

/// Localized date and time (Jalali for Persian, Gregorian otherwise).
String formatDateTime(BuildContext context, DateTime time) =>
    formatDateTimeFor(Localizations.localeOf(context), time);

/// Direction of free text from its first strongly-directional letter, so a
/// Persian message renders right-to-left even inside an English interface.
TextDirection textDirectionFor(String text) {
  for (final rune in text.runes) {
    final arabic = (rune >= 0x0600 && rune <= 0x06FF) ||
        (rune >= 0x0750 && rune <= 0x077F) ||
        (rune >= 0xFB50 && rune <= 0xFDFF) ||
        (rune >= 0xFE70 && rune <= 0xFEFF);
    if (arabic) return TextDirection.rtl;
    final latin = (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);
    if (latin) return TextDirection.ltr;
  }
  return TextDirection.ltr;
}

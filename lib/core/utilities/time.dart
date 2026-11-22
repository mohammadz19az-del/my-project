/// ISO-8601 UTC timestamp used for every stored date/time.
String nowIso() => DateTime.now().toUtc().toIso8601String();

DateTime? parseDate(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw as String);
}

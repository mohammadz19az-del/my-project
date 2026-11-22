import 'dart:developer' as developer;

/// Minimal logger that redacts secrets before anything is written.
/// Never pass passwords, OTPs, tokens, or session data here; redaction is a
/// safety net, not a licence to log them.
abstract final class AppLogger {
  static final RegExp _kv = RegExp(
    r'(password|passwd|otp|token|secret|session|api[_-]?key|authorization)(\s*[:=]\s*)\S+',
    caseSensitive: false,
  );
  static final RegExp _bearer = RegExp(r'Bearer\s+[A-Za-z0-9\-._~+/]+=*', caseSensitive: false);

  static String redact(String input) => input
      .replaceAllMapped(_kv, (m) => '${m[1]}${m[2]}[REDACTED]')
      .replaceAll(_bearer, 'Bearer [REDACTED]');

  static void info(String message) => _log('INFO', message);
  static void warning(String message) => _log('WARN', message);

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    _log('ERROR', error == null ? message : '$message | $error', stackTrace: stackTrace);
  }

  static void _log(String level, String message, {StackTrace? stackTrace}) {
    developer.log(
      redact(message),
      name: 'tesla_org.$level',
      stackTrace: stackTrace,
    );
  }
}

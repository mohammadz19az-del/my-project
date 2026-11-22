import '../../../shared/enums/enums.dart';

/// Offline format checks. They return a localization key on failure, or null.
/// A well-formed value is NOT proof that it works; only a real connection is.
abstract final class AccountValidator {
  static final RegExp _telegramUsername = RegExp(r'^[A-Za-z][A-Za-z0-9_]{4,31}$');
  static final RegExp _telegramToken = RegExp(r'^\d{5,}:[A-Za-z0-9_-]{30,}$');
  static final RegExp _digits = RegExp(r'^\d{5,20}$');

  /// Canonical stored form (Telegram usernames are kept as `@name`).
  static String normalizeIdentifier(MessagingPlatform p, String raw) {
    final t = raw.trim();
    if (p == MessagingPlatform.telegram) {
      return '@${t.startsWith('@') ? t.substring(1) : t}';
    }
    return t;
  }

  static String? validateIdentifier(MessagingPlatform p, String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'validation_required';
    switch (p) {
      case MessagingPlatform.telegram:
        final name = t.startsWith('@') ? t.substring(1) : t;
        if (!_telegramUsername.hasMatch(name) || !name.toLowerCase().endsWith('bot')) {
          return 'validation_telegram_username';
        }
        return null;
      case MessagingPlatform.whatsapp:
        return _digits.hasMatch(t) ? null : 'validation_whatsapp_phone_id';
      case MessagingPlatform.rubika:
      case MessagingPlatform.soroush:
        return t.length <= 64 ? null : 'validation_identifier_length';
    }
  }

  static String? validateSecret(MessagingPlatform p, String key, String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'validation_required';
    switch (p) {
      case MessagingPlatform.telegram:
        return _telegramToken.hasMatch(t) ? null : 'validation_telegram_token';
      case MessagingPlatform.whatsapp:
        return (t.length >= 20 && !t.contains(RegExp(r'\s'))) ? null : 'validation_whatsapp_token';
      case MessagingPlatform.rubika:
      case MessagingPlatform.soroush:
        return null;
    }
  }
}

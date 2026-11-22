/// Shared enumerations. Each value is stored in SQLite as its snake_case name
/// (see [EnumDb.dbValue]); the SQL CHECK constraints in migration 001 use the
/// same literals.
extension EnumDb on Enum {
  String get dbValue => name.replaceAllMapped(
        RegExp('[A-Z]'),
        (m) => '_${m[0]!.toLowerCase()}',
      );
}

T enumFromDb<T extends Enum>(List<T> values, Object? raw, {T? fallback}) {
  for (final v in values) {
    if (v.dbValue == raw) return v;
  }
  if (fallback != null) return fallback;
  throw FormatException('Unknown ${T.toString()} value in database: $raw');
}

enum MessagingPlatform { telegram, whatsapp, rubika, soroush }

extension MessagingPlatformLabel on MessagingPlatform {
  /// Brand names are not translated.
  String get label => switch (this) {
        MessagingPlatform.telegram => 'Telegram',
        MessagingPlatform.whatsapp => 'WhatsApp',
        MessagingPlatform.rubika => 'Rubika',
        MessagingPlatform.soroush => 'Soroush',
      };
}

enum ConnectionStatus {
  connected,
  disconnected,
  connecting,
  authenticationRequired,
  credentialsExpired,
  rateLimited,
  unsupported,
  error,

  /// A simulated connection from a mock adapter. Must never be presented as real.
  mockConnection,
}

enum MessageLanguage { persian, english, mixed }

enum ValidationStatus {
  invalidFormat,
  validFormat,
  verified,
  inaccessible,
  authorizationUnavailable,
  unknown,
}

enum CampaignStatus { draft, scheduled, running, paused, completed, cancelled, failed }

enum DeliveryStatus { pending, sending, sent, delivered, failed, skipped }

enum ConsentStatus { pending, granted, denied, revoked }

enum AuthorizationStatus { authorized, unauthorized, unknown }

enum EventSeverity { info, warning, error, security }

enum DestinationType { user, group, channel, other }

/// Capability/readiness of a platform integration (see project spec, Part 9).
enum IntegrationStatus {
  supported,
  partiallySupported,
  unsupported,
  notVerified,
  requiresApproval,
  mockOnly,
}

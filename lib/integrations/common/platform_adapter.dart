import '../../shared/enums/enums.dart';

/// How trustworthy a platform connection is.
enum AdapterMode {
  /// Talks to the platform's official, documented API.
  real,

  /// Simulation only. Never presented as a real connection; sends nothing.
  mock,

  /// No adapter exists for the platform.
  pending,
}

/// Secret values for one account. [toString] never reveals them.
class AccountCredentials {
  const AccountCredentials(this.values);

  final Map<String, String> values;

  String? operator [](String key) => values[key];

  @override
  String toString() => 'AccountCredentials(<redacted>)';
}

class ConnectResult {
  const ConnectResult(this.status, {this.displayName, this.errorCode});

  final ConnectionStatus status;
  final String? displayName;

  /// Stable, non-sensitive code (e.g. `TG_401`); stored in the audit log.
  final String? errorCode;
}

class SendRequest {
  const SendRequest({
    required this.accountIdentifier,
    required this.credentials,
    required this.destinationId,
    required this.text,
    this.templateName,
    this.templateLanguage,
  });

  final String accountIdentifier;
  final AccountCredentials credentials;
  final String destinationId;
  final String text;

  /// WhatsApp only: send this Meta-approved template instead of free text.
  final String? templateName;
  final String? templateLanguage;
}

enum SendOutcome {
  /// Accepted by the platform's API (NOT proof of delivery or reading).
  sent,

  /// A mock adapter: nothing was sent.
  simulated,
  rateLimited,

  /// Credentials rejected; every further send would fail too.
  authFailed,

  /// Permanently refused for this destination (blocked, not found, ...).
  rejected,

  /// Temporary failure (network, server error); safe to retry.
  retryable,
}

class SendResult {
  const SendResult(
    this.outcome, {
    this.messageId,
    this.errorCode,
    this.errorMessage,
    this.retryAfter,
  });

  final SendOutcome outcome;
  final String? messageId;
  final String? errorCode;
  final String? errorMessage;
  final Duration? retryAfter;
}

class GroupCheck {
  const GroupCheck(this.status, {this.title});

  final ValidationStatus status;
  final String? title;
}

/// Capability matrix (project spec, Part 9). Statuses use [IntegrationStatus].
class AdapterCapabilities {
  const AdapterCapabilities({
    required this.items,
    required this.overall,
    this.minIntervalSeconds = 1,
    this.maxTextLength = 4096,
  });

  static const List<String> keys = [
    'api_availability',
    'authentication',
    'account_connection',
    'text_messaging',
    'group_messaging',
    'destination_discovery',
    'delivery_status',
    'link_validation',
    'rate_limit_handling',
    'production_readiness',
  ];

  final Map<String, IntegrationStatus> items;
  final IntegrationStatus overall;

  /// Smallest pause between two sends the app allows for this platform.
  final int minIntervalSeconds;
  final int maxTextLength;
}

abstract class PlatformAdapter {
  MessagingPlatform get platform;
  AdapterMode get mode;
  AdapterCapabilities get capabilities;

  Future<ConnectResult> connect({
    required String accountIdentifier,
    required AccountCredentials credentials,
  });

  Future<void> disconnect({required String accountIdentifier});

  Future<SendResult> sendText(SendRequest request);

  /// Authorized lookup of a group link. Never returns `verified` unless the
  /// platform's official API confirmed that the destination exists.
  Future<GroupCheck> checkGroupLink({
    required AccountCredentials credentials,
    required String url,
  });
}

class AdapterRegistry {
  AdapterRegistry(Iterable<PlatformAdapter> adapters)
      : _byPlatform = {for (final a in adapters) a.platform: a} {
    for (final p in MessagingPlatform.values) {
      if (!_byPlatform.containsKey(p)) {
        throw ArgumentError('No adapter registered for ${p.name}');
      }
    }
  }

  final Map<MessagingPlatform, PlatformAdapter> _byPlatform;

  PlatformAdapter forPlatform(MessagingPlatform p) => _byPlatform[p]!;
}

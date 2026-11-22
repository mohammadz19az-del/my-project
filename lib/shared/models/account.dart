import '../../core/utilities/time.dart';
import '../enums/enums.dart';

/// A managed messaging account. Holds only non-secret metadata; secrets live in
/// secure storage and are referenced by [credentialReference].
class Account {
  const Account({
    required this.id,
    required this.platform,
    required this.accountIdentifier,
    required this.connectionStatus,
    required this.capabilitiesJson,
    required this.createdAt,
    required this.updatedAt,
    this.displayName,
    this.credentialReference,
    this.lastConnectedAt,
    this.lastActivityAt,
  });

  final int id;
  final MessagingPlatform platform;
  final String accountIdentifier;
  final String? displayName;
  final ConnectionStatus connectionStatus;
  final String? credentialReference;
  final String capabilitiesJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastConnectedAt;
  final DateTime? lastActivityAt;

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id']! as int,
        platform: enumFromDb(MessagingPlatform.values, m['platform']),
        accountIdentifier: m['account_identifier']! as String,
        displayName: m['display_name'] as String?,
        connectionStatus: enumFromDb(
          ConnectionStatus.values,
          m['connection_status'],
          fallback: ConnectionStatus.error,
        ),
        credentialReference: m['credential_reference'] as String?,
        capabilitiesJson: (m['capabilities_json'] as String?) ?? '{}',
        createdAt: DateTime.parse(m['created_at']! as String),
        updatedAt: DateTime.parse(m['updated_at']! as String),
        lastConnectedAt: parseDate(m['last_connected_at']),
        lastActivityAt: parseDate(m['last_activity_at']),
      );
}

/// Input for creating an account (no id/timestamps yet).
class AccountInput {
  const AccountInput({
    required this.platform,
    required this.accountIdentifier,
    this.displayName,
    this.credentialReference,
  });

  final MessagingPlatform platform;
  final String accountIdentifier;
  final String? displayName;
  final String? credentialReference;
}

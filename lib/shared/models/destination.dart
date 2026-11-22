import '../enums/enums.dart';

/// A place a campaign may deliver to (user, group, channel) for one account.
class Destination {
  const Destination({
    required this.id,
    required this.accountId,
    required this.platformDestinationId,
    required this.destinationType,
    required this.authorizationStatus,
    required this.createdAt,
    this.displayName,
  });

  final int id;
  final int accountId;
  final String platformDestinationId;
  final String? displayName;
  final DestinationType destinationType;
  final AuthorizationStatus authorizationStatus;
  final DateTime createdAt;

  factory Destination.fromMap(Map<String, Object?> m) => Destination(
        id: m['id']! as int,
        accountId: m['account_id']! as int,
        platformDestinationId: m['platform_destination_id']! as String,
        displayName: m['display_name'] as String?,
        destinationType: enumFromDb(DestinationType.values, m['destination_type'],
            fallback: DestinationType.other),
        authorizationStatus: enumFromDb(AuthorizationStatus.values, m['authorization_status'],
            fallback: AuthorizationStatus.unknown),
        createdAt: DateTime.parse(m['created_at']! as String),
      );
}

class DestinationInput {
  const DestinationInput({
    required this.accountId,
    required this.platformDestinationId,
    this.displayName,
    this.destinationType = DestinationType.other,
    this.authorizationStatus = AuthorizationStatus.unknown,
  });

  final int accountId;
  final String platformDestinationId;
  final String? displayName;
  final DestinationType destinationType;
  final AuthorizationStatus authorizationStatus;
}

import '../../core/utilities/time.dart';
import '../enums/enums.dart';

class Campaign {
  const Campaign({
    required this.id,
    required this.name,
    required this.accountId,
    required this.templateId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.scheduleStart,
    this.scheduleEnd,
    this.timezone,
    this.startedAt,
    this.completedAt,
    this.sendIntervalSeconds = 5,
    this.rounds = 1,
    this.maxDeliveries,
  });

  final int id;
  final String name;
  final int accountId;
  final int templateId;
  final CampaignStatus status;
  final DateTime? scheduleStart;
  final DateTime? scheduleEnd;
  final String? timezone;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  /// Pause between two sends, in seconds.
  final int sendIntervalSeconds;

  /// How many times each destination receives the message (1-5).
  final int rounds;

  /// Optional cap on send attempts for the whole campaign.
  final int? maxDeliveries;

  /// Statuses that count as "active" on the dashboard.
  static const Set<CampaignStatus> activeStatuses = {
    CampaignStatus.scheduled,
    CampaignStatus.running,
    CampaignStatus.paused,
  };

  factory Campaign.fromMap(Map<String, Object?> m) => Campaign(
        id: m['id']! as int,
        name: m['name']! as String,
        accountId: m['account_id']! as int,
        templateId: m['template_id']! as int,
        status: enumFromDb(CampaignStatus.values, m['status']),
        scheduleStart: parseDate(m['schedule_start']),
        scheduleEnd: parseDate(m['schedule_end']),
        timezone: m['timezone'] as String?,
        createdAt: DateTime.parse(m['created_at']! as String),
        updatedAt: DateTime.parse(m['updated_at']! as String),
        startedAt: parseDate(m['started_at']),
        completedAt: parseDate(m['completed_at']),
        sendIntervalSeconds: (m['send_interval_seconds'] as int?) ?? 5,
        rounds: (m['rounds'] as int?) ?? 1,
        maxDeliveries: m['max_deliveries'] as int?,
      );
}

class CampaignInput {
  const CampaignInput({
    required this.name,
    required this.accountId,
    required this.templateId,
    this.scheduleStart,
    this.scheduleEnd,
    this.timezone,
    this.sendIntervalSeconds = 5,
    this.rounds = 1,
    this.maxDeliveries,
  });

  final String name;
  final int accountId;
  final int templateId;
  final DateTime? scheduleStart;
  final DateTime? scheduleEnd;
  final String? timezone;
  final int sendIntervalSeconds;
  final int rounds;
  final int? maxDeliveries;
}

/// A destination attached to a campaign, with its consent/authorization state.
class CampaignDestination {
  const CampaignDestination({
    required this.id,
    required this.campaignId,
    required this.destinationId,
    required this.consentStatus,
    required this.authorizationStatus,
    required this.platformDestinationId,
    this.displayName,
  });

  final int id;
  final int campaignId;
  final int destinationId;
  final ConsentStatus consentStatus;
  final AuthorizationStatus authorizationStatus;
  final String platformDestinationId;
  final String? displayName;

  /// Messaging is permitted only with granted consent AND authorization.
  bool get isDeliverable =>
      consentStatus == ConsentStatus.granted &&
      authorizationStatus == AuthorizationStatus.authorized;

  factory CampaignDestination.fromMap(Map<String, Object?> m) => CampaignDestination(
        id: m['id']! as int,
        campaignId: m['campaign_id']! as int,
        destinationId: m['destination_id']! as int,
        consentStatus: enumFromDb(ConsentStatus.values, m['consent_status'],
            fallback: ConsentStatus.pending),
        authorizationStatus: enumFromDb(AuthorizationStatus.values, m['authorization_status'],
            fallback: AuthorizationStatus.unknown),
        platformDestinationId: m['platform_destination_id']! as String,
        displayName: m['destination_name'] as String?,
      );
}

import 'dart:convert';

import '../enums/enums.dart';

class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.eventType,
    required this.description,
    required this.severity,
    required this.metadataJson,
    required this.createdAt,
    this.accountId,
    this.campaignId,
  });

  final int id;
  final String eventType;
  final int? accountId;
  final int? campaignId;
  final String description;
  final EventSeverity severity;
  final String metadataJson;
  final DateTime createdAt;

  factory ActivityEvent.fromMap(Map<String, Object?> m) => ActivityEvent(
        id: m['id']! as int,
        eventType: m['event_type']! as String,
        accountId: m['account_id'] as int?,
        campaignId: m['campaign_id'] as int?,
        description: m['description']! as String,
        severity: enumFromDb(EventSeverity.values, m['severity'],
            fallback: EventSeverity.info),
        metadataJson: (m['metadata_json'] as String?) ?? '{}',
        createdAt: DateTime.parse(m['created_at']! as String),
      );
}

class ActivityEventInput {
  const ActivityEventInput({
    required this.eventType,
    required this.description,
    this.severity = EventSeverity.info,
    this.accountId,
    this.campaignId,
    this.metadata = const {},
  });

  final String eventType;
  final String description;
  final EventSeverity severity;
  final int? accountId;
  final int? campaignId;

  /// Must never contain credentials, tokens, OTPs or session data.
  final Map<String, Object?> metadata;

  String get metadataJson => jsonEncode(metadata);
}

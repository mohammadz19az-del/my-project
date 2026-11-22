import '../../core/utilities/time.dart';
import '../enums/enums.dart';

class DeliveryRecord {
  const DeliveryRecord({
    required this.id,
    required this.campaignId,
    required this.destinationId,
    required this.templateId,
    required this.idempotencyKey,
    required this.status,
    required this.attemptCount,
    required this.createdAt,
    required this.updatedAt,
    this.platformMessageId,
    this.errorCode,
    this.errorMessage,
    this.deliveredAt,
  });

  final int id;
  final int campaignId;
  final int destinationId;
  final int templateId;
  final String idempotencyKey;
  final DeliveryStatus status;
  final String? platformMessageId;
  final int attemptCount;
  final String? errorCode;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deliveredAt;

  factory DeliveryRecord.fromMap(Map<String, Object?> m) => DeliveryRecord(
        id: m['id']! as int,
        campaignId: m['campaign_id']! as int,
        destinationId: m['destination_id']! as int,
        templateId: m['template_id']! as int,
        idempotencyKey: m['idempotency_key']! as String,
        status: enumFromDb(DeliveryStatus.values, m['status']),
        platformMessageId: m['platform_message_id'] as String?,
        attemptCount: m['attempt_count']! as int,
        errorCode: m['error_code'] as String?,
        errorMessage: m['error_message'] as String?,
        createdAt: DateTime.parse(m['created_at']! as String),
        updatedAt: DateTime.parse(m['updated_at']! as String),
        deliveredAt: parseDate(m['delivered_at']),
      );
}

class DeliveryInput {
  const DeliveryInput({
    required this.campaignId,
    required this.destinationId,
    required this.templateId,
    required this.idempotencyKey,
  });

  final int campaignId;
  final int destinationId;
  final int templateId;
  final String idempotencyKey;
}

/// Result of [DeliveryRepository.createOrGet]: [created] is false when a record
/// with the same idempotency key already existed (duplicate prevented).
class DeliveryCreateResult {
  const DeliveryCreateResult(this.record, {required this.created});
  final DeliveryRecord record;
  final bool created;
}

import 'package:sqflite/sqflite.dart';

import '../../../core/database/db_guard.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/utilities/time.dart';
import '../../../shared/enums/enums.dart';
import '../../../shared/models/delivery_record.dart';

abstract class DeliveryRepository {
  /// Stable key so the same (campaign, destination, template, round) can never
  /// produce two delivery records. Use a new [round] only for deliberate re-sends.
  static String buildIdempotencyKey({
    required int campaignId,
    required int destinationId,
    required int templateId,
    int round = 1,
  }) =>
      'c$campaignId:d$destinationId:t$templateId:r$round';

  /// Returns the existing record for the key (`created == false`) or inserts a
  /// new `pending` one. The database rejects insertion without granted consent
  /// and an authorized destination (`DELIVERY_CONSENT_REQUIRED`).
  Future<DeliveryCreateResult> createOrGet(DeliveryInput input);

  Future<DeliveryRecord?> getById(int id);
  Future<DeliveryRecord?> getByKey(String idempotencyKey);
  Future<List<DeliveryRecord>> listForCampaign(int campaignId, {DeliveryStatus? status});

  Future<DeliveryRecord> markSending(int id); // pending -> sending, attempt_count + 1
  Future<DeliveryRecord> markSent(int id, {String? platformMessageId});
  Future<DeliveryRecord> markDelivered(int id);
  Future<DeliveryRecord> markFailed(int id, {required String errorCode, String? errorMessage});
  Future<DeliveryRecord> markSkipped(int id, {String? reason});

  /// sending -> pending without counting as failure (rate limit / network retry).
  Future<DeliveryRecord> releaseToPending(int id);

  /// failed -> pending so the engine can retry safely (same record, same key).
  Future<DeliveryRecord> requeueFailed(int id);

  /// Recovery after an app restart: `sending` records whose outcome is unknown
  /// go back to `pending`. Returns how many were reset.
  Future<int> recoverInterrupted();

  Future<Map<DeliveryStatus, int>> countsByStatus({int? campaignId});
}

class SqliteDeliveryRepository implements DeliveryRepository {
  SqliteDeliveryRepository(this._db);

  final Database _db;
  static const _table = 'delivery_records';

  static const Map<DeliveryStatus, Set<DeliveryStatus>> _allowed = {
    DeliveryStatus.pending: {DeliveryStatus.sending, DeliveryStatus.skipped},
    DeliveryStatus.sending: {
      DeliveryStatus.sent,
      DeliveryStatus.failed,
      DeliveryStatus.pending,
      DeliveryStatus.skipped,
    },
    DeliveryStatus.sent: {DeliveryStatus.delivered, DeliveryStatus.failed},
    DeliveryStatus.failed: {DeliveryStatus.pending},
    DeliveryStatus.delivered: <DeliveryStatus>{},
    DeliveryStatus.skipped: <DeliveryStatus>{},
  };

  static bool canTransition(DeliveryStatus from, DeliveryStatus to) =>
      _allowed[from]?.contains(to) ?? false;

  /// Redacts and truncates anything stored from external error text.
  static String? _safeMessage(String? m) {
    if (m == null) return null;
    final redacted = AppLogger.redact(m);
    return redacted.length <= 300 ? redacted : redacted.substring(0, 300);
  }

  @override
  Future<DeliveryCreateResult> createOrGet(DeliveryInput input) => guardDb(() => _db.transaction((txn) async {
        final existing = await txn.query(_table,
            where: 'idempotency_key = ?', whereArgs: [input.idempotencyKey], limit: 1);
        if (existing.isNotEmpty) {
          return DeliveryCreateResult(DeliveryRecord.fromMap(existing.first), created: false);
        }
        final now = nowIso();
        final id = await txn.insert(_table, {
          'campaign_id': input.campaignId,
          'destination_id': input.destinationId,
          'template_id': input.templateId,
          'idempotency_key': input.idempotencyKey,
          'status': DeliveryStatus.pending.dbValue,
          'created_at': now,
          'updated_at': now,
        });
        final rows = await txn.query(_table, where: 'id = ?', whereArgs: [id]);
        return DeliveryCreateResult(DeliveryRecord.fromMap(rows.single), created: true);
      }));

  @override
  Future<DeliveryRecord?> getById(int id) => guardDb(() async {
        final rows = await _db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
        return rows.isEmpty ? null : DeliveryRecord.fromMap(rows.first);
      });

  @override
  Future<DeliveryRecord?> getByKey(String idempotencyKey) => guardDb(() async {
        final rows = await _db.query(_table,
            where: 'idempotency_key = ?', whereArgs: [idempotencyKey], limit: 1);
        return rows.isEmpty ? null : DeliveryRecord.fromMap(rows.first);
      });

  @override
  Future<List<DeliveryRecord>> listForCampaign(int campaignId, {DeliveryStatus? status}) =>
      guardDb(() async {
        final rows = await _db.query(
          _table,
          where: status == null ? 'campaign_id = ?' : 'campaign_id = ? AND status = ?',
          whereArgs: status == null ? [campaignId] : [campaignId, status.dbValue],
          orderBy: 'id ASC',
        );
        return rows.map(DeliveryRecord.fromMap).toList();
      });

  Future<DeliveryRecord> _transition(
    int id,
    DeliveryStatus to,
    Map<String, Object?> extra, {
    bool incrementAttempt = false,
  }) =>
      guardDb(() => _db.transaction((txn) async {
            final rows = await txn.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
            if (rows.isEmpty) throw const NotFoundException('Delivery record not found.');
            final current = DeliveryRecord.fromMap(rows.first);
            if (!canTransition(current.status, to)) {
              throw const ValidationException(
                ErrorCodes.invalidDeliveryTransition,
                'Delivery status change is not allowed.',
              );
            }
            await txn.update(
              _table,
              {
                'status': to.dbValue,
                'updated_at': nowIso(),
                if (incrementAttempt) 'attempt_count': current.attemptCount + 1,
                ...extra,
              },
              where: 'id = ?',
              whereArgs: [id],
            );
            final out = await txn.query(_table, where: 'id = ?', whereArgs: [id]);
            return DeliveryRecord.fromMap(out.single);
          }));

  @override
  Future<DeliveryRecord> markSending(int id) =>
      _transition(id, DeliveryStatus.sending, const {}, incrementAttempt: true);

  @override
  Future<DeliveryRecord> markSent(int id, {String? platformMessageId}) => _transition(
        id,
        DeliveryStatus.sent,
        {'platform_message_id': platformMessageId, 'error_code': null, 'error_message': null},
      );

  @override
  Future<DeliveryRecord> markDelivered(int id) =>
      _transition(id, DeliveryStatus.delivered, {'delivered_at': nowIso()});

  @override
  Future<DeliveryRecord> markFailed(int id, {required String errorCode, String? errorMessage}) =>
      _transition(id, DeliveryStatus.failed, {
        'error_code': errorCode,
        'error_message': _safeMessage(errorMessage),
      });

  @override
  Future<DeliveryRecord> markSkipped(int id, {String? reason}) =>
      _transition(id, DeliveryStatus.skipped, {'error_message': _safeMessage(reason)});

  @override
  Future<DeliveryRecord> releaseToPending(int id) => _transition(id, DeliveryStatus.pending, const {});

  @override
  Future<DeliveryRecord> requeueFailed(int id) => _transition(id, DeliveryStatus.pending, const {});

  @override
  Future<int> recoverInterrupted() => guardDb(() => _db.update(
        _table,
        {'status': DeliveryStatus.pending.dbValue, 'updated_at': nowIso()},
        where: 'status = ?',
        whereArgs: [DeliveryStatus.sending.dbValue],
      ));

  @override
  Future<Map<DeliveryStatus, int>> countsByStatus({int? campaignId}) => guardDb(() async {
        final rows = await _db.rawQuery(
          'SELECT status, COUNT(*) AS c FROM delivery_records'
          '${campaignId == null ? '' : ' WHERE campaign_id = ?'} GROUP BY status',
          campaignId == null ? null : [campaignId],
        );
        final result = {for (final s in DeliveryStatus.values) s: 0};
        for (final r in rows) {
          result[enumFromDb(DeliveryStatus.values, r['status'])] = r['c']! as int;
        }
        return result;
      });
}

import 'package:sqflite/sqflite.dart';

import '../../../core/database/db_guard.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utilities/time.dart';
import '../../../shared/enums/enums.dart';
import '../../../shared/models/campaign.dart';

abstract class CampaignRepository {
  Future<List<Campaign>> list({CampaignStatus? status, int? accountId});
  Future<Campaign?> getById(int id);
  Future<Campaign> create(CampaignInput input);

  /// Only `draft` campaigns may be edited.
  Future<Campaign> updateDraft(int id, CampaignInput input);

  /// Applies a lifecycle change if [canTransition] allows it. Sets `started_at`
  /// on first start and `completed_at` on any terminal status.
  Future<Campaign> transition(int id, CampaignStatus to);

  /// Only `draft` campaigns may be deleted; other history is preserved.
  Future<void> delete(int id);
  Future<Map<CampaignStatus, int>> countsByStatus();

  Future<List<CampaignDestination>> listDestinations(int campaignId);
  Future<CampaignDestination> addDestination(
    int campaignId,
    int destinationId, {
    ConsentStatus consent = ConsentStatus.pending,
    AuthorizationStatus authorization = AuthorizationStatus.unknown,
  });

  /// Allowed in any campaign status so consent can always be revoked.
  Future<void> setDestinationConsent(int campaignId, int destinationId, ConsentStatus status);
  Future<void> setDestinationAuthorization(
      int campaignId, int destinationId, AuthorizationStatus status);

  /// Only while the campaign is `draft`.
  Future<void> removeDestination(int campaignId, int destinationId);
}

class SqliteCampaignRepository implements CampaignRepository {
  SqliteCampaignRepository(this._db);

  final Database _db;
  static const _table = 'campaigns';

  static const Map<CampaignStatus, Set<CampaignStatus>> _allowed = {
    CampaignStatus.draft: {CampaignStatus.scheduled, CampaignStatus.running, CampaignStatus.cancelled},
    CampaignStatus.scheduled: {CampaignStatus.draft, CampaignStatus.running, CampaignStatus.cancelled},
    CampaignStatus.running: {
      CampaignStatus.paused,
      CampaignStatus.completed,
      CampaignStatus.cancelled,
      CampaignStatus.failed,
    },
    CampaignStatus.paused: {CampaignStatus.running, CampaignStatus.cancelled, CampaignStatus.failed},
    CampaignStatus.completed: <CampaignStatus>{},
    CampaignStatus.cancelled: <CampaignStatus>{},
    CampaignStatus.failed: <CampaignStatus>{},
  };

  static bool canTransition(CampaignStatus from, CampaignStatus to) =>
      _allowed[from]?.contains(to) ?? false;

  static bool isTerminal(CampaignStatus s) => (_allowed[s] ?? const {}).isEmpty;

  void _validate(CampaignInput input) {
    if (input.name.trim().isEmpty) {
      throw const ValidationException(
          ErrorCodes.campaignNameRequired, 'Campaign name must not be empty.');
    }
    final s = input.scheduleStart;
    final e = input.scheduleEnd;
    if (s != null && e != null && e.isBefore(s)) {
      throw const ValidationException(
          ErrorCodes.campaignScheduleInvalid, 'Schedule end must not be before start.');
    }
    if (input.sendIntervalSeconds < 1 ||
        input.rounds < 1 ||
        input.rounds > 5 ||
        (input.maxDeliveries != null && input.maxDeliveries! < 1)) {
      throw const ValidationException(
          ErrorCodes.campaignOptionsInvalid, 'Interval, rounds or delivery limit is invalid.');
    }
  }

  String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

  @override
  Future<List<Campaign>> list({CampaignStatus? status, int? accountId}) => guardDb(() async {
        final where = <String>[];
        final args = <Object?>[];
        if (status != null) {
          where.add('status = ?');
          args.add(status.dbValue);
        }
        if (accountId != null) {
          where.add('account_id = ?');
          args.add(accountId);
        }
        final rows = await _db.query(
          _table,
          where: where.isEmpty ? null : where.join(' AND '),
          whereArgs: args.isEmpty ? null : args,
          orderBy: 'created_at DESC, id DESC',
        );
        return rows.map(Campaign.fromMap).toList();
      });

  @override
  Future<Campaign?> getById(int id) => guardDb(() async {
        final rows = await _db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
        return rows.isEmpty ? null : Campaign.fromMap(rows.first);
      });

  @override
  Future<Campaign> create(CampaignInput input) async {
    _validate(input);
    return guardDb(() async {
      final now = nowIso();
      final id = await _db.insert(_table, {
        'name': input.name.trim(),
        'account_id': input.accountId,
        'template_id': input.templateId,
        'status': CampaignStatus.draft.dbValue,
        'schedule_start': _iso(input.scheduleStart),
        'schedule_end': _iso(input.scheduleEnd),
        'timezone': input.timezone,
        'send_interval_seconds': input.sendIntervalSeconds,
        'rounds': input.rounds,
        'max_deliveries': input.maxDeliveries,
        'created_at': now,
        'updated_at': now,
      });
      final rows = await _db.query(_table, where: 'id = ?', whereArgs: [id]);
      return Campaign.fromMap(rows.single);
    });
  }

  @override
  Future<Campaign> updateDraft(int id, CampaignInput input) async {
    _validate(input);
    return guardDb(() => _db.transaction((txn) async {
          final rows = await txn.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
          if (rows.isEmpty) throw const NotFoundException('Campaign not found.');
          if (Campaign.fromMap(rows.first).status != CampaignStatus.draft) {
            throw const ValidationException(
                ErrorCodes.campaignNotEditable, 'Only draft campaigns can be edited.');
          }
          await txn.update(
            _table,
            {
              'name': input.name.trim(),
              'account_id': input.accountId,
              'template_id': input.templateId,
              'schedule_start': _iso(input.scheduleStart),
              'schedule_end': _iso(input.scheduleEnd),
              'timezone': input.timezone,
              'send_interval_seconds': input.sendIntervalSeconds,
              'rounds': input.rounds,
              'max_deliveries': input.maxDeliveries,
              'updated_at': nowIso(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          final out = await txn.query(_table, where: 'id = ?', whereArgs: [id]);
          return Campaign.fromMap(out.single);
        }));
  }

  @override
  Future<Campaign> transition(int id, CampaignStatus to) => guardDb(() => _db.transaction((txn) async {
        final rows = await txn.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) throw const NotFoundException('Campaign not found.');
        final current = Campaign.fromMap(rows.first);
        if (!canTransition(current.status, to)) {
          throw const ValidationException(
            ErrorCodes.invalidCampaignTransition,
            'Campaign status change is not allowed.',
          );
        }
        final now = nowIso();
        await txn.update(
          _table,
          {
            'status': to.dbValue,
            'updated_at': now,
            if (to == CampaignStatus.running && current.startedAt == null) 'started_at': now,
            if (isTerminal(to)) 'completed_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        final out = await txn.query(_table, where: 'id = ?', whereArgs: [id]);
        return Campaign.fromMap(out.single);
      }));

  @override
  Future<void> delete(int id) => guardDb(() => _db.transaction((txn) async {
        final rows = await txn.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) throw const NotFoundException('Campaign not found.');
        if (Campaign.fromMap(rows.first).status != CampaignStatus.draft) {
          throw const ValidationException(
              ErrorCodes.campaignNotEditable, 'Only draft campaigns can be deleted.');
        }
        await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
      }));

  @override
  Future<Map<CampaignStatus, int>> countsByStatus() => guardDb(() async {
        final rows = await _db.rawQuery('SELECT status, COUNT(*) AS c FROM campaigns GROUP BY status');
        final result = {for (final s in CampaignStatus.values) s: 0};
        for (final r in rows) {
          result[enumFromDb(CampaignStatus.values, r['status'])] = r['c']! as int;
        }
        return result;
      });

  static const _destSelect = '''
SELECT cd.id, cd.campaign_id, cd.destination_id, cd.consent_status, cd.authorization_status,
       d.display_name AS destination_name, d.platform_destination_id AS platform_destination_id
FROM campaign_destinations cd
JOIN destinations d ON d.id = cd.destination_id''';

  @override
  Future<List<CampaignDestination>> listDestinations(int campaignId) => guardDb(() async {
        final rows = await _db.rawQuery('$_destSelect WHERE cd.campaign_id = ? ORDER BY cd.id ASC', [campaignId]);
        return rows.map(CampaignDestination.fromMap).toList();
      });

  @override
  Future<CampaignDestination> addDestination(
    int campaignId,
    int destinationId, {
    ConsentStatus consent = ConsentStatus.pending,
    AuthorizationStatus authorization = AuthorizationStatus.unknown,
  }) =>
      guardDb(() async {
        final id = await _db.insert('campaign_destinations', {
          'campaign_id': campaignId,
          'destination_id': destinationId,
          'consent_status': consent.dbValue,
          'authorization_status': authorization.dbValue,
        });
        final rows = await _db.rawQuery('$_destSelect WHERE cd.id = ?', [id]);
        return CampaignDestination.fromMap(rows.single);
      });

  Future<void> _updateDestination(int campaignId, int destinationId, Map<String, Object?> values) async {
    final n = await _db.update('campaign_destinations', values,
        where: 'campaign_id = ? AND destination_id = ?', whereArgs: [campaignId, destinationId]);
    if (n == 0) throw const NotFoundException('Campaign destination not found.');
  }

  @override
  Future<void> setDestinationConsent(int campaignId, int destinationId, ConsentStatus status) =>
      guardDb(() => _updateDestination(campaignId, destinationId, {'consent_status': status.dbValue}));

  @override
  Future<void> setDestinationAuthorization(
          int campaignId, int destinationId, AuthorizationStatus status) =>
      guardDb(() =>
          _updateDestination(campaignId, destinationId, {'authorization_status': status.dbValue}));

  @override
  Future<void> removeDestination(int campaignId, int destinationId) => guardDb(() => _db.transaction((txn) async {
        final rows = await txn.query(_table, where: 'id = ?', whereArgs: [campaignId], limit: 1);
        if (rows.isEmpty) throw const NotFoundException('Campaign not found.');
        if (Campaign.fromMap(rows.first).status != CampaignStatus.draft) {
          throw const ValidationException(
              ErrorCodes.campaignNotEditable, 'Destinations can only be removed from draft campaigns.');
        }
        await txn.delete('campaign_destinations',
            where: 'campaign_id = ? AND destination_id = ?', whereArgs: [campaignId, destinationId]);
      }));
}

import 'package:sqflite/sqflite.dart';

import '../../../core/database/db_guard.dart';
import '../../../core/utilities/time.dart';
import '../../../shared/enums/enums.dart';
import '../../../shared/models/activity_event.dart';

abstract class ActivityRepository {
  Future<int> log(ActivityEventInput input);
  Future<List<ActivityEvent>> recent({int limit = 50});
  Future<int> count();
}

class SqliteActivityRepository implements ActivityRepository {
  SqliteActivityRepository(this._db);

  final Database _db;
  static const _table = 'activity_events';

  @override
  Future<int> log(ActivityEventInput input) => guardDb(() => _db.insert(_table, {
        'event_type': input.eventType,
        'account_id': input.accountId,
        'campaign_id': input.campaignId,
        'description': input.description,
        'severity': input.severity.dbValue,
        'metadata_json': input.metadataJson,
        'created_at': nowIso(),
      }));

  @override
  Future<List<ActivityEvent>> recent({int limit = 50}) => guardDb(() async {
        final rows = await _db.query(_table, orderBy: 'created_at DESC, id DESC', limit: limit);
        return rows.map(ActivityEvent.fromMap).toList();
      });

  @override
  Future<int> count() => guardDb(() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM activity_events')) ?? 0);
}

import 'package:sqflite/sqflite.dart';

import '../../../core/database/db_guard.dart';
import '../../../core/utilities/time.dart';

abstract class SettingsRepository {
  Future<Map<String, String>> getAll();
  Future<void> setValues(Map<String, String> values);
  Future<void> remove(String key);
}

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this._db);

  final Database _db;
  static const _table = 'application_settings';

  @override
  Future<Map<String, String>> getAll() => guardDb(() async {
        final rows = await _db.query(_table);
        return {for (final r in rows) r['key']! as String: r['value']! as String};
      });

  @override
  Future<void> setValues(Map<String, String> values) => guardDb(() => _db.transaction((txn) async {
        final now = nowIso();
        for (final e in values.entries) {
          await txn.insert(
            _table,
            {'key': e.key, 'value': e.value, 'updated_at': now},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }));

  @override
  Future<void> remove(String key) =>
      guardDb(() => _db.delete(_table, where: 'key = ?', whereArgs: [key]));
}

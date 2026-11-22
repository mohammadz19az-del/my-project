import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tesla_org/core/database/app_database.dart';
import 'package:tesla_org/core/database/migrations.dart';
import 'package:tesla_org/features/accounts/data/account_repository.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('tesla_migration'));
  tearDown(() async => dir.delete(recursive: true));

  test('a v1 database upgrades to the latest schema without losing data', () async {
    final path = p.join(dir.path, 'v1.db');
    final v1 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          for (final sql in statementsBetween(0, 1)) {
            await db.execute(sql);
          }
        },
      ),
    );
    await v1.insert('accounts', {'platform': 'telegram', 'account_identifier': 'keep-me'});
    await v1.close();

    final upgraded = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
    expect(await upgraded.schemaVersion(), latestSchemaVersion);
    final accounts = await SqliteAccountRepository(upgraded.db).list();
    expect(accounts.single.accountIdentifier, 'keep-me');
    final triggers = await upgraded.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger' AND name='trg_campaigns_audit_status'");
    expect(triggers.length, 1);
    final cols = await upgraded.db.rawQuery('PRAGMA table_info(campaigns)');
    expect(cols.map((c) => c['name']), containsAll(['send_interval_seconds', 'rounds', 'max_deliveries']));
    await upgraded.close();
  });

  test('a database newer than the app is refused and left untouched', () async {
    final path = p.join(dir.path, 'future.db');
    final future = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: latestSchemaVersion + 5,
        onCreate: (db, v) => db.execute('CREATE TABLE marker (id INTEGER)'),
      ),
    );
    await future.close();

    await expectLater(
      AppDatabase.open(path: path, factory: databaseFactoryFfi),
      throwsA(anything),
    );
    final check = await databaseFactoryFfi.openDatabase(path);
    final tables = await check.rawQuery("SELECT name FROM sqlite_master WHERE name='marker'");
    expect(tables.length, 1);
    await check.close();
  });
}

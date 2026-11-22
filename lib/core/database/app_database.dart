import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../constants/app_constants.dart';
import 'migrations.dart';

bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Selects the SQLite backend: FFI on desktop (Windows), native sqflite on Android.
void initDatabaseFactory() {
  if (_isDesktop) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

/// Wraps the open sqflite [Database] and owns schema creation/migration.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static Future<String> defaultPath() async {
    if (_isDesktop) {
      final dir = await getApplicationSupportDirectory();
      final folder = Directory(p.join(dir.path, 'databases'));
      await folder.create(recursive: true);
      return p.join(folder.path, AppConstants.databaseName);
    }
    return p.join(await getDatabasesPath(), AppConstants.databaseName);
  }

  /// Opens (creating/migrating as needed) the database at [path].
  /// Pass [factory] and `inMemoryDatabasePath` for tests.
  static Future<AppDatabase> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final resolved = path ?? await defaultPath();
    final db = await f.openDatabase(
      resolved,
      options: OpenDatabaseOptions(
        version: latestSchemaVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onDowngrade: _onDowngrade,
      ),
    );
    return AppDatabase._(db);
  }

  Future<int> schemaVersion() async {
    final rows = await db.rawQuery('PRAGMA user_version');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<void> close() => db.close();

  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _onCreate(Database db, int version) async {
    for (final sql in statementsBetween(0, version)) {
      await db.execute(sql);
    }
  }

  static Future<void> _onUpgrade(Database db, int from, int to) async {
    for (final sql in statementsBetween(from, to)) {
      await db.execute(sql);
    }
  }

  /// Opening a newer database with an older app must never alter or drop data.
  static Future<void> _onDowngrade(Database db, int from, int to) async {
    throw StateError(
      'Database schema v$from is newer than this app supports (v$to). '
      'Update Tesla.org; the data file was left untouched.',
    );
  }
}

@visibleForTesting
bool get isDesktopPlatform => _isDesktop;

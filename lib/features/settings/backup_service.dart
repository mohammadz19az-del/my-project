import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../app/providers.dart';
import '../../core/database/db_guard.dart';
import '../../core/database/migrations.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/security/credential_store.dart';
import '../../core/storage/app_files.dart';
import '../../core/utilities/time.dart';
import '../accounts/application/account_providers.dart';

/// Backup / restore / wipe of all local data.
///
/// * Backups are plain JSON files and NEVER contain credentials (the secure
///   store is not read, and `credential_reference` is blanked). After a restore
///   the user re-enters tokens, and accounts show "Authentication required".
/// * Restore validates structure, schema version and column names, takes a
///   safety backup first, and runs in one transaction (all or nothing).
class BackupService {
  BackupService({required Database db, required CredentialStore store, required AppFiles files})
      : _db = db,
        _store = store,
        _files = files;

  final Database _db;
  final CredentialStore _store;
  final AppFiles _files;

  static const String format = 'tesla_org_backup';

  static const List<String> _tables = [
    'accounts',
    'message_templates',
    'group_links',
    'destinations',
    'campaigns',
    'campaign_destinations',
    'delivery_records',
    'application_settings',
    'activity_events',
  ];

  /// Children first (foreign keys are RESTRICT for campaign history).
  static const List<String> _wipeOrder = [
    'delivery_records',
    'campaign_destinations',
    'campaigns',
    'destinations',
    'group_links',
    'message_templates',
    'accounts',
    'application_settings',
    'activity_events',
  ];

  static const List<String> _insertOrder = [
    'accounts',
    'message_templates',
    'group_links',
    'destinations',
    'campaigns',
    'campaign_destinations',
    'delivery_records',
    'application_settings',
  ];

  Future<String> createBackupJson() => guardDb(() async {
        final data = <String, Object?>{};
        for (final t in _tables) {
          final rows = await _db.query(t);
          data[t] = [
            for (final r in rows)
              {
                ...r,
                if (t == 'accounts') 'credential_reference': null,
              },
          ];
        }
        return const JsonEncoder.withIndent(' ').convert({
          'format': format,
          'schemaVersion': latestSchemaVersion,
          'createdAt': nowIso(),
          'secretsIncluded': false,
          'tables': data,
        });
      });

  String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }

  Future<File> writeBackup({String prefix = 'tesla_backup'}) async =>
      _files.write('backups', '${prefix}_${_stamp()}.json', await createBackupJson());

  Future<List<File>> listBackups() => _files.list('backups');

  Future<String> readBackup(File f) => _files.read(f);

  Future<Set<String>> _columns(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return {for (final r in rows) r['name']! as String};
  }

  ValidationException _invalid(String why) => ValidationException(ErrorCodes.backupInvalid, 'Invalid backup: $why');

  /// Parses and validates without touching the database.
  Future<Map<String, List<Map<String, Object?>>>> validate(String text) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw _invalid('not valid JSON');
    }
    if (decoded is! Map || decoded['format'] != format) throw _invalid('wrong format');
    final version = decoded['schemaVersion'];
    if (version is! int || version < 1 || version > latestSchemaVersion) {
      throw _invalid('unsupported schema version');
    }
    final tables = decoded['tables'];
    if (tables is! Map) throw _invalid('missing tables');
    final result = <String, List<Map<String, Object?>>>{};
    for (final t in _tables) {
      final raw = tables[t];
      if (raw is! List) throw _invalid('missing table $t');
      final columns = await _columns(_db, t);
      final rows = <Map<String, Object?>>[];
      for (final r in raw) {
        if (r is! Map) throw _invalid('bad row in $t');
        final row = <String, Object?>{};
        for (final e in r.entries) {
          if (e.key is! String || !columns.contains(e.key)) throw _invalid('unknown column in $t');
          final v = e.value;
          if (v != null && v is! num && v is! String) throw _invalid('bad value in $t');
          row[e.key as String] = v;
        }
        if (t == 'accounts') row['credential_reference'] = null; // never trust references
        rows.add(row);
      }
      result[t] = rows;
    }
    return result;
  }

  /// Returns restored row counts per table.
  Future<Map<String, int>> restoreFromJson(String text) async {
    final data = await validate(text);
    await writeBackup(prefix: 'tesla_prerestore'); // safety copy of the current data

    final oldRefs = await _credentialReferences();
    final counts = <String, int>{};
    await guardDb(() => _db.transaction((txn) async {
          for (final t in _wipeOrder) {
            await txn.delete(t);
          }
          for (final t in _insertOrder) {
            for (final row in data[t]!) {
              await txn.insert(t, row, conflictAlgorithm: ConflictAlgorithm.replace);
            }
            counts[t] = data[t]!.length;
          }
          // Audit triggers wrote new events while restoring; replace with the backed-up history.
          await txn.delete('activity_events');
          for (final row in data['activity_events']!) {
            await txn.insert('activity_events', row);
          }
          counts['activity_events'] = data['activity_events']!.length;
        }));
    await _deleteSecrets(oldRefs);
    return counts;
  }

  /// Deletes every local record and stored secret. Irreversible.
  Future<void> wipeAll() async {
    final refs = await _credentialReferences();
    await guardDb(() => _db.transaction((txn) async {
          for (final t in _wipeOrder) {
            await txn.delete(t);
          }
        }));
    await _deleteSecrets(refs);
  }

  Future<List<String>> _credentialReferences() async {
    final rows = await _db.rawQuery('SELECT credential_reference AS r FROM accounts WHERE credential_reference IS NOT NULL');
    return [for (final r in rows) r['r']! as String];
  }

  Future<void> _deleteSecrets(List<String> refs) async {
    for (final r in refs) {
      try {
        await _store.delete(r);
      } catch (_) {
        AppLogger.warning('Could not remove a stored credential entry');
      }
    }
  }
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    db: ref.watch(appDatabaseProvider).db,
    store: ref.watch(credentialStoreProvider),
    files: ref.watch(appFilesProvider),
  ),
);

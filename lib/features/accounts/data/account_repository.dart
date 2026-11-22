import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/db_guard.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utilities/time.dart';
import '../../../shared/enums/enums.dart';
import '../../../shared/models/account.dart';

abstract class AccountRepository {
  Future<List<Account>> list({MessagingPlatform? platform});
  Future<Account?> getById(int id);

  /// Throws [LimitExceededException] when the platform already has 10 accounts
  /// and [DuplicateRecordException] for an existing (platform, identifier).
  Future<Account> create(AccountInput input);

  /// Fields left null are unchanged. An empty [displayName] clears the name.
  Future<Account> updateDetails(int id, {String? accountIdentifier, String? displayName});

  Future<void> updateConnectionStatus(int id, ConnectionStatus status);

  /// Links the account to its secure-storage entry (a key, never a secret).
  Future<void> setCredentialReference(int id, String? reference);
  Future<void> touchActivity(int id);
  Future<void> delete(int id);
  Future<Map<MessagingPlatform, int>> countByPlatform();
}

class SqliteAccountRepository implements AccountRepository {
  SqliteAccountRepository(this._db);

  final Database _db;
  static const _table = 'accounts';

  @override
  Future<List<Account>> list({MessagingPlatform? platform}) => guardDb(() async {
        final rows = await _db.query(
          _table,
          where: platform == null ? null : 'platform = ?',
          whereArgs: platform == null ? null : [platform.dbValue],
          orderBy: 'platform ASC, created_at ASC, id ASC',
        );
        return rows.map(Account.fromMap).toList();
      });

  @override
  Future<Account?> getById(int id) => guardDb(() async {
        final rows = await _db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
        return rows.isEmpty ? null : Account.fromMap(rows.first);
      });

  @override
  Future<Account> create(AccountInput input) async {
    final identifier = input.accountIdentifier.trim();
    if (identifier.isEmpty) {
      throw const ValidationException(
        ErrorCodes.accountIdentifierRequired,
        'Account identifier must not be empty.',
      );
    }
    final name = input.displayName?.trim();
    return guardDb(() => _db.transaction((txn) async {
          final count = Sqflite.firstIntValue(await txn.rawQuery(
                'SELECT COUNT(*) FROM accounts WHERE platform = ?',
                [input.platform.dbValue],
              )) ??
              0;
          if (count >= AppConstants.maxAccountsPerPlatform) {
            throw const LimitExceededException(
              ErrorCodes.limitAccountsPerPlatform,
              'Account limit per platform reached.',
            );
          }
          final now = nowIso();
          final id = await txn.insert(_table, {
            'platform': input.platform.dbValue,
            'account_identifier': identifier,
            'display_name': (name == null || name.isEmpty) ? null : name,
            'credential_reference': input.credentialReference,
            'created_at': now,
            'updated_at': now,
          });
          final rows = await txn.query(_table, where: 'id = ?', whereArgs: [id]);
          return Account.fromMap(rows.single);
        }));
  }

  @override
  Future<Account> updateDetails(int id, {String? accountIdentifier, String? displayName}) async {
    final values = <String, Object?>{};
    if (accountIdentifier != null) {
      final trimmed = accountIdentifier.trim();
      if (trimmed.isEmpty) {
        throw const ValidationException(
          ErrorCodes.accountIdentifierRequired,
          'Account identifier must not be empty.',
        );
      }
      values['account_identifier'] = trimmed;
    }
    if (displayName != null) {
      final trimmed = displayName.trim();
      values['display_name'] = trimmed.isEmpty ? null : trimmed;
    }
    return guardDb(() async {
      if (values.isNotEmpty) {
        values['updated_at'] = nowIso();
        final n = await _db.update(_table, values, where: 'id = ?', whereArgs: [id]);
        if (n == 0) throw const NotFoundException('Account not found.');
      }
      final account = await getById(id);
      if (account == null) throw const NotFoundException('Account not found.');
      return account;
    });
  }

  @override
  Future<void> updateConnectionStatus(int id, ConnectionStatus status) => guardDb(() async {
        final now = nowIso();
        final n = await _db.update(
          _table,
          {
            'connection_status': status.dbValue,
            'updated_at': now,
            // Only a REAL connection counts as "last successful connection";
            // mock connections are deliberately excluded.
            if (status == ConnectionStatus.connected) 'last_connected_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        if (n == 0) throw const NotFoundException('Account not found.');
      });

  @override
  Future<void> setCredentialReference(int id, String? reference) => guardDb(() async {
        final n = await _db.update(
          _table,
          {'credential_reference': reference, 'updated_at': nowIso()},
          where: 'id = ?',
          whereArgs: [id],
        );
        if (n == 0) throw const NotFoundException('Account not found.');
      });

  @override
  Future<void> touchActivity(int id) => guardDb(() async {
        final now = nowIso();
        await _db.update(_table, {'last_activity_at': now, 'updated_at': now},
            where: 'id = ?', whereArgs: [id]);
      });

  @override
  Future<void> delete(int id) => guardDb(() async {
        final n = await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
        if (n == 0) throw const NotFoundException('Account not found.');
      });

  @override
  Future<Map<MessagingPlatform, int>> countByPlatform() => guardDb(() async {
        final rows = await _db.rawQuery(
          'SELECT platform, COUNT(*) AS c FROM accounts GROUP BY platform',
        );
        final result = {for (final p in MessagingPlatform.values) p: 0};
        for (final r in rows) {
          final platform = enumFromDb(MessagingPlatform.values, r['platform']);
          result[platform] = r['c']! as int;
        }
        return result;
      });
}

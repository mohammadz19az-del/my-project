import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/db_guard.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utilities/link_validator.dart';
import '../../../core/utilities/time.dart';
import '../../../shared/enums/enums.dart';
import '../../../shared/models/group_link.dart';

abstract class GroupLinkRepository {
  Future<List<GroupLink>> listForAccount(int accountId);
  Future<List<GroupLink>> listAll({MessagingPlatform? platform});
  Future<GroupLink?> getById(int id);

  /// The platform is taken from the owning account. The stored status is the
  /// offline *format* classification only; it is never `verified` on creation.
  /// Throws [LimitExceededException] at 20 links per account.
  Future<GroupLink> create(GroupLinkInput input);

  /// Changing the URL re-classifies the format and clears any prior verification.
  Future<GroupLink> update(int id, {required String url, String? title, String? description});

  /// For authorized verification flows only. [verifiedAt] defaults to now when
  /// the status is `verified`.
  Future<void> updateValidation(int id, ValidationStatus status, {DateTime? verifiedAt});
  Future<void> delete(int id);
  Future<int> countForAccount(int accountId);
}

class SqliteGroupLinkRepository implements GroupLinkRepository {
  SqliteGroupLinkRepository(this._db);

  final Database _db;
  static const _table = 'group_links';

  String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  @override
  Future<List<GroupLink>> listForAccount(int accountId) => guardDb(() async {
        final rows = await _db.query(_table,
            where: 'account_id = ?', whereArgs: [accountId], orderBy: 'created_at ASC, id ASC');
        return rows.map(GroupLink.fromMap).toList();
      });

  @override
  Future<List<GroupLink>> listAll({MessagingPlatform? platform}) => guardDb(() async {
        final rows = await _db.query(
          _table,
          where: platform == null ? null : 'platform = ?',
          whereArgs: platform == null ? null : [platform.dbValue],
          orderBy: 'platform ASC, created_at ASC, id ASC',
        );
        return rows.map(GroupLink.fromMap).toList();
      });

  @override
  Future<GroupLink?> getById(int id) => guardDb(() async {
        final rows = await _db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
        return rows.isEmpty ? null : GroupLink.fromMap(rows.first);
      });

  @override
  Future<GroupLink> create(GroupLinkInput input) async {
    final url = input.url.trim();
    if (url.isEmpty) {
      throw const ValidationException(
          ErrorCodes.groupLinkUrlRequired, 'Group link URL must not be empty.');
    }
    return guardDb(() => _db.transaction((txn) async {
          final acc = await txn.query('accounts',
              columns: ['platform'], where: 'id = ?', whereArgs: [input.accountId], limit: 1);
          if (acc.isEmpty) throw const NotFoundException('Account not found.');
          final platform = enumFromDb(MessagingPlatform.values, acc.first['platform']);

          final count = Sqflite.firstIntValue(await txn.rawQuery(
                  'SELECT COUNT(*) FROM group_links WHERE account_id = ?', [input.accountId])) ??
              0;
          if (count >= AppConstants.maxGroupLinksPerAccount) {
            throw const LimitExceededException(
              ErrorCodes.limitGroupLinksPerAccount,
              'Group link limit per account reached.',
            );
          }
          final now = nowIso();
          final id = await txn.insert(_table, {
            'account_id': input.accountId,
            'platform': platform.dbValue,
            'url': url,
            'title': _clean(input.title),
            'description': _clean(input.description),
            'validation_status': LinkValidator.checkFormat(platform, url).dbValue,
            'created_at': now,
            'updated_at': now,
          });
          final rows = await txn.query(_table, where: 'id = ?', whereArgs: [id]);
          return GroupLink.fromMap(rows.single);
        }));
  }

  @override
  Future<GroupLink> update(int id,
      {required String url, String? title, String? description}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException(
          ErrorCodes.groupLinkUrlRequired, 'Group link URL must not be empty.');
    }
    return guardDb(() => _db.transaction((txn) async {
          final rows = await txn.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
          if (rows.isEmpty) throw const NotFoundException('Group link not found.');
          final current = GroupLink.fromMap(rows.first);
          final changedUrl = current.url != trimmed;
          await txn.update(
            _table,
            {
              'url': trimmed,
              'title': _clean(title),
              'description': _clean(description),
              if (changedUrl) ...{
                'validation_status': LinkValidator.checkFormat(current.platform, trimmed).dbValue,
                'last_verified_at': null,
              },
              'updated_at': nowIso(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          final out = await txn.query(_table, where: 'id = ?', whereArgs: [id]);
          return GroupLink.fromMap(out.single);
        }));
  }

  @override
  Future<void> updateValidation(int id, ValidationStatus status, {DateTime? verifiedAt}) =>
      guardDb(() async {
        final stamp = verifiedAt ?? (status == ValidationStatus.verified ? DateTime.now() : null);
        final n = await _db.update(
          _table,
          {
            'validation_status': status.dbValue,
            if (stamp != null) 'last_verified_at': stamp.toUtc().toIso8601String(),
            'updated_at': nowIso(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        if (n == 0) throw const NotFoundException('Group link not found.');
      });

  @override
  Future<void> delete(int id) => guardDb(() async {
        final n = await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
        if (n == 0) throw const NotFoundException('Group link not found.');
      });

  @override
  Future<int> countForAccount(int accountId) => guardDb(() async =>
      Sqflite.firstIntValue(await _db
          .rawQuery('SELECT COUNT(*) FROM group_links WHERE account_id = ?', [accountId])) ??
      0);
}

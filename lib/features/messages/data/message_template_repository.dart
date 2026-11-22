import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/db_guard.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utilities/time.dart';
import '../../../shared/enums/enums.dart';
import '../../../shared/models/message_template.dart';

abstract class MessageTemplateRepository {
  Future<List<MessageTemplate>> listForAccount(int accountId);
  Future<MessageTemplate?> getById(int id);

  /// Throws [LimitExceededException] at 20 templates per account.
  Future<MessageTemplate> create(MessageTemplateInput input);
  Future<MessageTemplate> update(
    int id, {
    required String title,
    required String body,
    required MessageLanguage language,
    String? waTemplateName,
    String? waTemplateLanguage,
  });
  Future<void> setEnabled(int id, {required bool enabled});
  Future<void> delete(int id);
  Future<int> countForAccount(int accountId);
  Future<int> countAll();
}

class SqliteMessageTemplateRepository implements MessageTemplateRepository {
  SqliteMessageTemplateRepository(this._db);

  final Database _db;
  static const _table = 'message_templates';

  static String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  void _validate(String title, String body) {
    if (title.trim().isEmpty) {
      throw const ValidationException(
          ErrorCodes.templateTitleRequired, 'Template title must not be empty.');
    }
    if (body.trim().isEmpty) {
      throw const ValidationException(
          ErrorCodes.templateBodyRequired, 'Template body must not be empty.');
    }
  }

  @override
  Future<List<MessageTemplate>> listForAccount(int accountId) => guardDb(() async {
        final rows = await _db.query(_table,
            where: 'account_id = ?',
            whereArgs: [accountId],
            orderBy: 'created_at ASC, id ASC');
        return rows.map(MessageTemplate.fromMap).toList();
      });

  @override
  Future<MessageTemplate?> getById(int id) => guardDb(() async {
        final rows = await _db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
        return rows.isEmpty ? null : MessageTemplate.fromMap(rows.first);
      });

  @override
  Future<MessageTemplate> create(MessageTemplateInput input) async {
    _validate(input.title, input.body);
    return guardDb(() => _db.transaction((txn) async {
          final count = Sqflite.firstIntValue(await txn.rawQuery(
                'SELECT COUNT(*) FROM message_templates WHERE account_id = ?',
                [input.accountId],
              )) ??
              0;
          if (count >= AppConstants.maxTemplatesPerAccount) {
            throw const LimitExceededException(
              ErrorCodes.limitTemplatesPerAccount,
              'Message template limit per account reached.',
            );
          }
          final now = nowIso();
          final id = await txn.insert(_table, {
            'account_id': input.accountId,
            'title': input.title.trim(),
            'body': input.body, // exact content preserved
            'language': input.language.dbValue,
            'enabled': input.enabled ? 1 : 0,
            'wa_template_name': _clean(input.waTemplateName),
            'wa_template_language': _clean(input.waTemplateLanguage),
            'created_at': now,
            'updated_at': now,
          });
          final rows = await txn.query(_table, where: 'id = ?', whereArgs: [id]);
          return MessageTemplate.fromMap(rows.single);
        }));
  }

  @override
  Future<MessageTemplate> update(
    int id, {
    required String title,
    required String body,
    required MessageLanguage language,
    String? waTemplateName,
    String? waTemplateLanguage,
  }) async {
    _validate(title, body);
    return guardDb(() async {
      final n = await _db.update(
        _table,
        {
          'title': title.trim(),
          'body': body,
          'language': language.dbValue,
          'wa_template_name': _clean(waTemplateName),
          'wa_template_language': _clean(waTemplateLanguage),
          'updated_at': nowIso(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (n == 0) throw const NotFoundException('Template not found.');
      final t = await getById(id);
      if (t == null) throw const NotFoundException('Template not found.');
      return t;
    });
  }

  @override
  Future<void> setEnabled(int id, {required bool enabled}) => guardDb(() async {
        final n = await _db.update(
          _table,
          {'enabled': enabled ? 1 : 0, 'updated_at': nowIso()},
          where: 'id = ?',
          whereArgs: [id],
        );
        if (n == 0) throw const NotFoundException('Template not found.');
      });

  @override
  Future<void> delete(int id) => guardDb(() async {
        final n = await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
        if (n == 0) throw const NotFoundException('Template not found.');
      });

  @override
  Future<int> countForAccount(int accountId) => guardDb(() async =>
      Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT COUNT(*) FROM message_templates WHERE account_id = ?', [accountId])) ??
      0);

  @override
  Future<int> countAll() => guardDb(() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM message_templates')) ??
      0);
}

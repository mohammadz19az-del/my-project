import 'package:sqflite/sqflite.dart';

import '../../../core/database/db_guard.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utilities/time.dart';
import '../../../shared/enums/enums.dart';
import '../../../shared/models/destination.dart';

abstract class DestinationRepository {
  Future<List<Destination>> listForAccount(int accountId);
  Future<Destination?> getById(int id);
  Future<Destination> create(DestinationInput input);

  /// `authorized` must only be set from an authorized platform lookup or an
  /// explicit user attestation, never inferred.
  Future<Destination> setAuthorization(int id, AuthorizationStatus status);
  Future<void> delete(int id);
}

class SqliteDestinationRepository implements DestinationRepository {
  SqliteDestinationRepository(this._db);

  final Database _db;
  static const _table = 'destinations';

  @override
  Future<List<Destination>> listForAccount(int accountId) => guardDb(() async {
        final rows = await _db.query(_table,
            where: 'account_id = ?', whereArgs: [accountId], orderBy: 'created_at ASC, id ASC');
        return rows.map(Destination.fromMap).toList();
      });

  @override
  Future<Destination?> getById(int id) => guardDb(() async {
        final rows = await _db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
        return rows.isEmpty ? null : Destination.fromMap(rows.first);
      });

  @override
  Future<Destination> create(DestinationInput input) async {
    final destId = input.platformDestinationId.trim();
    if (destId.isEmpty) {
      throw const ValidationException(
          ErrorCodes.destinationIdRequired, 'Destination identifier must not be empty.');
    }
    final name = input.displayName?.trim();
    return guardDb(() async {
      final id = await _db.insert(_table, {
        'account_id': input.accountId,
        'platform_destination_id': destId,
        'display_name': (name == null || name.isEmpty) ? null : name,
        'destination_type': input.destinationType.dbValue,
        'authorization_status': input.authorizationStatus.dbValue,
        'created_at': nowIso(),
      });
      final rows = await _db.query(_table, where: 'id = ?', whereArgs: [id]);
      return Destination.fromMap(rows.single);
    });
  }

  @override
  Future<Destination> setAuthorization(int id, AuthorizationStatus status) => guardDb(() async {
        final n = await _db.update(_table, {'authorization_status': status.dbValue},
            where: 'id = ?', whereArgs: [id]);
        if (n == 0) throw const NotFoundException('Destination not found.');
        final rows = await _db.query(_table, where: 'id = ?', whereArgs: [id]);
        return Destination.fromMap(rows.single);
      });

  @override
  Future<void> delete(int id) => guardDb(() async {
        final n = await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
        if (n == 0) throw const NotFoundException('Destination not found.');
      });
}

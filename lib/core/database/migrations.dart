import 'database_schema.dart';
import 'database_schema_v2.dart';
import 'database_schema_v3.dart';

/// One forward-only schema migration. Statements run inside the open/upgrade
/// transaction, so a failed migration rolls back and leaves data untouched.
class Migration {
  const Migration({
    required this.version,
    required this.description,
    required this.statements,
  });

  final int version;
  final String description;
  final List<String> statements;
}

/// Ordered, contiguous migration history. Append only; never edit released ones.
final List<Migration> allMigrations = <Migration>[
  Migration(
    version: 1,
    description: 'Initial schema: tables, indexes, limit/integrity/audit triggers',
    statements: schemaV1Statements,
  ),
  Migration(
    version: 2,
    description: 'Campaign audit triggers and delivery destination index',
    statements: schemaV2Statements,
  ),
  Migration(
    version: 3,
    description: 'Campaign interval/rounds/limit and WhatsApp template columns',
    statements: schemaV3Statements,
  ),
];

int get latestSchemaVersion => allMigrations.last.version;

/// Statements needed to move a database from [from] (exclusive) to [to] (inclusive).
List<String> statementsBetween(int from, int to) {
  assert(() {
    for (var i = 0; i < allMigrations.length; i++) {
      if (allMigrations[i].version != i + 1) return false;
    }
    return true;
  }(), 'Migrations must be contiguous starting at version 1');
  return [
    for (final m in allMigrations)
      if (m.version > from && m.version <= to) ...m.statements,
  ];
}

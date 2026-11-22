import 'package:sqflite/sqflite.dart';

import '../errors/app_exception.dart';
import '../logging/app_logger.dart';

/// Runs a database action and converts low-level errors into [AppException]s.
Future<T> guardDb<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on AppException {
    rethrow;
  } on DatabaseException catch (e, s) {
    AppLogger.error('Database operation failed', error: e, stackTrace: s);
    throw mapDatabaseException(e);
  }
}

/// Maps trigger/constraint failures to typed exceptions with stable codes.
AppException mapDatabaseException(Object error) {
  final text = error.toString();

  const limits = {
    ErrorCodes.limitAccountsPerPlatform: 'Account limit per platform reached.',
    ErrorCodes.limitTemplatesPerAccount: 'Message template limit per account reached.',
    ErrorCodes.limitGroupLinksPerAccount: 'Group link limit per account reached.',
  };
  for (final e in limits.entries) {
    if (text.contains(e.key)) return LimitExceededException(e.key, e.value);
  }

  const rules = {
    ErrorCodes.groupPlatformMismatch: 'Group link platform must match its account platform.',
    ErrorCodes.campaignTemplateAccountMismatch:
        'Campaign template must belong to the campaign account.',
    ErrorCodes.campaignDestinationAccountMismatch:
        'Campaign destination must belong to the campaign account.',
    ErrorCodes.deliveryConsentRequired:
        'Delivery requires granted consent and an authorized destination.',
  };
  for (final e in rules.entries) {
    if (text.contains(e.key)) {
      return ConstraintViolationException(e.key, e.value, cause: error);
    }
  }

  if (text.contains('UNIQUE constraint failed')) {
    return DuplicateRecordException('A record with the same unique values already exists.',
        cause: error);
  }
  if (text.contains('FOREIGN KEY constraint failed')) {
    return ConstraintViolationException(
      ErrorCodes.foreignKey,
      'The operation conflicts with related records.',
      cause: error,
    );
  }
  if (text.contains('CHECK constraint failed')) {
    return ConstraintViolationException(
      ErrorCodes.checkConstraint,
      'A value violates a database rule.',
      cause: error,
    );
  }
  return DatabaseFailure('Unexpected database error.', cause: error);
}

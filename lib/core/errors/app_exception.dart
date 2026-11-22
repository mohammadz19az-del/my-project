/// Stable machine-readable error codes. The UI localizes `error_<code lowercase>`.
abstract final class ErrorCodes {
  static const limitAccountsPerPlatform = 'LIMIT_ACCOUNTS_PER_PLATFORM';
  static const limitTemplatesPerAccount = 'LIMIT_TEMPLATES_PER_ACCOUNT';
  static const limitGroupLinksPerAccount = 'LIMIT_GROUP_LINKS_PER_ACCOUNT';
  static const groupPlatformMismatch = 'GROUP_PLATFORM_MISMATCH';
  static const campaignTemplateAccountMismatch = 'CAMPAIGN_TEMPLATE_ACCOUNT_MISMATCH';
  static const campaignDestinationAccountMismatch = 'CAMPAIGN_DESTINATION_ACCOUNT_MISMATCH';
  static const deliveryConsentRequired = 'DELIVERY_CONSENT_REQUIRED';
  static const duplicateRecord = 'DUPLICATE_RECORD';
  static const foreignKey = 'FOREIGN_KEY';
  static const checkConstraint = 'CHECK_CONSTRAINT';
  static const notFound = 'NOT_FOUND';
  static const accountIdentifierRequired = 'ACCOUNT_IDENTIFIER_REQUIRED';
  static const templateTitleRequired = 'TEMPLATE_TITLE_REQUIRED';
  static const templateBodyRequired = 'TEMPLATE_BODY_REQUIRED';
  static const databaseFailure = 'DATABASE_FAILURE';
  static const credentialStorageFailure = 'CREDENTIAL_STORAGE_FAILURE';
  static const invalidAccountInput = 'INVALID_ACCOUNT_INPUT';
  static const campaignOptionsInvalid = 'CAMPAIGN_OPTIONS_INVALID';
  static const campaignNoDestinations = 'CAMPAIGN_NO_DESTINATIONS';
  static const templateDisabled = 'TEMPLATE_DISABLED';
  static const accountNotConnected = 'ACCOUNT_NOT_CONNECTED';
  static const intervalTooShort = 'INTERVAL_TOO_SHORT';
  static const templateTooLong = 'TEMPLATE_TOO_LONG';
  static const backupInvalid = 'BACKUP_INVALID';
  static const destinationInvalid = 'DESTINATION_INVALID';
  static const invalidCampaignTransition = 'INVALID_CAMPAIGN_TRANSITION';
  static const campaignNotEditable = 'CAMPAIGN_NOT_EDITABLE';
  static const campaignNameRequired = 'CAMPAIGN_NAME_REQUIRED';
  static const campaignScheduleInvalid = 'CAMPAIGN_SCHEDULE_INVALID';
  static const groupLinkUrlRequired = 'GROUP_LINK_URL_REQUIRED';
  static const destinationIdRequired = 'DESTINATION_ID_REQUIRED';
  static const invalidDeliveryTransition = 'INVALID_DELIVERY_TRANSITION';
}

/// Base type for every error the data/business layers intentionally raise.
/// Messages are developer-facing English; the UI shows a localized message
/// selected by [code]. Never put credentials or tokens in a message.
abstract class AppException implements Exception {
  const AppException(this.code, this.message, {this.cause});

  final String code;
  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType($code): $message';
}

class ValidationException extends AppException {
  const ValidationException(super.code, super.message);
}

class LimitExceededException extends AppException {
  const LimitExceededException(super.code, super.message);
}

class DuplicateRecordException extends AppException {
  const DuplicateRecordException(String message, {Object? cause})
      : super(ErrorCodes.duplicateRecord, message, cause: cause);
}

class NotFoundException extends AppException {
  const NotFoundException(String message) : super(ErrorCodes.notFound, message);
}

class ConstraintViolationException extends AppException {
  const ConstraintViolationException(super.code, super.message, {super.cause});
}

class DatabaseFailure extends AppException {
  const DatabaseFailure(String message, {Object? cause})
      : super(ErrorCodes.databaseFailure, message, cause: cause);
}

/// Secure storage could not be read or written. Never carries secret values.
class CredentialStorageFailure extends AppException {
  const CredentialStorageFailure(String message, {Object? cause})
      : super(ErrorCodes.credentialStorageFailure, message, cause: cause);
}

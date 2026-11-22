import '../../../shared/enums/enums.dart';

/// One secret input of an account form (e.g. a bot token).
class SecretField {
  const SecretField({required this.key, required this.labelKey, required this.hintKey});

  final String key;
  final String labelKey;
  final String hintKey;
}

/// What an account of a platform needs. Drives the form, validation and storage.
class PlatformAccountSpec {
  const PlatformAccountSpec({
    required this.platform,
    required this.identifierLabelKey,
    required this.identifierHintKey,
    this.secrets = const [],
  });

  final MessagingPlatform platform;
  final String identifierLabelKey;
  final String identifierHintKey;
  final List<SecretField> secrets;

  bool get requiresCredentials => secrets.isNotEmpty;
  String get noteKey => 'platform_note_${platform.dbValue}';
}

abstract final class PlatformSpecs {
  static const _telegram = PlatformAccountSpec(
    platform: MessagingPlatform.telegram,
    identifierLabelKey: 'field_bot_username',
    identifierHintKey: 'hint_bot_username',
    secrets: [SecretField(key: 'bot_token', labelKey: 'field_bot_token', hintKey: 'hint_bot_token')],
  );
  static const _whatsapp = PlatformAccountSpec(
    platform: MessagingPlatform.whatsapp,
    identifierLabelKey: 'field_phone_number_id',
    identifierHintKey: 'hint_phone_number_id',
    secrets: [
      SecretField(key: 'access_token', labelKey: 'field_access_token', hintKey: 'hint_access_token'),
    ],
  );
  static const _rubika = PlatformAccountSpec(
    platform: MessagingPlatform.rubika,
    identifierLabelKey: 'field_account_identifier',
    identifierHintKey: 'hint_account_identifier',
  );
  static const _soroush = PlatformAccountSpec(
    platform: MessagingPlatform.soroush,
    identifierLabelKey: 'field_account_identifier',
    identifierHintKey: 'hint_account_identifier',
  );

  static PlatformAccountSpec of(MessagingPlatform p) => switch (p) {
        MessagingPlatform.telegram => _telegram,
        MessagingPlatform.whatsapp => _whatsapp,
        MessagingPlatform.rubika => _rubika,
        MessagingPlatform.soroush => _soroush,
      };
}

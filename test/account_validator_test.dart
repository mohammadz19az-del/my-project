import 'package:flutter_test/flutter_test.dart';
import 'package:tesla_org/features/accounts/domain/account_validator.dart';
import 'package:tesla_org/shared/enums/enums.dart';

void main() {
  const tg = MessagingPlatform.telegram;
  const wa = MessagingPlatform.whatsapp;

  test('telegram bot username', () {
    expect(AccountValidator.validateIdentifier(tg, '@my_test_bot'), isNull);
    expect(AccountValidator.validateIdentifier(tg, 'my_test_bot'), isNull);
    expect(AccountValidator.validateIdentifier(tg, 'MyTestBOT'), isNull);
    expect(AccountValidator.validateIdentifier(tg, 'not_a_robot_name'), 'validation_telegram_username');
    expect(AccountValidator.validateIdentifier(tg, 'abc'), 'validation_telegram_username');
    expect(AccountValidator.validateIdentifier(tg, '1abcbot'), 'validation_telegram_username');
    expect(AccountValidator.validateIdentifier(tg, '  '), 'validation_required');
  });

  test('telegram identifiers are stored as @name', () {
    expect(AccountValidator.normalizeIdentifier(tg, ' my_test_bot '), '@my_test_bot');
    expect(AccountValidator.normalizeIdentifier(tg, '@my_test_bot'), '@my_test_bot');
    expect(AccountValidator.normalizeIdentifier(wa, ' 123456789 '), '123456789');
  });

  test('telegram token format', () {
    expect(
      AccountValidator.validateSecret(tg, 'bot_token', '123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw'),
      isNull,
    );
    expect(AccountValidator.validateSecret(tg, 'bot_token', 'abc'), 'validation_telegram_token');
    expect(AccountValidator.validateSecret(tg, 'bot_token', '123:short'), 'validation_telegram_token');
    expect(AccountValidator.validateSecret(tg, 'bot_token', ''), 'validation_required');
  });

  test('whatsapp phone number id and token', () {
    expect(AccountValidator.validateIdentifier(wa, '109876543210987'), isNull);
    expect(AccountValidator.validateIdentifier(wa, '+98 912'), 'validation_whatsapp_phone_id');
    expect(AccountValidator.validateSecret(wa, 'access_token', 'EAAB${'x' * 30}'), isNull);
    expect(AccountValidator.validateSecret(wa, 'access_token', 'too short'), 'validation_whatsapp_token');
  });

  test('mock platforms only need a short identifier', () {
    expect(AccountValidator.validateIdentifier(MessagingPlatform.rubika, 'نام حساب'), isNull);
    expect(AccountValidator.validateIdentifier(MessagingPlatform.soroush, 'x' * 65), 'validation_identifier_length');
  });
}

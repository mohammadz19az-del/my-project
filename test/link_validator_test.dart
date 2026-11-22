import 'package:flutter_test/flutter_test.dart';
import 'package:tesla_org/core/utilities/link_validator.dart';
import 'package:tesla_org/shared/enums/enums.dart';

void main() {
  const valid = ValidationStatus.validFormat;
  const invalid = ValidationStatus.invalidFormat;

  test('telegram links', () {
    expect(LinkValidator.checkFormat(MessagingPlatform.telegram, 'https://t.me/joinchat/AbC'), valid);
    expect(LinkValidator.checkFormat(MessagingPlatform.telegram, 'https://www.t.me/group'), valid);
    expect(LinkValidator.checkFormat(MessagingPlatform.telegram, 'https://t.me/'), invalid);
    expect(LinkValidator.checkFormat(MessagingPlatform.telegram, 'https://chat.whatsapp.com/x'), invalid);
  });

  test('whatsapp links', () {
    expect(LinkValidator.checkFormat(MessagingPlatform.whatsapp, 'https://chat.whatsapp.com/Invite123'), valid);
    expect(LinkValidator.checkFormat(MessagingPlatform.whatsapp, 'https://chat.whatsapp.com'), invalid);
  });

  test('unverified platforms only get generic URL checks', () {
    expect(LinkValidator.checkFormat(MessagingPlatform.rubika, 'https://example.com/join/abc'), valid);
    expect(LinkValidator.checkFormat(MessagingPlatform.soroush, 'https://example.com/join/abc'), valid);
  });

  test('malformed input', () {
    for (final bad in ['', '   ', 'not a url', 'ftp://t.me/x', 'https://nodot/x', 'https://t.me/a b']) {
      expect(LinkValidator.checkFormat(MessagingPlatform.telegram, bad), invalid, reason: bad);
    }
  });

  test('never reports verified', () {
    for (final p in MessagingPlatform.values) {
      expect(LinkValidator.checkFormat(p, 'https://t.me/x'), isNot(ValidationStatus.verified));
    }
  });
}

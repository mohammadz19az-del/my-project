import 'package:flutter_test/flutter_test.dart';
import 'package:tesla_org/core/errors/app_exception.dart';
import 'package:tesla_org/shared/enums/enums.dart';
import 'package:tesla_org/shared/models/group_link.dart';

import 'support/test_fixture.dart';

void main() {
  late TestFixture f;
  setUp(() async => f = await TestFixture.create());
  tearDown(() => f.close());

  test('format is classified, platform comes from the account, never verified', () async {
    final tg = await f.account(MessagingPlatform.telegram);
    final ok = await f.groupLinks.create(
        GroupLinkInput(accountId: tg.id, url: ' https://t.me/joinchat/abc ', title: ' News '));
    expect(ok.platform, MessagingPlatform.telegram);
    expect(ok.url, 'https://t.me/joinchat/abc');
    expect(ok.title, 'News');
    expect(ok.validationStatus, ValidationStatus.validFormat);
    expect(ok.lastVerifiedAt, isNull);

    final bad = await f.groupLinks.create(GroupLinkInput(accountId: tg.id, url: 'not a url'));
    expect(bad.validationStatus, ValidationStatus.invalidFormat);

    final wa = await f.account(MessagingPlatform.whatsapp, 'wa');
    final wrongHost =
        await f.groupLinks.create(GroupLinkInput(accountId: wa.id, url: 'https://t.me/x'));
    expect(wrongHost.validationStatus, ValidationStatus.invalidFormat);
  });

  test('20 links per account; duplicates; empty url; unknown account', () async {
    final a = await f.account(MessagingPlatform.telegram);
    for (var i = 0; i < 20; i++) {
      await f.groupLinks.create(GroupLinkInput(accountId: a.id, url: 'https://t.me/g$i'));
    }
    await expectLater(
      f.groupLinks.create(GroupLinkInput(accountId: a.id, url: 'https://t.me/extra')),
      throwsA(isA<LimitExceededException>()),
    );
    await expectLater(
      f.groupLinks.create(GroupLinkInput(accountId: a.id, url: 'https://t.me/g0')),
      throwsA(isA<AppException>()),
    );
    expect(await f.groupLinks.countForAccount(a.id), 20);

    await expectLater(
      f.groupLinks.create(GroupLinkInput(accountId: a.id, url: '  ')),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      f.groupLinks.create(const GroupLinkInput(accountId: 9999, url: 'https://t.me/x')),
      throwsA(isA<NotFoundException>()),
    );
  });

  test('changing the URL clears verification; same URL keeps it', () async {
    final a = await f.account(MessagingPlatform.telegram);
    final link = await f.groupLinks.create(GroupLinkInput(accountId: a.id, url: 'https://t.me/one'));
    await f.groupLinks.updateValidation(link.id, ValidationStatus.verified);
    var current = (await f.groupLinks.getById(link.id))!;
    expect(current.validationStatus, ValidationStatus.verified);
    expect(current.lastVerifiedAt, isNotNull);

    current = await f.groupLinks.update(link.id, url: 'https://t.me/one', title: 'Renamed');
    expect(current.validationStatus, ValidationStatus.verified);

    current = await f.groupLinks.update(link.id, url: 'https://t.me/two');
    expect(current.validationStatus, ValidationStatus.validFormat);
    expect(current.lastVerifiedAt, isNull);
  });

  test('delete and filtered listing', () async {
    final tg = await f.account(MessagingPlatform.telegram);
    final wa = await f.account(MessagingPlatform.whatsapp, 'wa');
    final l1 = await f.groupLinks.create(GroupLinkInput(accountId: tg.id, url: 'https://t.me/a'));
    await f.groupLinks
        .create(GroupLinkInput(accountId: wa.id, url: 'https://chat.whatsapp.com/b'));
    expect((await f.groupLinks.listAll()).length, 2);
    expect((await f.groupLinks.listAll(platform: MessagingPlatform.whatsapp)).length, 1);
    await f.groupLinks.delete(l1.id);
    expect(await f.groupLinks.getById(l1.id), isNull);
    await expectLater(f.groupLinks.delete(l1.id), throwsA(isA<NotFoundException>()));
  });
}

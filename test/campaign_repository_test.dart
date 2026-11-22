import 'package:flutter_test/flutter_test.dart';
import 'package:tesla_org/core/errors/app_exception.dart';
import 'package:tesla_org/features/campaigns/data/campaign_repository.dart';
import 'package:tesla_org/shared/enums/enums.dart';
import 'package:tesla_org/shared/models/campaign.dart';
import 'package:tesla_org/shared/models/destination.dart';

import 'support/test_fixture.dart';

void main() {
  late TestFixture f;
  late int accountId;
  late int templateId;

  setUp(() async {
    f = await TestFixture.create();
    final a = await f.account(MessagingPlatform.telegram);
    accountId = a.id;
    templateId = (await f.template(a.id)).id;
  });
  tearDown(() => f.close());

  CampaignInput input({String name = 'Launch', DateTime? start, DateTime? end}) => CampaignInput(
        name: name,
        accountId: accountId,
        templateId: templateId,
        scheduleStart: start,
        scheduleEnd: end,
      );

  test('creates a draft and writes an audit event', () async {
    final c = await f.campaigns.create(input(name: '  Launch  '));
    expect(c.name, 'Launch');
    expect(c.status, CampaignStatus.draft);
    final events = await f.activity.recent();
    expect(events.where((e) => e.eventType == 'campaign_created' && e.campaignId == c.id).length, 1);
  });

  test('validation: name, schedule order, template/account match', () async {
    await expectLater(f.campaigns.create(input(name: '  ')), throwsA(isA<ValidationException>()));
    final now = DateTime.now();
    await expectLater(
      f.campaigns.create(input(start: now, end: now.subtract(const Duration(days: 1)))),
      throwsA(isA<ValidationException>()),
    );
    final other = await f.account(MessagingPlatform.whatsapp, 'wa');
    final foreignTemplate = await f.template(other.id, 'x');
    await expectLater(
      f.campaigns.create(CampaignInput(
          name: 'Bad', accountId: accountId, templateId: foreignTemplate.id)),
      throwsA(isA<ConstraintViolationException>()
          .having((e) => e.code, 'code', ErrorCodes.campaignTemplateAccountMismatch)),
    );
  });

  test('lifecycle transitions, timestamps and audit trail', () async {
    var c = await f.campaigns.create(input());
    c = await f.campaigns.transition(c.id, CampaignStatus.running);
    expect(c.startedAt, isNotNull);
    final startedAt = c.startedAt;
    c = await f.campaigns.transition(c.id, CampaignStatus.paused);
    c = await f.campaigns.transition(c.id, CampaignStatus.running);
    expect(c.startedAt, startedAt);
    expect(c.completedAt, isNull);
    c = await f.campaigns.transition(c.id, CampaignStatus.completed);
    expect(c.completedAt, isNotNull);

    await expectLater(
      f.campaigns.transition(c.id, CampaignStatus.running),
      throwsA(isA<ValidationException>()
          .having((e) => e.code, 'code', ErrorCodes.invalidCampaignTransition)),
    );
    final changes = (await f.activity.recent())
        .where((e) => e.eventType == 'campaign_status_changed')
        .length;
    expect(changes, 4);
  });

  test('transition table', () {
    expect(SqliteCampaignRepository.canTransition(CampaignStatus.draft, CampaignStatus.paused), isFalse);
    expect(SqliteCampaignRepository.canTransition(CampaignStatus.paused, CampaignStatus.running), isTrue);
    for (final t in [CampaignStatus.completed, CampaignStatus.cancelled, CampaignStatus.failed]) {
      expect(SqliteCampaignRepository.isTerminal(t), isTrue);
    }
  });

  test('only drafts can be edited or deleted', () async {
    final c = await f.campaigns.create(input());
    final edited = await f.campaigns.updateDraft(c.id, input(name: 'Renamed'));
    expect(edited.name, 'Renamed');
    await f.campaigns.transition(c.id, CampaignStatus.running);
    await expectLater(f.campaigns.updateDraft(c.id, input()), throwsA(isA<ValidationException>()));
    await expectLater(f.campaigns.delete(c.id), throwsA(isA<ValidationException>()));

    final d = await f.campaigns.create(input(name: 'Disposable'));
    await f.campaigns.delete(d.id);
    expect(await f.campaigns.getById(d.id), isNull);
  });

  test('counts by status and filtered list', () async {
    await f.campaigns.create(input(name: 'a'));
    final b = await f.campaigns.create(input(name: 'b'));
    await f.campaigns.transition(b.id, CampaignStatus.cancelled);
    final counts = await f.campaigns.countsByStatus();
    expect(counts[CampaignStatus.draft], 1);
    expect(counts[CampaignStatus.cancelled], 1);
    expect((await f.campaigns.list(status: CampaignStatus.cancelled)).single.name, 'b');
  });

  test('destinations: account match, consent gating, draft-only removal', () async {
    final c = await f.campaigns.create(input());
    final dest = await f.destinations.create(DestinationInput(
      accountId: accountId,
      platformDestinationId: ' chat-1 ',
      displayName: 'Team chat',
      destinationType: DestinationType.group,
    ));
    expect(dest.platformDestinationId, 'chat-1');

    final cd = await f.campaigns.addDestination(c.id, dest.id);
    expect(cd.isDeliverable, isFalse);
    expect(cd.displayName, 'Team chat');

    await f.campaigns.setDestinationConsent(c.id, dest.id, ConsentStatus.granted);
    await f.campaigns
        .setDestinationAuthorization(c.id, dest.id, AuthorizationStatus.authorized);
    expect((await f.campaigns.listDestinations(c.id)).single.isDeliverable, isTrue);

    await f.campaigns.setDestinationConsent(c.id, dest.id, ConsentStatus.revoked);
    expect((await f.campaigns.listDestinations(c.id)).single.isDeliverable, isFalse);

    final other = await f.account(MessagingPlatform.whatsapp, 'wa');
    final foreign = await f.destinations
        .create(DestinationInput(accountId: other.id, platformDestinationId: 'x'));
    await expectLater(
      f.campaigns.addDestination(c.id, foreign.id),
      throwsA(isA<ConstraintViolationException>()
          .having((e) => e.code, 'code', ErrorCodes.campaignDestinationAccountMismatch)),
    );

    await f.campaigns.transition(c.id, CampaignStatus.running);
    await expectLater(
        f.campaigns.removeDestination(c.id, dest.id), throwsA(isA<ValidationException>()));
  });

  test('destination validation and duplicates', () async {
    await expectLater(
      f.destinations.create(DestinationInput(accountId: accountId, platformDestinationId: ' ')),
      throwsA(isA<ValidationException>()),
    );
    await f.destinations.create(DestinationInput(accountId: accountId, platformDestinationId: 'd'));
    await expectLater(
      f.destinations.create(DestinationInput(accountId: accountId, platformDestinationId: 'd')),
      throwsA(isA<DuplicateRecordException>()),
    );
    final d = (await f.destinations.listForAccount(accountId)).single;
    final updated = await f.destinations.setAuthorization(d.id, AuthorizationStatus.authorized);
    expect(updated.authorizationStatus, AuthorizationStatus.authorized);
  });
}

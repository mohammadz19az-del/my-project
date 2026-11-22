import 'package:flutter_test/flutter_test.dart';
import 'package:tesla_org/features/campaigns/data/delivery_repository.dart';
import 'package:tesla_org/features/dashboard/data/dashboard_repository.dart';
import 'package:tesla_org/shared/enums/enums.dart';
import 'package:tesla_org/shared/models/campaign.dart';
import 'package:tesla_org/shared/models/delivery_record.dart';
import 'package:tesla_org/shared/models/destination.dart';

import 'support/test_fixture.dart';

void main() {
  late TestFixture f;
  late SqliteDashboardRepository dashboard;

  setUp(() async {
    f = await TestFixture.create();
    dashboard = SqliteDashboardRepository(f.appDb.db);
  });
  tearDown(() => f.close());

  test('empty database yields all zeros and no accounts', () async {
    final s = await dashboard.loadStats();
    expect(s.hasAnyAccounts, isFalse);
    expect(s.totalAccounts, 0);
    expect(s.totalTemplates, 0);
    expect(s.activeCampaigns, 0);
    expect(s.successfulDeliveries + s.failedDeliveries + s.pendingDeliveries, 0);
    expect(s.platforms.length, MessagingPlatform.values.length);
  });

  test('numbers are derived from stored records', () async {
    final tg1 = await f.account(MessagingPlatform.telegram, 'tg1');
    await f.account(MessagingPlatform.telegram, 'tg2');
    final wa = await f.account(MessagingPlatform.whatsapp, 'wa');
    await f.accounts.updateConnectionStatus(tg1.id, ConnectionStatus.connected);
    await f.accounts.updateConnectionStatus(wa.id, ConnectionStatus.mockConnection);
    final tmpl = await f.template(tg1.id);
    await f.template(tg1.id, 'second');

    // two campaigns: one running (active), one completed
    final running = await f.campaigns
        .create(CampaignInput(name: 'r', accountId: tg1.id, templateId: tmpl.id));
    await f.campaigns.transition(running.id, CampaignStatus.running);
    final done = await f.campaigns
        .create(CampaignInput(name: 'd', accountId: tg1.id, templateId: tmpl.id));
    await f.campaigns.transition(done.id, CampaignStatus.running);
    await f.campaigns.transition(done.id, CampaignStatus.completed);
    await f.campaigns.create(CampaignInput(name: 'draft', accountId: tg1.id, templateId: tmpl.id));

    // four deliveries: delivered, sent, failed, pending
    final ids = <int>[];
    for (var i = 0; i < 4; i++) {
      final d = await f.destinations
          .create(DestinationInput(accountId: tg1.id, platformDestinationId: 'd$i'));
      await f.campaigns.addDestination(running.id, d.id,
          consent: ConsentStatus.granted, authorization: AuthorizationStatus.authorized);
      final r = await f.deliveries.createOrGet(DeliveryInput(
        campaignId: running.id,
        destinationId: d.id,
        templateId: tmpl.id,
        idempotencyKey: DeliveryRepository.buildIdempotencyKey(
            campaignId: running.id, destinationId: d.id, templateId: tmpl.id),
      ));
      ids.add(r.record.id);
    }
    await f.deliveries.markSending(ids[0]);
    await f.deliveries.markSent(ids[0]);
    await f.deliveries.markDelivered(ids[0]);
    await f.deliveries.markSending(ids[1]);
    await f.deliveries.markSent(ids[1]);
    await f.deliveries.markSending(ids[2]);
    await f.deliveries.markFailed(ids[2], errorCode: 'X');

    final s = await dashboard.loadStats();
    expect(s.hasAnyAccounts, isTrue);
    expect(s.totalAccounts, 3);
    expect(s.connectedAccounts, 1);
    expect(s.disconnectedAccounts, 1); // tg2
    expect(s.otherStateAccounts, 1); // mock connection
    expect(s.platforms[MessagingPlatform.telegram]!.total, 2);
    expect(s.platforms[MessagingPlatform.telegram]!.connected, 1);
    expect(s.platforms[MessagingPlatform.whatsapp]!.total, 1);
    expect(s.platforms[MessagingPlatform.rubika]!.total, 0);
    expect(s.totalTemplates, 2);
    expect(s.activeCampaigns, 1);
    expect(s.completedCampaigns, 1);
    expect(s.successfulDeliveries, 2);
    expect(s.failedDeliveries, 1);
    expect(s.pendingDeliveries, 1);
  });
}

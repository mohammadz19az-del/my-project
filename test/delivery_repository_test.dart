import 'package:flutter_test/flutter_test.dart';
import 'package:tesla_org/core/errors/app_exception.dart';
import 'package:tesla_org/features/campaigns/data/delivery_repository.dart';
import 'package:tesla_org/shared/enums/enums.dart';
import 'package:tesla_org/shared/models/campaign.dart';
import 'package:tesla_org/shared/models/delivery_record.dart';
import 'package:tesla_org/shared/models/destination.dart';

import 'support/test_fixture.dart';

void main() {
  late TestFixture f;
  late int campaignId;
  late int destinationId;
  late int templateId;

  DeliveryInput delivery([int round = 1]) => DeliveryInput(
        campaignId: campaignId,
        destinationId: destinationId,
        templateId: templateId,
        idempotencyKey: DeliveryRepository.buildIdempotencyKey(
          campaignId: campaignId,
          destinationId: destinationId,
          templateId: templateId,
          round: round,
        ),
      );

  Future<void> grantConsent() async {
    await f.campaigns.setDestinationConsent(campaignId, destinationId, ConsentStatus.granted);
    await f.campaigns
        .setDestinationAuthorization(campaignId, destinationId, AuthorizationStatus.authorized);
  }

  setUp(() async {
    f = await TestFixture.create();
    final a = await f.account(MessagingPlatform.telegram);
    templateId = (await f.template(a.id)).id;
    final c = await f.campaigns
        .create(CampaignInput(name: 'c', accountId: a.id, templateId: templateId));
    campaignId = c.id;
    final d = await f.destinations
        .create(DestinationInput(accountId: a.id, platformDestinationId: 'chat'));
    destinationId = d.id;
    await f.campaigns.addDestination(campaignId, destinationId);
  });
  tearDown(() => f.close());

  test('no delivery record without granted consent and authorization', () async {
    await expectLater(
      f.deliveries.createOrGet(delivery()),
      throwsA(isA<ConstraintViolationException>()
          .having((e) => e.code, 'code', ErrorCodes.deliveryConsentRequired)),
    );
    await grantConsent();
    expect((await f.deliveries.createOrGet(delivery())).created, isTrue);

    // Revoking consent blocks any further (new) deliveries.
    await f.campaigns.setDestinationConsent(campaignId, destinationId, ConsentStatus.revoked);
    await expectLater(
      f.deliveries.createOrGet(delivery(2)),
      throwsA(isA<ConstraintViolationException>()),
    );
  });

  test('idempotency: the same key returns the existing record', () async {
    await grantConsent();
    final first = await f.deliveries.createOrGet(delivery());
    final second = await f.deliveries.createOrGet(delivery());
    expect(first.created, isTrue);
    expect(second.created, isFalse);
    expect(second.record.id, first.record.id);
    expect((await f.deliveries.listForCampaign(campaignId)).length, 1);
  });

  test('happy path: pending -> sending -> sent -> delivered', () async {
    await grantConsent();
    var r = (await f.deliveries.createOrGet(delivery())).record;
    expect(r.status, DeliveryStatus.pending);
    r = await f.deliveries.markSending(r.id);
    expect(r.attemptCount, 1);
    r = await f.deliveries.markSent(r.id, platformMessageId: 'm-1');
    expect(r.platformMessageId, 'm-1');
    r = await f.deliveries.markDelivered(r.id);
    expect(r.status, DeliveryStatus.delivered);
    expect(r.deliveredAt, isNotNull);
  });

  test('invalid transitions are rejected', () async {
    await grantConsent();
    final r = (await f.deliveries.createOrGet(delivery())).record;
    await expectLater(
      f.deliveries.markDelivered(r.id),
      throwsA(isA<ValidationException>()
          .having((e) => e.code, 'code', ErrorCodes.invalidDeliveryTransition)),
    );
    expect(DeliveryRepositoryTransitions.pendingToSent, isFalse);
  });

  test('failure stores a redacted message; requeue allows a safe retry', () async {
    await grantConsent();
    var r = (await f.deliveries.createOrGet(delivery())).record;
    r = await f.deliveries.markSending(r.id);
    r = await f.deliveries
        .markFailed(r.id, errorCode: 'HTTP_401', errorMessage: 'bad token=SECRET123 supplied');
    expect(r.status, DeliveryStatus.failed);
    expect(r.errorCode, 'HTTP_401');
    expect(r.errorMessage!.contains('SECRET123'), isFalse);

    r = await f.deliveries.requeueFailed(r.id);
    expect(r.status, DeliveryStatus.pending);
    r = await f.deliveries.markSending(r.id);
    expect(r.attemptCount, 2);
  });

  test('recovery resets interrupted sends; counts by status', () async {
    await grantConsent();
    final r = (await f.deliveries.createOrGet(delivery())).record;
    await f.deliveries.markSending(r.id);
    expect((await f.deliveries.countsByStatus())[DeliveryStatus.sending], 1);
    expect(await f.deliveries.recoverInterrupted(), 1);
    final counts = await f.deliveries.countsByStatus(campaignId: campaignId);
    expect(counts[DeliveryStatus.pending], 1);
    expect(counts[DeliveryStatus.sending], 0);
  });
}

/// Pure transition-table checks (no database).
abstract final class DeliveryRepositoryTransitions {
  static final bool pendingToSent =
      SqliteDeliveryRepository.canTransition(DeliveryStatus.pending, DeliveryStatus.sent);
}

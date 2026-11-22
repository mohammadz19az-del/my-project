import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tesla_org/core/errors/app_exception.dart';
import 'package:tesla_org/core/security/credential_store.dart';
import 'package:tesla_org/features/campaigns/campaign_engine.dart';
import 'package:tesla_org/features/campaigns/campaigns_screen.dart' show validateDestinationId;
import 'package:tesla_org/features/campaigns/data/delivery_repository.dart';
import 'package:tesla_org/integrations/common/mock_adapter.dart';
import 'package:tesla_org/integrations/common/platform_adapter.dart';
import 'package:tesla_org/shared/enums/enums.dart';
import 'package:tesla_org/shared/models/account.dart';
import 'package:tesla_org/shared/models/campaign.dart';
import 'package:tesla_org/shared/models/delivery_record.dart';
import 'package:tesla_org/shared/models/destination.dart';

import 'support/test_fixture.dart';

/// Adapter that replays a script of results and records every send.
class ScriptedAdapter implements PlatformAdapter {
  ScriptedAdapter(this.platform, {this.minInterval = 1});

  @override
  final MessagingPlatform platform;
  final int minInterval;
  final List<SendResult> script = [];
  final List<SendRequest> sent = [];
  Future<void> Function(SendRequest)? onSend;

  @override
  AdapterMode get mode => AdapterMode.real;

  @override
  AdapterCapabilities get capabilities => AdapterCapabilities(
      items: const {}, overall: IntegrationStatus.partiallySupported, minIntervalSeconds: minInterval);

  @override
  Future<ConnectResult> connect({required String accountIdentifier, required AccountCredentials credentials}) async =>
      const ConnectResult(ConnectionStatus.connected);

  @override
  Future<void> disconnect({required String accountIdentifier}) async {}

  @override
  Future<GroupCheck> checkGroupLink({required AccountCredentials credentials, required String url}) async =>
      const GroupCheck(ValidationStatus.unknown);

  @override
  Future<SendResult> sendText(SendRequest request) async {
    sent.add(request);
    await onSend?.call(request);
    return script.isEmpty ? SendResult(SendOutcome.sent, messageId: 'm${sent.length}') : script.removeAt(0);
  }
}

void main() {
  late TestFixture f;
  late InMemoryCredentialStore store;
  late ScriptedAdapter adapter;
  late CampaignEngine engine;
  late Account account;
  late int templateId;
  var now = DateTime.now();
  final events = <EngineEvent>[];

  CampaignEngine buildEngine() => CampaignEngine(
        campaigns: f.campaigns,
        deliveries: f.deliveries,
        templates: f.templates,
        accounts: f.accounts,
        store: store,
        registry: AdapterRegistry([
          adapter,
          ScriptedAdapter(MessagingPlatform.whatsapp),
          MockPlatformAdapter(MessagingPlatform.rubika),
          MockPlatformAdapter(MessagingPlatform.soroush),
        ]),
        activity: f.activity,
        delay: (_) async {},
        now: () => now,
      );

  setUp(() async {
    f = await TestFixture.create();
    store = InMemoryCredentialStore();
    adapter = ScriptedAdapter(MessagingPlatform.telegram);
    engine = buildEngine();
    events.clear();
    engine.events.listen(events.add);
    now = DateTime.now();
    await store.write('ref', {'bot_token': 'T'});
    account = await f.accounts.create(const AccountInput(
        platform: MessagingPlatform.telegram, accountIdentifier: '@x_bot', credentialReference: 'ref'));
    await f.accounts.updateConnectionStatus(account.id, ConnectionStatus.connected);
    templateId = (await f.template(account.id)).id;
  });
  tearDown(() => f.close());

  Future<Campaign> campaign({int rounds = 1, int interval = 1, int? max, DateTime? start}) =>
      f.campaigns.create(CampaignInput(
          name: 'c', accountId: account.id, templateId: templateId,
          sendIntervalSeconds: interval, rounds: rounds, maxDeliveries: max, scheduleStart: start));

  Future<Destination> destination(Campaign c, String id, {bool consent = true}) async {
    final d = await f.destinations.create(DestinationInput(accountId: account.id, platformDestinationId: id));
    await f.campaigns.addDestination(c.id, d.id,
        consent: consent ? ConsentStatus.granted : ConsentStatus.pending,
        authorization: consent ? AuthorizationStatus.authorized : AuthorizationStatus.unknown);
    return d;
  }

  Future<Map<DeliveryStatus, int>> counts(Campaign c) => f.deliveries.countsByStatus(campaignId: c.id);
  Future<void> run(Campaign c) async {
    await engine.start(c.id);
    await engine.whenIdle(c.id);
    await Future<void>.delayed(Duration.zero);
  }

  test('sends only to consenting destinations, then completes', () async {
    final c = await campaign();
    await destination(c, '1001');
    await destination(c, '1002');
    await destination(c, '1003', consent: false);
    await run(c);

    expect(adapter.sent.map((r) => r.destinationId), ['1001', '1002']);
    expect(adapter.sent.first.credentials['bot_token'], 'T');
    final counts0 = await counts(c);
    expect(counts0[DeliveryStatus.sent], 2);
    expect((await f.deliveries.listForCampaign(c.id)).length, 2); // none for the non-consenting one
    expect((await f.campaigns.getById(c.id))!.status, CampaignStatus.completed);
    expect(events.map((e) => e.type), contains(EngineEventType.completed));
    expect(engine.isRunning(c.id), isFalse);
  });

  test('pre-flight refuses unsafe starts and leaves the campaign untouched', () async {
    final c = await campaign();
    await expectLater(engine.start(c.id),
        throwsA(isA<ValidationException>().having((e) => e.code, 'code', ErrorCodes.campaignNoDestinations)));
    await destination(c, '1001', consent: false);
    await expectLater(engine.start(c.id), throwsA(isA<ValidationException>()));
    expect((await f.campaigns.getById(c.id))!.status, CampaignStatus.draft);

    final ok = await campaign();
    await destination(ok, '2001');
    await f.accounts.updateConnectionStatus(account.id, ConnectionStatus.disconnected);
    await expectLater(engine.start(ok.id),
        throwsA(isA<ValidationException>().having((e) => e.code, 'code', ErrorCodes.accountNotConnected)));
    await f.accounts.updateConnectionStatus(account.id, ConnectionStatus.connected);

    final t = (await f.templates.listForAccount(account.id)).first;
    await f.templates.setEnabled(t.id, enabled: false);
    await expectLater(engine.start(ok.id),
        throwsA(isA<ValidationException>().having((e) => e.code, 'code', ErrorCodes.templateDisabled)));
    await f.templates.setEnabled(t.id, enabled: true);

    adapter = ScriptedAdapter(MessagingPlatform.telegram, minInterval: 3);
    engine = buildEngine();
    await expectLater(engine.start(ok.id),
        throwsA(isA<ValidationException>().having((e) => e.code, 'code', ErrorCodes.intervalTooShort)));
    expect(adapter.sent, isEmpty);
  });

  test('rounds create one record per destination and round; existing sent records are not resent', () async {
    final c = await campaign(rounds: 2);
    final d1 = await destination(c, '1001');
    await destination(c, '1002');
    final pre = await f.deliveries.createOrGet(DeliveryInput(
      campaignId: c.id, destinationId: d1.id, templateId: templateId,
      idempotencyKey: DeliveryRepository.buildIdempotencyKey(
          campaignId: c.id, destinationId: d1.id, templateId: templateId, round: 1),
    ));
    await f.deliveries.markSending(pre.record.id);
    await f.deliveries.markSent(pre.record.id, platformMessageId: 'old');

    await run(c);
    expect(adapter.sent.length, 3); // 2 destinations x 2 rounds, minus the one already sent
    expect((await f.deliveries.listForCampaign(c.id)).length, 4);
  });

  test('rate limit: waits retry_after, retries, restores the account status', () async {
    final c = await campaign();
    await destination(c, '1001');
    adapter.script.add(const SendResult(SendOutcome.rateLimited,
        errorCode: 'TG_429', retryAfter: Duration(seconds: 2)));
    await run(c);
    final rec = (await f.deliveries.listForCampaign(c.id)).single;
    expect(rec.status, DeliveryStatus.sent);
    expect(rec.attemptCount, 2);
    expect(adapter.sent.length, 2);
    expect((await f.accounts.getById(account.id))!.connectionStatus, ConnectionStatus.connected);
  });

  test('repeated rate limits pause the campaign and keep the delivery pending', () async {
    final c = await campaign();
    await destination(c, '1001');
    for (var i = 0; i < 3; i++) {
      adapter.script.add(const SendResult(SendOutcome.rateLimited, retryAfter: Duration(seconds: 1)));
    }
    await run(c);
    expect((await f.campaigns.getById(c.id))!.status, CampaignStatus.paused);
    expect((await f.deliveries.listForCampaign(c.id)).single.status, DeliveryStatus.pending);
    expect(events.map((e) => e.type), contains(EngineEventType.autoPaused));
    expect((await f.accounts.getById(account.id))!.connectionStatus, ConnectionStatus.rateLimited);

    // Resume continues with the same record (no duplicate).
    await run(c);
    expect((await f.campaigns.getById(c.id))!.status, CampaignStatus.completed);
    expect((await f.deliveries.listForCampaign(c.id)).length, 1);
  });

  test('rejected credentials fail the delivery, pause the campaign and flag the account', () async {
    final c = await campaign();
    await destination(c, '1001');
    await destination(c, '1002');
    adapter.script.add(const SendResult(SendOutcome.authFailed, errorCode: 'TG_401'));
    await run(c);
    expect(adapter.sent.length, 1);
    expect((await f.campaigns.getById(c.id))!.status, CampaignStatus.paused);
    expect((await f.accounts.getById(account.id))!.connectionStatus, ConnectionStatus.authenticationRequired);
    expect(events.map((e) => e.type), contains(EngineEventType.authExpired));
    expect((await counts(c))[DeliveryStatus.failed], 1);
  });

  test('a rejected destination fails alone; temporary errors retry then fail', () async {
    final c = await campaign();
    await destination(c, '1001');
    await destination(c, '1002');
    await destination(c, '1003');
    adapter.script
      ..add(const SendResult(SendOutcome.rejected, errorCode: 'TG_403', errorMessage: 'blocked'))
      ..addAll(List.filled(3, const SendResult(SendOutcome.retryable, errorCode: 'NETWORK')));
    await run(c);
    final recs = await f.deliveries.listForCampaign(c.id);
    expect(recs.map((r) => r.status), [DeliveryStatus.failed, DeliveryStatus.failed, DeliveryStatus.sent]);
    expect(recs[0].errorCode, 'TG_403');
    expect(recs[1].errorCode, 'NETWORK');
    expect(recs[1].attemptCount, 3);
  });

  test('mock integrations are recorded as simulated, never as sent', () async {
    final mock = await f.accounts.create(const AccountInput(
        platform: MessagingPlatform.rubika, accountIdentifier: 'demo'));
    await f.accounts.updateConnectionStatus(mock.id, ConnectionStatus.mockConnection);
    final t = await f.template(mock.id);
    final c = await f.campaigns.create(CampaignInput(
        name: 'm', accountId: mock.id, templateId: t.id, sendIntervalSeconds: 1));
    final d = await f.destinations.create(DestinationInput(accountId: mock.id, platformDestinationId: 'x'));
    await f.campaigns.addDestination(c.id, d.id,
        consent: ConsentStatus.granted, authorization: AuthorizationStatus.authorized);
    await run(c);
    final counts0 = await counts(c);
    expect(counts0[DeliveryStatus.skipped], 1);
    expect(counts0[DeliveryStatus.sent], 0);
  });

  test('maximum sends stops the campaign', () async {
    final c = await campaign(max: 1);
    await destination(c, '1001');
    await destination(c, '1002');
    await run(c);
    expect(adapter.sent.length, 1);
    expect((await f.campaigns.getById(c.id))!.status, CampaignStatus.completed);
  });

  test('consent revoked while running is honoured before the next send', () async {
    final c = await campaign();
    await destination(c, '1001');
    final d2 = await destination(c, '1002');
    adapter.onSend = (_) async {
      await f.campaigns.setDestinationConsent(c.id, d2.id, ConsentStatus.revoked);
    };
    await run(c);
    expect(adapter.sent.map((r) => r.destinationId), ['1001']);
  });

  test('pause and resume continue without duplicates', () async {
    final c = await campaign();
    await destination(c, '1001');
    await destination(c, '1002');
    var paused = false;
    adapter.onSend = (_) async {
      if (!paused) {
        paused = true;
        await engine.pause(c.id);
      }
    };
    await run(c);
    expect((await f.campaigns.getById(c.id))!.status, CampaignStatus.paused);
    expect(adapter.sent.length, 1);

    await run(c); // resume
    expect(adapter.sent.map((r) => r.destinationId), ['1001', '1002']);
    expect((await f.campaigns.getById(c.id))!.status, CampaignStatus.completed);
  });

  test('stop cancels and the worker ends', () async {
    final c = await campaign();
    await destination(c, '1001');
    await destination(c, '1002');
    adapter.onSend = (_) => engine.stop(c.id);
    await run(c);
    expect((await f.campaigns.getById(c.id))!.status, CampaignStatus.cancelled);
    expect(adapter.sent.length, 1);
  });

  test('recover(): running campaigns become paused and interrupted sends return to pending', () async {
    final c = await campaign();
    final d = await destination(c, '1001');
    final rec = (await f.deliveries.createOrGet(DeliveryInput(
      campaignId: c.id, destinationId: d.id, templateId: templateId,
      idempotencyKey: DeliveryRepository.buildIdempotencyKey(campaignId: c.id, destinationId: d.id, templateId: templateId),
    ))).record;
    await f.deliveries.markSending(rec.id);
    await f.campaigns.transition(c.id, CampaignStatus.running); // as if the app died mid-run

    expect(await engine.recover(), 1);
    expect((await f.campaigns.getById(c.id))!.status, CampaignStatus.paused);
    expect((await f.deliveries.getById(rec.id))!.status, DeliveryStatus.pending);
    expect((await f.activity.recent()).any((e) => e.eventType == 'campaign_interrupted'), isTrue);
    expect(engine.isRunning(c.id), isFalse);
  });

  test('scheduling: needs a future start; the scheduler starts due campaigns', () async {
    final past = await campaign(start: now.subtract(const Duration(hours: 1)));
    await destination(past, '1');
    await expectLater(engine.schedule(past.id), throwsA(isA<ValidationException>()));

    final c = await campaign(start: now.add(const Duration(hours: 1)));
    await destination(c, '2001');
    await engine.schedule(c.id);
    expect((await f.campaigns.getById(c.id))!.status, CampaignStatus.scheduled);
    expect(await engine.startDueCampaigns(), 0); // not due yet

    now = now.add(const Duration(hours: 2));
    expect(await engine.startDueCampaigns(), 1);
    await engine.whenIdle(c.id);
    expect((await f.campaigns.getById(c.id))!.status, CampaignStatus.completed);
  });

  test('destination identifier validation', () {
    expect(validateDestinationId(MessagingPlatform.telegram, '-1001234567890'), isNull);
    expect(validateDestinationId(MessagingPlatform.telegram, '@public_chat'), isNull);
    expect(validateDestinationId(MessagingPlatform.telegram, 'hello'), 'validation_destination_telegram');
    expect(validateDestinationId(MessagingPlatform.whatsapp, '+491701234567'), isNull);
    expect(validateDestinationId(MessagingPlatform.whatsapp, '0170123'), 'validation_destination_whatsapp');
    expect(validateDestinationId(MessagingPlatform.rubika, ' '), 'validation_required');
  });
}

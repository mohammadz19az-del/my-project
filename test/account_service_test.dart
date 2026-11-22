import 'package:flutter_test/flutter_test.dart';
import 'package:tesla_org/core/errors/app_exception.dart';
import 'package:tesla_org/core/security/credential_store.dart';
import 'package:tesla_org/features/accounts/application/account_service.dart';
import 'package:tesla_org/integrations/common/mock_adapter.dart';
import 'package:tesla_org/integrations/common/platform_adapter.dart';
import 'package:tesla_org/shared/enums/enums.dart';
import 'package:tesla_org/shared/models/campaign.dart';

import 'support/test_fixture.dart';

const _token = '123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw';
final _waToken = 'EAAB${'x' * 30}';

/// Configurable adapter standing in for a verified real integration.
class FakeRealAdapter implements PlatformAdapter {
  FakeRealAdapter(this.platform, {this.result, this.throwOnConnect = false});

  @override
  final MessagingPlatform platform;
  ConnectResult? result;
  bool throwOnConnect;
  int connectCalls = 0;
  int disconnectCalls = 0;
  AccountCredentials? lastCredentials;

  @override
  AdapterMode get mode => AdapterMode.real;

  @override
  AdapterCapabilities get capabilities =>
      const AdapterCapabilities(items: {}, overall: IntegrationStatus.partiallySupported);

  @override
  Future<SendResult> sendText(SendRequest request) async => const SendResult(SendOutcome.sent);

  @override
  Future<GroupCheck> checkGroupLink({required AccountCredentials credentials, required String url}) async =>
      const GroupCheck(ValidationStatus.verified, title: 'Group');

  @override
  Future<ConnectResult> connect({
    required String accountIdentifier,
    required AccountCredentials credentials,
  }) async {
    connectCalls++;
    lastCredentials = credentials;
    if (throwOnConnect) throw StateError('boom token=LEAK');
    return result ?? const ConnectResult(ConnectionStatus.connected);
  }

  @override
  Future<void> disconnect({required String accountIdentifier}) async => disconnectCalls++;
}

class FailingStore extends InMemoryCredentialStore {
  @override
  Future<void> write(String reference, Map<String, String> values) =>
      throw const CredentialStorageFailure('down');
}

void main() {
  late TestFixture f;
  late InMemoryCredentialStore store;
  late FakeRealAdapter telegram;
  late AccountService service;

  AccountService build(InMemoryCredentialStore s, {FakeRealAdapter? tg}) => AccountService(
        accounts: f.accounts,
        store: s,
        registry: AdapterRegistry([
          tg ?? telegram,
          FakeRealAdapter(MessagingPlatform.whatsapp,
              result: const ConnectResult(ConnectionStatus.unsupported, errorCode: 'ADAPTER_UNAVAILABLE')),
          MockPlatformAdapter(MessagingPlatform.rubika),
          MockPlatformAdapter(MessagingPlatform.soroush),
        ]),
        activity: f.activity,
      );

  AccountDraft tgDraft([String name = 'my_test_bot']) => AccountDraft(
        platform: MessagingPlatform.telegram,
        identifier: name,
        displayName: 'Main bot',
        secrets: const {'bot_token': _token},
      );

  setUp(() async {
    f = await TestFixture.create();
    store = InMemoryCredentialStore();
    telegram = FakeRealAdapter(MessagingPlatform.telegram);
    service = build(store);
  });
  tearDown(() => f.close());

  test('create keeps the secret in secure storage and only a reference in SQLite', () async {
    final a = await service.create(tgDraft());
    expect(a.accountIdentifier, '@my_test_bot');
    expect(a.credentialReference, isNotNull);
    expect((await store.read(a.credentialReference!))!['bot_token'], _token);

    final rows = await f.appDb.db.query('accounts');
    expect(rows.toString().contains(_token), isFalse);
    expect(await service.hasStoredCredentials(a), isTrue);
  });

  test('invalid input is rejected before anything is stored', () async {
    await expectLater(
      service.create(const AccountDraft(
        platform: MessagingPlatform.telegram,
        identifier: 'my_test_bot',
        secrets: {'bot_token': 'nope'},
      )),
      throwsA(isA<ValidationException>()),
    );
    expect(store.length, 0);
    expect(await f.accounts.list(), isEmpty);
  });

  test('database rejection (limit, duplicate) rolls the secret back', () async {
    for (var i = 0; i < 10; i++) {
      await service.create(tgDraft('bot_number_${i}_bot'));
    }
    expect(store.length, 10);
    await expectLater(service.create(tgDraft('another_one_bot')), throwsA(isA<LimitExceededException>()));
    expect(store.length, 10);

    await expectLater(service.create(tgDraft('bot_number_0_bot')), throwsA(isA<AppException>()));
    expect(store.length, 10);
  });

  test('secure storage failure means no account is created', () async {
    final failing = build(FailingStore());
    await expectLater(failing.create(tgDraft()), throwsA(isA<CredentialStorageFailure>()));
    expect(await f.accounts.list(), isEmpty);
  });

  test('mock platforms need no secret and store none', () async {
    final a = await service.create(const AccountDraft(
        platform: MessagingPlatform.rubika, identifier: 'my rubika'));
    expect(a.credentialReference, isNull);
    expect(store.length, 0);
  });

  test('update: blank secret keeps the stored one; new secret replaces it', () async {
    final a = await service.create(tgDraft());
    await service.update(a.id, identifier: 'my_test_bot', displayName: 'Renamed');
    expect((await store.read(a.credentialReference!))!['bot_token'], _token);

    const newToken = '987654321:BBHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw';
    final updated = await service.update(a.id,
        identifier: 'my_test_bot', displayName: 'Renamed', newSecrets: {'bot_token': newToken});
    expect((await store.read(a.credentialReference!))!['bot_token'], newToken);
    expect(updated.displayName, 'Renamed');
    expect(store.length, 1);
  });

  test('changing credentials of a live connection disconnects it first', () async {
    final a = await service.create(tgDraft());
    await service.connect(a.id);
    expect((await f.accounts.getById(a.id))!.connectionStatus, ConnectionStatus.connected);
    await service.update(a.id,
        identifier: 'my_test_bot',
        newSecrets: {'bot_token': '987654321:BBHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw'});
    expect((await f.accounts.getById(a.id))!.connectionStatus, ConnectionStatus.disconnected);
    expect(telegram.disconnectCalls, 1);
  });

  test('delete removes the secret; campaign history blocks deletion and keeps it', () async {
    final a = await service.create(tgDraft());
    final ref = a.credentialReference!;
    final t = await f.template(a.id);
    final c = await f.campaigns.create(CampaignInput(name: 'c', accountId: a.id, templateId: t.id));

    await expectLater(service.delete(a.id), throwsA(isA<ConstraintViolationException>()));
    expect(await store.contains(ref), isTrue);
    expect(await f.accounts.getById(a.id), isNotNull);

    await f.campaigns.delete(c.id);
    await service.delete(a.id);
    expect(await store.contains(ref), isFalse);
    expect(await f.accounts.getById(a.id), isNull);
  });

  test('connect with a verified adapter: connected, timestamps, display name adopted', () async {
    telegram.result = const ConnectResult(ConnectionStatus.connected, displayName: 'Bot Display');
    final a = await service.create(const AccountDraft(
      platform: MessagingPlatform.telegram,
      identifier: 'my_test_bot',
      secrets: {'bot_token': _token},
    ));
    final out = await service.connect(a.id);
    expect(out.connectionStatus, ConnectionStatus.connected);
    expect(out.lastConnectedAt, isNotNull);
    expect(out.lastActivityAt, isNotNull);
    expect(out.displayName, 'Bot Display');
    expect(telegram.lastCredentials!['bot_token'], _token);
  });

  test('mock connection is labelled mock and never counts as a real connection', () async {
    final a = await service.create(const AccountDraft(
        platform: MessagingPlatform.soroush, identifier: 'demo'));
    final out = await service.connect(a.id);
    expect(out.connectionStatus, ConnectionStatus.mockConnection);
    expect(out.lastConnectedAt, isNull);
  });

  test('an adapter that reports unsupported is stored as unsupported, never as connected', () async {
    final a = await service.create(AccountDraft(
      platform: MessagingPlatform.whatsapp,
      identifier: '109876543210987',
      secrets: {'access_token': _waToken},
    ));
    final out = await service.connect(a.id);
    expect(out.connectionStatus, ConnectionStatus.unsupported);
    expect(out.lastConnectedAt, isNull);
    final events = await f.activity.recent();
    expect(events.any((e) => e.eventType == 'account_connect_failed'), isTrue);
  });

  test('group link check: verified only through the adapter, never without credentials', () async {
    final a = await service.create(tgDraft());
    final ok = await service.checkGroupLink(a, 'https://t.me/somegroup');
    expect(ok.status, ValidationStatus.verified);

    final bare = await f.accounts.create(const AccountInput(
        platform: MessagingPlatform.telegram, accountIdentifier: '@legacy_bot'));
    final noCreds = await service.checkGroupLink(bare, 'https://t.me/somegroup');
    expect(noCreds.status, ValidationStatus.authorizationUnavailable);
  });

  test('missing credentials -> authentication required (adapter not called)', () async {
    final a = await f.accounts.create(const AccountInput(
        platform: MessagingPlatform.telegram, accountIdentifier: '@legacy_bot'));
    final out = await service.connect(a.id);
    expect(out.connectionStatus, ConnectionStatus.authenticationRequired);
    expect(telegram.connectCalls, 0);
  });

  test('an adapter exception becomes an error status without leaking details', () async {
    telegram.throwOnConnect = true;
    final a = await service.create(tgDraft());
    final out = await service.connect(a.id);
    expect(out.connectionStatus, ConnectionStatus.error);
    final events = await f.activity.recent();
    final failed = events.firstWhere((e) => e.eventType == 'account_connect_failed');
    expect(failed.metadataJson.contains('LEAK'), isFalse);
    expect(failed.description.contains(_token), isFalse);
  });

  test('disconnect', () async {
    final a = await service.create(tgDraft());
    await service.connect(a.id);
    final out = await service.disconnect(a.id);
    expect(out.connectionStatus, ConnectionStatus.disconnected);
  });

  test('adapter registry requires every platform', () {
    expect(() => AdapterRegistry([MockPlatformAdapter(MessagingPlatform.rubika)]),
        throwsA(isA<ArgumentError>()));
  });
}

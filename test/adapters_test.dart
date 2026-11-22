import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tesla_org/integrations/common/mock_adapter.dart';
import 'package:tesla_org/integrations/common/platform_adapter.dart';
import 'package:tesla_org/integrations/common/real_adapters.dart';
import 'package:tesla_org/shared/enums/enums.dart';

typedef Call = ({String method, Uri url, Map<String, String> headers, Map<String, Object?>? body});

class FakeTransport implements HttpTransport {
  final List<HttpResult> responses = [];
  final List<Call> calls = [];
  Object? error;

  @override
  Future<HttpResult> send(String method, Uri url,
      {Map<String, String> headers = const {}, Map<String, Object?>? body}) async {
    calls.add((method: method, url: url, headers: headers, body: body));
    if (error != null) throw error!;
    return responses.removeAt(0);
  }
}

void main() {
  late FakeTransport http;
  setUp(() => http = FakeTransport());

  group('Telegram Bot API adapter', () {
    late TelegramAdapter tg;
    const creds = AccountCredentials({'bot_token': '123456789:SECRETSECRETSECRETSECRETSECRETSEC'});
    setUp(() => tg = TelegramAdapter(http));

    SendRequest req(String dest, [String text = 'hello']) => SendRequest(
        accountIdentifier: '@my_bot', credentials: creds, destinationId: dest, text: text);

    test('connect succeeds only when getMe is ok and the username matches', () async {
      http.responses.add(const HttpResult(200, {'ok': true, 'result': {'username': 'My_Bot', 'first_name': 'Bot'}}));
      final r = await tg.connect(accountIdentifier: '@my_bot', credentials: creds);
      expect(r.status, ConnectionStatus.connected);
      expect(r.displayName, 'Bot');
      expect(http.calls.single.method, 'GET');
      expect(http.calls.single.url.path.endsWith('/getMe'), isTrue);

      http.responses.add(const HttpResult(200, {'ok': true, 'result': {'username': 'other_bot'}}));
      final mismatch = await tg.connect(accountIdentifier: '@my_bot', credentials: creds);
      expect(mismatch.status, ConnectionStatus.error);
      expect(mismatch.errorCode, 'IDENTIFIER_MISMATCH');
    });

    test('connect maps 401, 429 and network errors honestly', () async {
      http.responses.add(const HttpResult(401, {'ok': false}));
      expect((await tg.connect(accountIdentifier: '@my_bot', credentials: creds)).status,
          ConnectionStatus.authenticationRequired);
      http.responses.add(const HttpResult(429, {'ok': false}));
      expect((await tg.connect(accountIdentifier: '@my_bot', credentials: creds)).status,
          ConnectionStatus.rateLimited);
      http.error = TimeoutException('x');
      final net = await tg.connect(accountIdentifier: '@my_bot', credentials: creds);
      expect(net.status, ConnectionStatus.error);
      expect(net.errorCode, 'NETWORK');
      expect((await tg.connect(accountIdentifier: '@my_bot', credentials: const AccountCredentials({}))).status,
          ConnectionStatus.authenticationRequired);
    });

    test('sendText: success, numeric chat ids, rate limit with retry_after, rejection, server error', () async {
      http.responses.add(const HttpResult(200, {'ok': true, 'result': {'message_id': 42}}));
      final ok = await tg.sendText(req('123456'));
      expect(ok.outcome, SendOutcome.sent);
      expect(ok.messageId, '42');
      expect(http.calls.last.body!['chat_id'], 123456);
      expect(http.calls.last.body!['text'], 'hello');

      http.responses.add(const HttpResult(429, {'ok': false, 'parameters': {'retry_after': 7}}));
      final limited = await tg.sendText(req('@somechannel'));
      expect(limited.outcome, SendOutcome.rateLimited);
      expect(limited.retryAfter, const Duration(seconds: 7));
      expect(http.calls.last.body!['chat_id'], '@somechannel');

      http.responses.add(const HttpResult(403, {'ok': false, 'description': 'Forbidden: bot was blocked by the user'}));
      final blocked = await tg.sendText(req('123456'));
      expect(blocked.outcome, SendOutcome.rejected);
      expect(blocked.errorCode, 'TG_403');

      http.responses.add(const HttpResult(502, null));
      expect((await tg.sendText(req('123456'))).outcome, SendOutcome.retryable);
      http.responses.add(const HttpResult(401, {'ok': false}));
      expect((await tg.sendText(req('123456'))).outcome, SendOutcome.authFailed);
    });

    test('sendText refuses over-long text without calling the API', () async {
      final r = await tg.sendText(req('123456', 'x' * 4097));
      expect(r.outcome, SendOutcome.rejected);
      expect(r.errorCode, 'TEXT_TOO_LONG');
      expect(http.calls, isEmpty);
    });

    test('group links: public username verified via getChat; private invites never verified', () async {
      http.responses.add(const HttpResult(200, {'ok': true, 'result': {'title': 'Devs'}}));
      final ok = await tg.checkGroupLink(credentials: creds, url: 'https://t.me/devs_chat');
      expect(ok.status, ValidationStatus.verified);
      expect(ok.title, 'Devs');
      expect(http.calls.single.body!['chat_id'], '@devs_chat');

      final calls = http.calls.length;
      final invite = await tg.checkGroupLink(credentials: creds, url: 'https://t.me/+AbCdEf');
      expect(invite.status, ValidationStatus.authorizationUnavailable);
      expect(http.calls.length, calls); // no request made

      http.responses.add(const HttpResult(400, {'ok': false}));
      expect((await tg.checkGroupLink(credentials: creds, url: 'https://t.me/nope_group')).status,
          ValidationStatus.inaccessible);
      expect((await tg.checkGroupLink(credentials: creds, url: 'https://example.com/x')).status,
          ValidationStatus.invalidFormat);
    });

    test('capabilities are honest', () {
      expect(tg.capabilities.overall, IntegrationStatus.partiallySupported);
      expect(tg.capabilities.items['delivery_status'], IntegrationStatus.unsupported);
      expect(tg.capabilities.items['production_readiness'], IntegrationStatus.notVerified);
      expect(tg.capabilities.minIntervalSeconds, 3);
      expect(tg.capabilities.items.keys.toSet(), AdapterCapabilities.keys.toSet());
    });
  });

  group('WhatsApp Cloud API adapter', () {
    late WhatsAppAdapter wa;
    final creds = AccountCredentials({'access_token': 'EAAB${'x' * 30}'});
    setUp(() => wa = WhatsAppAdapter(http));

    SendRequest req(String to, {String? template, String? lang}) => SendRequest(
        accountIdentifier: '109876543210987',
        credentials: creds,
        destinationId: to,
        text: 'hello',
        templateName: template,
        templateLanguage: lang);

    test('connect uses the Graph API with a bearer token', () async {
      http.responses.add(const HttpResult(200, {'verified_name': 'My Shop', 'display_phone_number': '+1 555'}));
      final r = await wa.connect(accountIdentifier: '109876543210987', credentials: creds);
      expect(r.status, ConnectionStatus.connected);
      expect(r.displayName, 'My Shop');
      final c = http.calls.single;
      expect(c.url.host, 'graph.facebook.com');
      expect(c.url.path, '/${WhatsAppAdapter.graphVersion}/109876543210987');
      expect(c.headers['Authorization'], startsWith('Bearer '));
    });

    test('connect: expired token and rate limits', () async {
      http.responses.add(const HttpResult(400, {'error': {'code': 190}}));
      expect((await wa.connect(accountIdentifier: '1', credentials: creds)).status,
          ConnectionStatus.credentialsExpired);
      http.responses.add(const HttpResult(429, {'error': {'code': 130429}}));
      expect((await wa.connect(accountIdentifier: '1', credentials: creds)).status,
          ConnectionStatus.rateLimited);
    });

    test('sendText: text, template, validation and error mapping', () async {
      http.responses.add(const HttpResult(200, {'messages': [{'id': 'wamid.X'}]}));
      final ok = await wa.sendText(req('+491701234567'));
      expect(ok.outcome, SendOutcome.sent);
      expect(ok.messageId, 'wamid.X');
      expect(http.calls.last.url.path, '/${WhatsAppAdapter.graphVersion}/109876543210987/messages');
      expect(http.calls.last.body!['type'], 'text');
      expect(http.calls.last.body!['to'], '+491701234567');

      http.responses.add(const HttpResult(200, {'messages': [{'id': 'wamid.Y'}]}));
      await wa.sendText(req('+491701234567', template: 'order_update', lang: 'de'));
      final body = http.calls.last.body!;
      expect(body['type'], 'template');
      expect((body['template'] as Map)['name'], 'order_update');
      expect(((body['template'] as Map)['language'] as Map)['code'], 'de');

      final calls = http.calls.length;
      final bad = await wa.sendText(req('0170 123'));
      expect(bad.errorCode, 'WA_BAD_NUMBER');
      expect(http.calls.length, calls);

      http.responses.add(const HttpResult(400, {'error': {'code': 131047, 'message': 'Re-engagement message'}}));
      final outside = await wa.sendText(req('+491701234567'));
      expect(outside.outcome, SendOutcome.rejected);
      expect(outside.errorCode, 'WA_131047');

      http.responses.add(const HttpResult(429, {'error': {'code': 130429}}));
      expect((await wa.sendText(req('+491701234567'))).outcome, SendOutcome.rateLimited);
      http.responses.add(const HttpResult(401, {'error': {'code': 190}}));
      expect((await wa.sendText(req('+491701234567'))).outcome, SendOutcome.authFailed);
      http.responses.add(const HttpResult(503, null));
      expect((await wa.sendText(req('+491701234567'))).outcome, SendOutcome.retryable);
    });

    test('capabilities: no delivery status, approval required', () {
      expect(wa.capabilities.items['delivery_status'], IntegrationStatus.unsupported);
      expect(wa.capabilities.items['production_readiness'], IntegrationStatus.requiresApproval);
      expect(wa.capabilities.items['group_messaging'], IntegrationStatus.unsupported);
    });
  });

  test('mock adapter never claims success', () async {
    final m = MockPlatformAdapter(MessagingPlatform.rubika);
    expect(m.mode, AdapterMode.mock);
    expect(m.capabilities.overall, IntegrationStatus.mockOnly);
    final r = await m.sendText(const SendRequest(
        accountIdentifier: 'x', credentials: AccountCredentials({}), destinationId: 'y', text: 'z'));
    expect(r.outcome, SendOutcome.simulated);
    expect((await m.connect(accountIdentifier: 'x', credentials: const AccountCredentials({}))).status,
        ConnectionStatus.mockConnection);
  });

  test('the real transport refuses non-HTTPS URLs', () async {
    await expectLater(DartIoTransport().send('GET', Uri.parse('http://example.com')), throwsArgumentError);
  });
}

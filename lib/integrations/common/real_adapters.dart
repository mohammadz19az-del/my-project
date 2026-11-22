import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../shared/enums/enums.dart';
import 'platform_adapter.dart';

// ---------------------------------------------------------------- HTTP layer

class HttpResult {
  const HttpResult(this.status, this.json);

  final int status;
  final Map<String, dynamic>? json;
}

/// Minimal HTTPS client. Replaceable in tests. It never logs URLs or bodies
/// (a Telegram URL contains the bot token).
abstract class HttpTransport {
  Future<HttpResult> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
  });
}

/// `dart:io` transport: HTTPS only, default (verifying) TLS, hard timeouts.
class DartIoTransport implements HttpTransport {
  DartIoTransport({this.timeout = const Duration(seconds: 20)});

  final Duration timeout;

  @override
  Future<HttpResult> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
  }) async {
    if (url.scheme != 'https') throw ArgumentError('HTTPS is required.');
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, url).timeout(timeout);
      request.headers.contentType = ContentType.json;
      for (final e in headers.entries) {
        request.headers.set(e.key, e.value);
      }
      if (body != null) request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join().timeout(timeout);
      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {}
      return HttpResult(response.statusCode, json);
    } finally {
      client.close(force: true);
    }
  }
}

// ------------------------------------------------------------------ Telegram

/// Official Telegram **Bot API** (https://core.telegram.org/bots/api).
/// Bots only: personal accounts are not supported and never will be.
/// Limits honoured by the campaign engine: ~1 msg/s per chat, 20 msg/min per
/// group (min interval 3 s), `429 retry_after`. A bot cannot start a
/// conversation, so a destination must have messaged/added the bot first.
class TelegramAdapter implements PlatformAdapter {
  TelegramAdapter(this._http, {String baseUrl = 'https://api.telegram.org'}) : _base = baseUrl;

  final HttpTransport _http;
  final String _base;

  @override
  MessagingPlatform get platform => MessagingPlatform.telegram;

  @override
  AdapterMode get mode => AdapterMode.real;

  @override
  AdapterCapabilities get capabilities => const AdapterCapabilities(
        overall: IntegrationStatus.partiallySupported,
        minIntervalSeconds: 3,
        items: {
          'api_availability': IntegrationStatus.supported,
          'authentication': IntegrationStatus.supported,
          'account_connection': IntegrationStatus.supported,
          'text_messaging': IntegrationStatus.supported,
          'group_messaging': IntegrationStatus.partiallySupported,
          'destination_discovery': IntegrationStatus.unsupported,
          'delivery_status': IntegrationStatus.unsupported,
          'link_validation': IntegrationStatus.partiallySupported,
          'rate_limit_handling': IntegrationStatus.supported,
          // Code written against the documented API; not yet exercised with a live bot.
          'production_readiness': IntegrationStatus.notVerified,
        },
      );

  Uri _uri(String token, String method) => Uri.parse('$_base/bot$token/$method');

  static String? _token(AccountCredentials c) {
    final t = c['bot_token'];
    return (t == null || t.isEmpty) ? null : t;
  }

  @override
  Future<ConnectResult> connect({
    required String accountIdentifier,
    required AccountCredentials credentials,
  }) async {
    final token = _token(credentials);
    if (token == null) {
      return const ConnectResult(ConnectionStatus.authenticationRequired,
          errorCode: 'CREDENTIALS_MISSING');
    }
    try {
      final r = await _http.send('GET', _uri(token, 'getMe'));
      if (r.status == 200 && r.json?['ok'] == true) {
        final result = r.json!['result'];
        final info = result is Map ? result : const {};
        final username = info['username'];
        if (username is String &&
            '@${username.toLowerCase()}' != accountIdentifier.toLowerCase()) {
          return const ConnectResult(ConnectionStatus.error, errorCode: 'IDENTIFIER_MISMATCH');
        }
        final name = info['first_name'];
        return ConnectResult(ConnectionStatus.connected, displayName: name is String ? name : null);
      }
      if (r.status == 401) {
        return const ConnectResult(ConnectionStatus.authenticationRequired, errorCode: 'TG_401');
      }
      if (r.status == 429) {
        return const ConnectResult(ConnectionStatus.rateLimited, errorCode: 'TG_429');
      }
      return ConnectResult(ConnectionStatus.error, errorCode: 'TG_${r.status}');
    } on Object {
      return const ConnectResult(ConnectionStatus.error, errorCode: 'NETWORK');
    }
  }

  @override
  Future<void> disconnect({required String accountIdentifier}) async {} // stateless API

  @override
  Future<SendResult> sendText(SendRequest request) async {
    final token = _token(request.credentials);
    if (token == null) return const SendResult(SendOutcome.authFailed, errorCode: 'CREDENTIALS_MISSING');
    if (request.text.length > capabilities.maxTextLength) {
      return const SendResult(SendOutcome.rejected, errorCode: 'TEXT_TOO_LONG');
    }
    final HttpResult r;
    try {
      r = await _http.send('POST', _uri(token, 'sendMessage'), body: {
        'chat_id': int.tryParse(request.destinationId) ?? request.destinationId,
        'text': request.text,
      });
    } on Object {
      return const SendResult(SendOutcome.retryable, errorCode: 'NETWORK');
    }
    if (r.status == 200 && r.json?['ok'] == true) {
      final result = r.json!['result'];
      final id = result is Map ? result['message_id'] : null;
      return SendResult(SendOutcome.sent, messageId: id?.toString());
    }
    if (r.status == 429) {
      final params = r.json?['parameters'];
      final wait = params is Map ? params['retry_after'] : null;
      return SendResult(SendOutcome.rateLimited,
          errorCode: 'TG_429', retryAfter: Duration(seconds: wait is int ? wait : 30));
    }
    if (r.status == 401) return const SendResult(SendOutcome.authFailed, errorCode: 'TG_401');
    if (r.status >= 500) return SendResult(SendOutcome.retryable, errorCode: 'TG_${r.status}');
    final description = r.json?['description'];
    return SendResult(SendOutcome.rejected,
        errorCode: 'TG_${r.status}', errorMessage: description is String ? description : null);
  }

  @override
  Future<GroupCheck> checkGroupLink({
    required AccountCredentials credentials,
    required String url,
  }) async {
    final token = _token(credentials);
    final uri = Uri.tryParse(url.trim());
    if (token == null || uri == null) return const GroupCheck(ValidationStatus.authorizationUnavailable);
    const hosts = {'t.me', 'telegram.me', 'telegram.dog'};
    final host = uri.host.toLowerCase().replaceFirst('www.', '');
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (!hosts.contains(host) || segments.isEmpty) {
      return const GroupCheck(ValidationStatus.invalidFormat);
    }
    final first = segments.first;
    // Private invite links cannot be resolved by the Bot API.
    if (first.startsWith('+') || first == 'joinchat') {
      return const GroupCheck(ValidationStatus.authorizationUnavailable);
    }
    try {
      final r = await _http.send('POST', _uri(token, 'getChat'), body: {'chat_id': '@$first'});
      if (r.status == 200 && r.json?['ok'] == true) {
        final result = r.json!['result'];
        final info = result is Map ? result : const {};
        final title = info['title'] ?? info['first_name'];
        return GroupCheck(ValidationStatus.verified, title: title is String ? title : null);
      }
      if (r.status == 400 || r.status == 403) return const GroupCheck(ValidationStatus.inaccessible);
      if (r.status == 401) return const GroupCheck(ValidationStatus.authorizationUnavailable);
      return const GroupCheck(ValidationStatus.unknown);
    } on Object {
      return const GroupCheck(ValidationStatus.unknown);
    }
  }
}

// ------------------------------------------------------------------ WhatsApp

/// Official **WhatsApp Business Cloud API** (Meta Graph API).
/// * Needs a Business phone-number ID and an access token (manual Meta onboarding).
/// * Free text is accepted only inside the 24-hour customer-service window;
///   business-initiated messages must use a Meta-approved template.
/// * Delivery/read receipts arrive via webhooks, which a desktop/phone app cannot
///   receive, so the status stops at "sent" (accepted by the API).
/// * Recipients must have opted in. Numbers must be E.164 with a leading '+'.
class WhatsAppAdapter implements PlatformAdapter {
  WhatsAppAdapter(this._http);

  /// Update when Meta retires a Graph API version.
  static const String graphVersion = 'v25.0';
  static final RegExp _e164 = RegExp(r'^\+\d{7,15}$');

  final HttpTransport _http;

  @override
  MessagingPlatform get platform => MessagingPlatform.whatsapp;

  @override
  AdapterMode get mode => AdapterMode.real;

  @override
  AdapterCapabilities get capabilities => const AdapterCapabilities(
        overall: IntegrationStatus.partiallySupported,
        items: {
          'api_availability': IntegrationStatus.supported,
          'authentication': IntegrationStatus.requiresApproval,
          'account_connection': IntegrationStatus.supported,
          'text_messaging': IntegrationStatus.partiallySupported,
          'group_messaging': IntegrationStatus.unsupported,
          'destination_discovery': IntegrationStatus.unsupported,
          'delivery_status': IntegrationStatus.unsupported,
          'link_validation': IntegrationStatus.unsupported,
          'rate_limit_handling': IntegrationStatus.partiallySupported,
          'production_readiness': IntegrationStatus.requiresApproval,
        },
      );

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.https('graph.facebook.com', '/$graphVersion/$path', query);

  static Map<String, String> _auth(String token) => {'Authorization': 'Bearer $token'};

  static String? _token(AccountCredentials c) {
    final t = c['access_token'];
    return (t == null || t.isEmpty) ? null : t;
  }

  static int? _errorCode(HttpResult r) {
    final e = r.json?['error'];
    final code = e is Map ? e['code'] : null;
    return code is int ? code : null;
  }

  @override
  Future<ConnectResult> connect({
    required String accountIdentifier,
    required AccountCredentials credentials,
  }) async {
    final token = _token(credentials);
    if (token == null) {
      return const ConnectResult(ConnectionStatus.authenticationRequired,
          errorCode: 'CREDENTIALS_MISSING');
    }
    try {
      final r = await _http.send(
        'GET',
        _uri(accountIdentifier, {'fields': 'verified_name,display_phone_number'}),
        headers: _auth(token),
      );
      if (r.status == 200 && r.json != null && r.json!['error'] == null) {
        final name = r.json!['verified_name'];
        return ConnectResult(ConnectionStatus.connected, displayName: name is String ? name : null);
      }
      final code = _errorCode(r);
      if (r.status == 401 || code == 190) {
        return ConnectResult(ConnectionStatus.credentialsExpired, errorCode: 'WA_${code ?? 401}');
      }
      if (r.status == 429 || code == 130429) {
        return const ConnectResult(ConnectionStatus.rateLimited, errorCode: 'WA_429');
      }
      return ConnectResult(ConnectionStatus.error, errorCode: 'WA_${code ?? r.status}');
    } on Object {
      return const ConnectResult(ConnectionStatus.error, errorCode: 'NETWORK');
    }
  }

  @override
  Future<void> disconnect({required String accountIdentifier}) async {}

  @override
  Future<SendResult> sendText(SendRequest request) async {
    final token = _token(request.credentials);
    if (token == null) return const SendResult(SendOutcome.authFailed, errorCode: 'CREDENTIALS_MISSING');
    if (!_e164.hasMatch(request.destinationId)) {
      return const SendResult(SendOutcome.rejected, errorCode: 'WA_BAD_NUMBER');
    }
    final Map<String, Object?> body;
    if (request.templateName != null && request.templateName!.isNotEmpty) {
      body = {
        'messaging_product': 'whatsapp',
        'recipient_type': 'individual',
        'to': request.destinationId,
        'type': 'template',
        'template': {
          'name': request.templateName,
          'language': {'code': request.templateLanguage ?? 'en_US'},
        },
      };
    } else {
      if (request.text.length > capabilities.maxTextLength) {
        return const SendResult(SendOutcome.rejected, errorCode: 'TEXT_TOO_LONG');
      }
      body = {
        'messaging_product': 'whatsapp',
        'recipient_type': 'individual',
        'to': request.destinationId,
        'type': 'text',
        'text': {'body': request.text},
      };
    }
    final HttpResult r;
    try {
      r = await _http.send('POST', _uri('${request.accountIdentifier}/messages'),
          headers: _auth(token), body: body);
    } on Object {
      return const SendResult(SendOutcome.retryable, errorCode: 'NETWORK');
    }
    if (r.status == 200 || r.status == 201) {
      final messages = r.json?['messages'];
      final first = messages is List && messages.isNotEmpty ? messages.first : null;
      final id = first is Map ? first['id'] : null;
      if (id != null) return SendResult(SendOutcome.sent, messageId: id.toString());
    }
    final code = _errorCode(r);
    if (r.status == 401 || code == 190) {
      return SendResult(SendOutcome.authFailed, errorCode: 'WA_${code ?? 401}');
    }
    if (r.status == 429 || code == 130429) {
      return const SendResult(SendOutcome.rateLimited,
          errorCode: 'WA_429', retryAfter: Duration(seconds: 60));
    }
    if (r.status >= 500) return SendResult(SendOutcome.retryable, errorCode: 'WA_${r.status}');
    // 131047 = outside the 24-hour window: a Meta-approved template is required.
    final err = r.json?['error'];
    final message = err is Map ? err['message'] : null;
    return SendResult(SendOutcome.rejected,
        errorCode: 'WA_${code ?? r.status}', errorMessage: message is String ? message : null);
  }

  @override
  Future<GroupCheck> checkGroupLink({
    required AccountCredentials credentials,
    required String url,
  }) async =>
      const GroupCheck(ValidationStatus.authorizationUnavailable);
}

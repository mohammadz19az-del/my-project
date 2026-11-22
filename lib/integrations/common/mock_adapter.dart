import '../../shared/enums/enums.dart';
import 'platform_adapter.dart';

/// SIMULATED integration for platforms without a verified official API
/// (Rubika, Soroush). No network I/O, nothing is ever sent: connecting yields
/// `mockConnection` and every send yields [SendOutcome.simulated], which the
/// campaign engine records as "skipped (simulated)", never as a success.
///
/// Integration point: when official, verifiable API documentation exists, replace
/// this with a real adapter implementing [PlatformAdapter] and register it in
/// `adapterRegistryProvider`. Do not invent endpoints.
class MockPlatformAdapter implements PlatformAdapter {
  MockPlatformAdapter(this.platform);

  @override
  final MessagingPlatform platform;

  @override
  AdapterMode get mode => AdapterMode.mock;

  @override
  AdapterCapabilities get capabilities => const AdapterCapabilities(
        overall: IntegrationStatus.mockOnly,
        items: {
          'api_availability': IntegrationStatus.notVerified,
          'authentication': IntegrationStatus.mockOnly,
          'account_connection': IntegrationStatus.mockOnly,
          'text_messaging': IntegrationStatus.mockOnly,
          'group_messaging': IntegrationStatus.mockOnly,
          'destination_discovery': IntegrationStatus.unsupported,
          'delivery_status': IntegrationStatus.unsupported,
          'link_validation': IntegrationStatus.unsupported,
          'rate_limit_handling': IntegrationStatus.unsupported,
          'production_readiness': IntegrationStatus.unsupported,
        },
      );

  @override
  Future<ConnectResult> connect({
    required String accountIdentifier,
    required AccountCredentials credentials,
  }) async =>
      const ConnectResult(ConnectionStatus.mockConnection);

  @override
  Future<void> disconnect({required String accountIdentifier}) async {}

  @override
  Future<SendResult> sendText(SendRequest request) async =>
      const SendResult(SendOutcome.simulated, errorCode: 'MOCK_NOT_SENT');

  @override
  Future<GroupCheck> checkGroupLink({
    required AccountCredentials credentials,
    required String url,
  }) async =>
      const GroupCheck(ValidationStatus.authorizationUnavailable);
}

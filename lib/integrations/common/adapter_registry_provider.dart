import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/enums/enums.dart';
import 'mock_adapter.dart';
import 'platform_adapter.dart';
import 'real_adapters.dart';

final httpTransportProvider = Provider<HttpTransport>((ref) => DartIoTransport());

/// Telegram (Bot API) and WhatsApp (Cloud API) are real adapters. Rubika and
/// Soroush stay mock-only: no official API has been verified.
final adapterRegistryProvider = Provider<AdapterRegistry>((ref) {
  final http = ref.watch(httpTransportProvider);
  return AdapterRegistry([
    TelegramAdapter(http),
    WhatsAppAdapter(http),
    MockPlatformAdapter(MessagingPlatform.rubika),
    MockPlatformAdapter(MessagingPlatform.soroush),
  ]);
});

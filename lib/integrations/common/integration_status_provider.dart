import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/enums/enums.dart';
import 'adapter_registry_provider.dart';

/// Overall integration status per platform, taken from each adapter's capability
/// matrix (real adapters: partially supported; mock adapters: mock mode only).
final integrationStatusesProvider = Provider<Map<MessagingPlatform, IntegrationStatus>>((ref) {
  final registry = ref.watch(adapterRegistryProvider);
  return {
    for (final p in MessagingPlatform.values) p: registry.forPlatform(p).capabilities.overall,
  };
});

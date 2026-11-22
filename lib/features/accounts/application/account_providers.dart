import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/security/credential_store.dart';
import '../../../integrations/common/adapter_registry_provider.dart';
import '../../../shared/enums/enums.dart';
import '../../../shared/models/account.dart';
import 'account_service.dart';

final credentialStoreProvider = Provider<CredentialStore>((ref) => SecureCredentialStore());

final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(
    accounts: ref.watch(accountRepositoryProvider),
    store: ref.watch(credentialStoreProvider),
    registry: ref.watch(adapterRegistryProvider),
    activity: ref.watch(activityRepositoryProvider),
  ),
);

/// All accounts; refreshed with `ref.invalidate(accountsProvider)`.
final accountsProvider = FutureProvider.autoDispose<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).list(),
);

/// Selected platform tab (null = all).
final accountPlatformFilterProvider = StateProvider<MessagingPlatform?>((ref) => null);

/// Account ids with an operation in flight (disables their buttons).
final busyAccountIdsProvider = StateProvider<Set<int>>((ref) => <int>{});

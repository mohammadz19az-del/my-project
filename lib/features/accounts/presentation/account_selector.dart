import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_destinations.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/state_views.dart';
import '../../../shared/models/account.dart';
import '../application/account_providers.dart';

/// Account chosen on the Messages / Group Links / Campaign screens.
final selectedAccountIdProvider = StateProvider<int?>((ref) => null);

/// Handles loading / error / "no accounts yet" and hands [builder] the selected
/// account together with a ready-made account dropdown.
class AccountScoped extends ConsumerWidget {
  const AccountScoped({super.key, required this.builder});

  final Widget Function(BuildContext context, WidgetRef ref, Account account, Widget selector) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(accountsProvider);
    final selectedId = ref.watch(selectedAccountIdProvider);
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorState(
        message: localizedError(context.strings, e),
        onRetry: () => ref.invalidate(accountsProvider),
      ),
      data: (accounts) {
        if (accounts.isEmpty) {
          return EmptyState(
            icon: Icons.hub_outlined,
            title: context.tr('empty_accounts_title'),
            message: context.tr('need_account_first'),
            actionLabel: context.tr('account_add'),
            onAction: () => context.go(AppDestinations.accounts.path),
          );
        }
        final account = accounts.firstWhere((a) => a.id == selectedId, orElse: () => accounts.first);
        final selector = DropdownButtonFormField<int>(
          value: account.id,
          decoration: InputDecoration(labelText: context.tr('select_account')),
          items: [
            for (final a in accounts)
              DropdownMenuItem(
                value: a.id,
                child: Text('${a.platform.label} · ${a.displayName ?? a.accountIdentifier}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) => ref.read(selectedAccountIdProvider.notifier).state = id,
        );
        return builder(context, ref, account, selector);
      },
    );
  }
}

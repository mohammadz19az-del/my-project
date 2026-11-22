import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/widgets/responsive_wrap.dart';
import '../../../core/widgets/state_views.dart';
import '../../../shared/enums/enums.dart';
import '../../../shared/models/account.dart';
import '../application/account_providers.dart';
import 'account_actions.dart';
import 'account_card.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(accountsProvider);
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorState(
        message: localizedError(context.strings, e),
        onRetry: () => ref.invalidate(accountsProvider),
      ),
      data: (accounts) => _AccountsBody(accounts: accounts),
    );
  }
}

class _AccountsBody extends ConsumerWidget {
  const _AccountsBody({required this.accounts});

  final List<Account> accounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(accountPlatformFilterProvider);
    final busyIds = ref.watch(busyAccountIdsProvider);
    final service = ref.watch(accountServiceProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final counts = {for (final p in MessagingPlatform.values) p: 0};
    for (final a in accounts) {
      counts[a.platform] = counts[a.platform]! + 1;
    }
    const max = AppConstants.maxAccountsPerPlatform;
    final visible = filter == null ? accounts : accounts.where((a) => a.platform == filter).toList();

    // The add button is disabled only when no platform (or the selected one) has room.
    final full = filter == null
        ? counts.values.every((c) => c >= max)
        : counts[filter]! >= max;
    final firstWithRoom = MessagingPlatform.values.firstWhere(
      (p) => counts[p]! < max,
      orElse: () => MessagingPlatform.telegram,
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(accountsProvider);
        await ref.read(accountsProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(wide ? 28 : 16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: Text('${context.tr('accounts_filter_all')} '
                    '${formatNumber(context, accounts.length)}/${formatNumber(context, AppConstants.maxAccountsTotal)}'),
                selected: filter == null,
                onSelected: (_) => ref.read(accountPlatformFilterProvider.notifier).state = null,
              ),
              for (final p in MessagingPlatform.values)
                ChoiceChip(
                  label: Text('${p.label} ${formatNumber(context, counts[p]!)}/${formatNumber(context, max)}'),
                  selected: filter == p,
                  onSelected: (_) => ref.read(accountPlatformFilterProvider.notifier).state = p,
                ),
              Tooltip(
                message: !full
                    ? ''
                    : filter == null
                        ? context.tr('account_limit_all', args: {'max': formatNumber(context, max)})
                        : context.tr('account_limit_reached',
                            args: {'max': formatNumber(context, max), 'platform': filter.label}),
                child: FilledButton.icon(
                  onPressed: full
                      ? null
                      : () => showAccountForm(
                            context,
                            ref,
                            initialPlatform: (filter != null && counts[filter]! < max) ? filter : firstWithRoom,
                          ),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(context.tr('account_add')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (visible.isEmpty)
            EmptyState(
              icon: Icons.hub_outlined,
              title: context.tr(accounts.isEmpty ? 'empty_accounts_title' : 'accounts_empty_filtered_title'),
              message: context.tr('empty_accounts_body'),
              actionLabel: full ? null : context.tr('account_add'),
              onAction: full ? null : () => showAccountForm(context, ref, initialPlatform: filter ?? firstWithRoom),
            )
          else
            ResponsiveWrap(
              minItemWidth: 340,
              children: [
                for (final a in visible)
                  AccountCard(
                    key: ValueKey(a.id),
                    account: a,
                    mode: service.modeFor(a.platform),
                    busy: busyIds.contains(a.id),
                    onPrimary: () {
                      final live = a.connectionStatus == ConnectionStatus.connected ||
                          a.connectionStatus == ConnectionStatus.mockConnection;
                      live ? disconnectAccount(context, ref, a) : connectAccount(context, ref, a);
                    },
                    onMenu: (action) => switch (action) {
                      AccountMenuAction.details => showAccountDetails(context, ref, a),
                      AccountMenuAction.edit => showAccountForm(context, ref, existing: a),
                      AccountMenuAction.delete => deleteAccount(context, ref, a),
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

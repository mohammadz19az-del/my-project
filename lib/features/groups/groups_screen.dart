import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/error_messages.dart';
import '../../core/localization/app_strings.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utilities/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/glow_card.dart';
import '../../core/widgets/responsive_wrap.dart';
import '../../core/widgets/simple_form_dialog.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/status_chip.dart';
import '../../shared/enums/enums.dart';
import '../../shared/models/account.dart';
import '../../shared/models/group_link.dart';
import '../accounts/application/account_providers.dart';
import '../accounts/presentation/account_selector.dart';

final groupLinksProvider = FutureProvider.autoDispose.family<List<GroupLink>, int>(
  (ref, accountId) => ref.watch(groupLinkRepositoryProvider).listForAccount(accountId),
);

Color _statusColor(ValidationStatus s) => switch (s) {
      ValidationStatus.verified => AppColors.emerald,
      ValidationStatus.validFormat => AppColors.cyan,
      ValidationStatus.invalidFormat => AppColors.red,
      ValidationStatus.inaccessible => AppColors.red,
      ValidationStatus.authorizationUnavailable => AppColors.amber,
      ValidationStatus.unknown => Colors.blueGrey,
    };

class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context) => AccountScoped(
        builder: (context, ref, account, selector) => _LinksView(account: account, selector: selector),
      );
}

Future<void> _run(BuildContext context, WidgetRef ref, int accountId, Future<void> Function() action,
    {String? successKey}) async {
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.strings;
  try {
    await action();
    if (successKey != null) messenger.showSnackBar(SnackBar(content: Text(strings.t(successKey))));
  } catch (e, s) {
    AppLogger.error('Group link action failed', error: e.runtimeType, stackTrace: s);
    messenger.showSnackBar(SnackBar(content: Text(localizedError(strings, e))));
  } finally {
    ref.invalidate(groupLinksProvider(accountId));
  }
}

class _LinksView extends ConsumerWidget {
  const _LinksView({required this.account, required this.selector});

  final Account account;
  final Widget selector;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(groupLinksProvider(account.id));
    final wide = MediaQuery.sizeOf(context).width >= 900;
    const max = AppConstants.maxGroupLinksPerAccount;

    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorState(
        message: localizedError(context.strings, e),
        onRetry: () => ref.invalidate(groupLinksProvider(account.id)),
      ),
      data: (links) {
        final full = links.length >= max;
        return ListView(
          padding: EdgeInsets.all(wide ? 28 : 16),
          children: [
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: selector),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip(
                  label: context.tr('links_count', args: {
                    'n': formatNumber(context, links.length),
                    'max': formatNumber(context, max),
                  }),
                  color: full ? AppColors.amber : AppColors.cyan,
                ),
                Tooltip(
                  message: full ? context.tr('links_limit_reached', args: {'max': formatNumber(context, max)}) : '',
                  child: FilledButton.icon(
                    onPressed: full ? null : () => _edit(context, ref, account),
                    icon: const Icon(Icons.add_link),
                    label: Text(context.tr('link_add')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(context.tr('links_note'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            if (links.isEmpty)
              EmptyState(
                icon: Icons.link,
                title: context.tr('links_empty_title'),
                message: context.tr('links_empty_body'),
              )
            else
              ResponsiveWrap(
                minItemWidth: 340,
                children: [for (final l in links) _LinkCard(account: account, link: l)],
              ),
          ],
        );
      },
    );
  }
}

class _LinkCard extends ConsumerWidget {
  const _LinkCard({required this.account, required this.link});

  final Account account;
  final GroupLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.read(groupLinkRepositoryProvider);
    return GlowCard(
      onTap: () => _edit(context, ref, account, existing: link),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(link.title ?? link.url, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
          if (link.title != null)
            Text(link.url, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
          if ((link.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(link.description!, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 10),
          StatusChip(
            label: context.tr('link_status_${link.validationStatus.dbValue}'),
            color: _statusColor(link.validationStatus),
          ),
          const SizedBox(height: 6),
          Text(
            '${context.tr('link_last_verified')}: ${link.lastVerifiedAt == null ? context.tr('account_never') : formatDateTime(context, link.lastVerifiedAt!)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            children: [
              TextButton(
                onPressed: () => _run(context, ref, account.id, () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final strings = context.strings;
                  final check = await ref.read(accountServiceProvider).checkGroupLink(account, link.url);
                  await repo.updateValidation(link.id, check.status);
                  if (check.title != null && link.title == null) {
                    await repo.update(link.id, url: link.url, title: check.title, description: link.description);
                    await repo.updateValidation(link.id, check.status);
                  }
                  final key = check.status == ValidationStatus.authorizationUnavailable
                      ? 'link_verify_unavailable'
                      : 'link_status_${check.status.dbValue}';
                  messenger.showSnackBar(SnackBar(content: Text(strings.t(key))));
                }),
                child: Text(context.tr('link_verify')),
              ),
              TextButton(
                onPressed: () async {
                  // The only supported "joining": the user opens the link in their own app.
                  final ok = await showConfirmDialog(
                    context,
                    title: context.tr('link_open_title'),
                    message: context.tr('link_open_body'),
                    confirmLabel: context.tr('link_copy'),
                  );
                  if (ok && context.mounted) {
                    await Clipboard.setData(ClipboardData(text: link.url));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(context.tr('link_copied'))));
                    }
                  }
                },
                child: Text(context.tr('link_open')),
              ),
              TextButton(
                onPressed: () => _edit(context, ref, account, existing: link),
                child: Text(context.tr('account_edit')),
              ),
              TextButton(
                onPressed: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: context.tr('link_delete_title'),
                    message: context.tr('link_delete_body'),
                    confirmLabel: context.tr('account_delete'),
                    destructive: true,
                  );
                  if (ok && context.mounted) {
                    await _run(context, ref, account.id, () => repo.delete(link.id), successKey: 'link_deleted');
                  }
                },
                child: Text(context.tr('account_delete')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _edit(BuildContext context, WidgetRef ref, Account account, {GroupLink? existing}) async {
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.strings;
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SimpleFormDialog(
      title: context.tr(existing == null ? 'link_add' : 'link_edit'),
      note: context.tr('link_form_note'),
      fields: [
        FormFieldSpec('url',
            label: context.tr('link_url'), initial: existing?.url ?? '', ltr: true, required: true),
        FormFieldSpec('title', label: context.tr('link_title'), initial: existing?.title ?? ''),
        FormFieldSpec('description',
            label: context.tr('link_description'), initial: existing?.description ?? '', maxLines: 3),
      ],
      onSubmit: (v) async {
        final repo = ref.read(groupLinkRepositoryProvider);
        if (existing == null) {
          await repo.create(GroupLinkInput(
              accountId: account.id, url: v['url']!, title: v['title'], description: v['description']));
        } else {
          await repo.update(existing.id, url: v['url']!, title: v['title'], description: v['description']);
        }
      },
    ),
  );
  ref.invalidate(groupLinksProvider(account.id));
  if (saved == true) messenger.showSnackBar(SnackBar(content: Text(strings.t('link_saved'))));
}

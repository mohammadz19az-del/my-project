import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/widgets/glow_card.dart';
import '../../../core/widgets/platform_visuals.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../integrations/common/platform_adapter.dart';
import '../../../shared/enums/enums.dart';
import '../../../shared/models/account.dart';

enum AccountMenuAction { details, edit, delete }

class AccountCard extends StatelessWidget {
  const AccountCard({
    super.key,
    required this.account,
    required this.mode,
    required this.busy,
    required this.onPrimary,
    required this.onMenu,
  });

  final Account account;
  final AdapterMode mode;
  final bool busy;

  /// Connect / reconnect / disconnect, depending on the current status.
  final VoidCallback onPrimary;
  final ValueChanged<AccountMenuAction> onMenu;

  bool get _isLive =>
      account.connectionStatus == ConnectionStatus.connected ||
      account.connectionStatus == ConnectionStatus.mockConnection;

  String _primaryLabelKey() {
    if (_isLive) return 'account_disconnect';
    return account.connectionStatus == ConnectionStatus.disconnected
        ? 'account_connect'
        : 'account_reconnect';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = account.connectionStatus;
    final color = platformColor(account.platform);
    final title = account.displayName ?? account.accountIdentifier;
    final connecting = status == ConnectionStatus.connecting;

    String? notice;
    if (status == ConnectionStatus.mockConnection) {
      notice = context.tr('account_mock_notice');
    } else if (status == ConnectionStatus.unsupported && mode == AdapterMode.pending) {
      notice = context.tr('account_pending_notice');
    } else if (status == ConnectionStatus.authenticationRequired) {
      notice = context.tr('account_credentials_missing_notice');
    }

    String when(DateTime? t) => t == null ? context.tr('account_never') : formatRelative(context, t);

    return GlowCard(
      accent: color,
      onTap: () => onMenu(AccountMenuAction.details),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withAlpha(36),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(platformIcon(account.platform), color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                    Text(
                      account.displayName == null
                          ? account.platform.label
                          : '${account.platform.label} · ${account.accountIdentifier}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<AccountMenuAction>(
                tooltip: context.tr('account_more'),
                onSelected: onMenu,
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                      value: AccountMenuAction.details, child: Text(ctx.tr('account_details'))),
                  PopupMenuItem(value: AccountMenuAction.edit, child: Text(ctx.tr('account_edit'))),
                  PopupMenuItem(
                      value: AccountMenuAction.delete, child: Text(ctx.tr('account_delete'))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StatusChip(
              label: context.tr(connectionStatusKey(status)),
              color: connectionStatusColor(status),
            ),
          ),
          if (notice != null) ...[
            const SizedBox(height: 8),
            Text(notice, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Text('${context.tr('account_last_connection')}: ${when(account.lastConnectedAt)}',
              style: theme.textTheme.bodySmall),
          Text('${context.tr('account_last_activity')}: ${when(account.lastActivityAt)}',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: (busy || connecting) ? null : onPrimary,
                child: (busy || connecting)
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(context.tr(_primaryLabelKey())),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: busy ? null : () => onMenu(AccountMenuAction.edit),
                child: Text(context.tr('account_edit')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

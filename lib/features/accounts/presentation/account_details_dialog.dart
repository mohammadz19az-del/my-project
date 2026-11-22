import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../integrations/common/platform_adapter.dart';
import '../../../shared/models/account.dart';
import '../domain/platform_specs.dart';

/// Read-only account details. Secret values are never shown, only whether they exist.
class AccountDetailsDialog extends StatelessWidget {
  const AccountDetailsDialog({
    super.key,
    required this.account,
    required this.mode,
    required this.hasStoredCredentials,
  });

  final Account account;
  final AdapterMode mode;
  final bool hasStoredCredentials;

  @override
  Widget build(BuildContext context) {
    final spec = PlatformSpecs.of(account.platform);

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 150, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
              Expanded(child: Text(value)),
            ],
          ),
        );

    String when(DateTime? t) => t == null ? context.tr('account_never') : formatDateTime(context, t);

    final credentialText = !spec.requiresCredentials
        ? context.tr('credential_not_required')
        : context.tr(hasStoredCredentials ? 'credential_stored' : 'credential_not_stored');

    return AlertDialog(
      title: Text(account.displayName ?? account.accountIdentifier),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row(context.tr('field_platform'), account.platform.label),
              row(context.tr(spec.identifierLabelKey), account.accountIdentifier),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                        width: 150,
                        child: Text(context.tr('details_status'),
                            style: Theme.of(context).textTheme.bodySmall)),
                    Flexible(
                      child: StatusChip(
                        label: context.tr(connectionStatusKey(account.connectionStatus)),
                        color: connectionStatusColor(account.connectionStatus),
                      ),
                    ),
                  ],
                ),
              ),
              row(context.tr('details_integration'), context.tr('adapter_mode_${mode.name}')),
              row(context.tr('details_credentials'), credentialText),
              row(context.tr('account_last_connection'), when(account.lastConnectedAt)),
              row(context.tr('account_last_activity'), when(account.lastActivityAt)),
              row(context.tr('details_created'), formatDateTime(context, account.createdAt)),
              row(context.tr('details_updated'), formatDateTime(context, account.updatedAt)),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('action_close')),
        ),
      ],
    );
  }
}

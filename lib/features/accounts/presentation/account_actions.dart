import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../integrations/common/platform_adapter.dart';
import '../../../shared/enums/enums.dart';
import '../../../shared/models/account.dart';
import '../application/account_providers.dart';
import '../application/account_service.dart';
import 'account_details_dialog.dart';
import 'account_form_dialog.dart';

/// UI-level orchestration: busy state, error snackbars and list refresh.
/// Success messages are derived from the REAL resulting state, never assumed.

Future<void> _guarded(
  BuildContext context,
  WidgetRef ref,
  int accountId,
  Future<void> Function(AccountService service) action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.strings;
  final busy = ref.read(busyAccountIdsProvider.notifier);
  busy.update((s) => {...s, accountId});
  try {
    await action(ref.read(accountServiceProvider));
  } catch (e, s) {
    AppLogger.error('Account action failed', error: e.runtimeType, stackTrace: s);
    messenger.showSnackBar(SnackBar(content: Text(localizedError(strings, e))));
  } finally {
    busy.update((s) => {...s}..remove(accountId));
    ref.invalidate(accountsProvider);
  }
}

String _connectMessageKey(Account result, AdapterMode mode) {
  switch (result.connectionStatus) {
    case ConnectionStatus.connected:
      return 'connect_result_connected';
    case ConnectionStatus.mockConnection:
      return 'connect_result_mock';
    case ConnectionStatus.unsupported:
      return mode == AdapterMode.pending ? 'account_pending_notice' : 'connection_unsupported';
    case ConnectionStatus.authenticationRequired:
      return 'account_credentials_missing_notice';
    default:
      return connectionStatusKey(result.connectionStatus);
  }
}

Future<void> connectAccount(BuildContext context, WidgetRef ref, Account account) async {
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.strings;
  await _guarded(context, ref, account.id, (service) async {
    final result = await service.connect(account.id);
    messenger.showSnackBar(SnackBar(
      content: Text(strings.t(_connectMessageKey(result, service.modeFor(account.platform)))),
    ));
  });
}

Future<void> disconnectAccount(BuildContext context, WidgetRef ref, Account account) =>
    _guarded(context, ref, account.id, (service) async {
      await service.disconnect(account.id);
    });

Future<void> deleteAccount(BuildContext context, WidgetRef ref, Account account) async {
  final confirmed = await showConfirmDialog(
    context,
    title: context.tr('account_delete_title'),
    message: context.tr('account_delete_body'),
    confirmLabel: context.tr('account_delete'),
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.strings;
  await _guarded(context, ref, account.id, (service) async {
    await service.delete(account.id);
    messenger.showSnackBar(SnackBar(content: Text(strings.t('account_deleted'))));
  });
}

Future<void> showAccountDetails(BuildContext context, WidgetRef ref, Account account) async {
  final service = ref.read(accountServiceProvider);
  var stored = false;
  try {
    stored = await service.hasStoredCredentials(account);
  } catch (_) {
    stored = false;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => AccountDetailsDialog(
      account: account,
      mode: service.modeFor(account.platform),
      hasStoredCredentials: stored,
    ),
  );
}

Future<void> showAccountForm(
  BuildContext context,
  WidgetRef ref, {
  Account? existing,
  MessagingPlatform? initialPlatform,
}) async {
  final service = ref.read(accountServiceProvider);
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.strings;
  var stored = false;
  if (existing != null) {
    try {
      stored = await service.hasStoredCredentials(existing);
    } catch (_) {
      stored = false;
    }
  }
  if (!context.mounted) return;

  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AccountFormDialog(
      existing: existing,
      initialPlatform: initialPlatform,
      hasStoredCredentials: stored,
      onSubmit: (r) async {
        if (existing == null) {
          await service.create(AccountDraft(
            platform: r.platform,
            identifier: r.identifier,
            displayName: r.displayName,
            secrets: r.secrets,
          ));
        } else {
          await service.update(
            existing.id,
            identifier: r.identifier,
            displayName: r.displayName,
            newSecrets: r.secrets,
          );
        }
      },
    ),
  );
  if (saved == true) {
    ref.invalidate(accountsProvider);
    messenger.showSnackBar(SnackBar(content: Text(strings.t('account_saved'))));
  }
}

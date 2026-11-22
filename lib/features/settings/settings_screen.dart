import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/error_messages.dart';
import '../../core/localization/app_strings.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utilities/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/glow_card.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/simple_form_dialog.dart';
import '../../core/widgets/status_chip.dart';
import '../../integrations/common/adapter_registry_provider.dart';
import '../../integrations/common/platform_adapter.dart';
import '../../shared/enums/enums.dart';
import '../accounts/application/account_providers.dart';
import '../accounts/application/account_service.dart';
import '../campaigns/campaigns_screen.dart';
import '../dashboard/application/dashboard_providers.dart';
import '../reports/reports_repository.dart';
import 'application/settings_controller.dart';
import 'backup_service.dart';
import 'domain/app_settings.dart';

final backupListProvider = FutureProvider.autoDispose<List<File>>(
  (ref) => ref.watch(backupServiceProvider).listBackups(),
);

/// Round-trips a probe value to find out whether secure storage works on this device.
final credentialStorageStatusProvider = FutureProvider.autoDispose<bool>((ref) async {
  final store = ref.watch(credentialStoreProvider);
  const probe = 'tesla_org_storage_probe';
  try {
    await store.write(probe, {'k': 'v'});
    final ok = (await store.read(probe))?['k'] == 'v';
    await store.delete(probe);
    return ok;
  } catch (_) {
    return false;
  }
});

void _refreshAll(WidgetRef ref) {
  ref.invalidate(settingsControllerProvider);
  ref.invalidate(accountsProvider);
  ref.invalidate(dashboardProvider);
  ref.invalidate(campaignsProvider);
  ref.invalidate(reportDataProvider);
  ref.invalidate(backupListProvider);
}

Future<void> _guard(BuildContext context, Future<void> Function() action, {String? successKey}) async {
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.strings;
  try {
    await action();
    if (successKey != null) messenger.showSnackBar(SnackBar(content: Text(strings.t(successKey))));
  } catch (e, s) {
    AppLogger.error('Settings action failed', error: e.runtimeType, stackTrace: s);
    messenger.showSnackBar(SnackBar(content: Text(localizedError(strings, e))));
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(title: title),
        GlowCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ]);
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider).valueOrNull ?? const AppSettings();
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final registry = ref.watch(adapterRegistryProvider);
    final storage = ref.watch(credentialStorageStatusProvider);
    final backups = ref.watch(backupListProvider).valueOrNull ?? const <File>[];
    final backup = ref.read(backupServiceProvider);

    return ListView(
      padding: EdgeInsets.all(wide ? 28 : 16),
      children: [
        // ------------------------------------------------------------ appearance
        _Section(title: context.tr('set_appearance'), children: [
          ListTile(
            title: Text(context.tr('set_language')),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'fa', label: Text('فارسی')),
              ],
              selected: {settings.localeCode},
              onSelectionChanged: (s) => _guard(context, () => ctrl.setLocale(s.first)),
            ),
          ),
          ListTile(
            title: Text(context.tr('set_theme')),
            trailing: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_outlined), label: Text(context.tr('theme_dark'))),
                ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode_outlined), label: Text(context.tr('theme_light'))),
                ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.brightness_auto_outlined), label: Text(context.tr('theme_system'))),
              ],
              showSelectedIcon: false,
              selected: {settings.themeMode},
              onSelectionChanged: (s) => _guard(context, () => ctrl.setThemeMode(s.first)),
            ),
          ),
          ListTile(
            title: Text(context.tr('set_accent')),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 12, children: [
                for (final c in AppSettings.accentChoices)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _guard(context, () => ctrl.setAccentColor(c)),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: settings.accentColorValue == c ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          SwitchListTile(
            title: Text(context.tr('set_animations')),
            value: settings.animationsEnabled,
            onChanged: (v) => _guard(context, () => ctrl.setAnimationsEnabled(v)),
          ),
          SwitchListTile(
            title: Text(context.tr('set_reduced_motion')),
            subtitle: Text(context.tr('set_reduced_motion_hint')),
            value: settings.reducedMotion,
            onChanged: (v) => _guard(context, () => ctrl.setReducedMotion(v)),
          ),
        ]),

        // --------------------------------------------------------- notifications
        _Section(title: context.tr('set_notifications'), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(context.tr('notify_note'), style: Theme.of(context).textTheme.bodySmall),
          ),
          SwitchListTile(
            title: Text(context.tr('notify_completion')),
            value: settings.notifyCompletion,
            onChanged: (v) => _guard(context, () => ctrl.setNotify(AppSettings.keyNotifyCompletion, v)),
          ),
          SwitchListTile(
            title: Text(context.tr('notify_errors')),
            value: settings.notifyErrors,
            onChanged: (v) => _guard(context, () => ctrl.setNotify(AppSettings.keyNotifyErrors, v)),
          ),
          SwitchListTile(
            title: Text(context.tr('notify_auth')),
            value: settings.notifyAuth,
            onChanged: (v) => _guard(context, () => ctrl.setNotify(AppSettings.keyNotifyAuth, v)),
          ),
        ]),

        // -------------------------------------------------------------- security
        _Section(title: context.tr('set_security'), children: [
          ListTile(
            title: Text(context.tr('set_credential_storage')),
            subtitle: Text(context.tr('set_credential_storage_hint')),
            trailing: storage.when(
              loading: () => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              error: (_, __) => StatusChip(label: context.tr('storage_unavailable'), color: Colors.red),
              data: (ok) => StatusChip(
                label: context.tr(ok ? 'storage_ok' : 'storage_unavailable'),
                color: ok ? Colors.green : Colors.red,
              ),
            ),
          ),
          ListTile(
            title: Text(context.tr('set_db_note')),
            subtitle: Text(context.tr('set_db_note_body')),
          ),
          ListTile(
            title: Text(context.tr('set_disconnect_all')),
            trailing: OutlinedButton(
              onPressed: () async {
                final ok = await showConfirmDialog(
                  context,
                  title: context.tr('set_disconnect_all'),
                  message: context.tr('set_disconnect_all_body'),
                );
                if (!ok || !context.mounted) return;
                await _guard(context, () async {
                  final service = ref.read(accountServiceProvider);
                  for (final a in await ref.read(accountsProvider.future)) {
                    if (AccountService.isLive(a.connectionStatus)) await service.disconnect(a.id);
                  }
                  _refreshAll(ref);
                }, successKey: 'set_disconnected_all');
              },
              child: Text(context.tr('account_disconnect')),
            ),
          ),
          ListTile(
            title: Text(context.tr('set_clear_data'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            subtitle: Text(context.tr('set_clear_data_body')),
            trailing: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () async {
                final ok = await showConfirmDialog(
                  context,
                  title: context.tr('set_clear_data'),
                  message: context.tr('set_clear_data_confirm'),
                  confirmLabel: context.tr('account_delete'),
                  destructive: true,
                );
                if (!ok || !context.mounted) return;
                await _guard(context, () async {
                  await backup.wipeAll();
                  _refreshAll(ref);
                }, successKey: 'set_cleared');
              },
              child: Text(context.tr('account_delete')),
            ),
          ),
        ]),

        // ------------------------------------------------------- backup / restore
        _Section(title: context.tr('set_backup'), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(context.tr('backup_note'), style: Theme.of(context).textTheme.bodySmall),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                icon: const Icon(Icons.save_alt),
                label: Text(context.tr('backup_create')),
                onPressed: () => _guard(context, () async {
                  final file = await backup.writeBackup();
                  ref.invalidate(backupListProvider);
                  if (!context.mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(ctx.tr('backup_created')),
                      content: SelectableText(file.path, textDirection: TextDirection.ltr),
                      actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.tr('action_close')))],
                    ),
                  );
                }),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: Text(context.tr('backup_copy')),
                onPressed: () => _guard(context, () async {
                  await Clipboard.setData(ClipboardData(text: await backup.createBackupJson()));
                }, successKey: 'backup_copied'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.paste),
                label: Text(context.tr('backup_restore_paste')),
                onPressed: () => showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => SimpleFormDialog(
                    title: context.tr('backup_restore_paste'),
                    note: context.tr('backup_paste_note'),
                    fields: [FormFieldSpec('json', label: 'JSON', maxLines: 10, ltr: true, required: true)],
                    onSubmit: (v) async {
                      await backup.validate(v['json']!); // fail early, inline
                      if (!context.mounted) return;
                      await _confirmRestore(context, ref, () => v['json']!);
                    },
                  ),
                ),
              ),
            ]),
          ),
          if (backups.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(context.tr('backup_list'), style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final f in backups.take(6))
              ListTile(
                dense: true,
                title: Text(f.uri.pathSegments.last, textDirection: TextDirection.ltr),
                subtitle: Text(formatDateTime(context, f.statSync().modified)),
                trailing: TextButton(
                  onPressed: () => _confirmRestore(context, ref, () => backup.readBackup(f)),
                  child: Text(context.tr('backup_restore')),
                ),
              ),
          ],
        ]),

        // ---------------------------------------------------------- integrations
        _Section(title: context.tr('set_integrations'), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(context.tr('integrations_note'), style: Theme.of(context).textTheme.bodySmall),
          ),
          for (final p in MessagingPlatform.values) _IntegrationTile(adapter: registry.forPlatform(p)),
        ]),

        // ------------------------------------------------------------ user guide
        _Section(title: context.tr('set_guide'), children: [
          for (var i = 1; i <= 8; i++)
            ExpansionTile(
              title: Text(context.tr('guide_${i}_title')),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(context.tr('guide_${i}_body'))],
            ),
        ]),

        // ----------------------------------------------------------------- about
        _Section(title: context.tr('set_about'), children: [
          ListTile(title: Text(AppConstants.appName), subtitle: Text(context.tr('about_tagline'))),
          ListTile(
            title: Text(context.tr('about_version')),
            trailing: Text('${AppConstants.appVersion} (${AppConstants.buildNumber})', textDirection: TextDirection.ltr),
          ),
          ListTile(title: Text(context.tr('about_privacy')), subtitle: Text(context.tr('about_privacy_body'))),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }
}

Future<void> _confirmRestore(BuildContext context, WidgetRef ref, FutureOr<String> Function() source) async {
  final ok = await showConfirmDialog(
    context,
    title: context.tr('restore_title'),
    message: context.tr('restore_body'),
    confirmLabel: context.tr('restore_confirm'),
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  await _guard(context, () async {
    await ref.read(backupServiceProvider).restoreFromJson(await source());
    _refreshAll(ref);
  }, successKey: 'restore_done');
}

class _IntegrationTile extends StatelessWidget {
  const _IntegrationTile({required this.adapter});

  final PlatformAdapter adapter;

  @override
  Widget build(BuildContext context) {
    final caps = adapter.capabilities;
    final theme = Theme.of(context);
    return ExpansionTile(
      title: Text(adapter.platform.label),
      subtitle: Text(context.tr('adapter_mode_${adapter.mode.name}')),
      trailing: StatusChip(
        label: context.tr(integrationStatusKey(caps.overall)),
        color: integrationStatusColor(caps.overall),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('platform_note_${adapter.platform.dbValue}'), style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final key in AdapterCapabilities.keys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(context.tr('cap_$key'))),
              StatusChip(
                label: context.tr(integrationStatusKey(caps.items[key] ?? IntegrationStatus.notVerified)),
                color: integrationStatusColor(caps.items[key] ?? IntegrationStatus.notVerified),
              ),
            ]),
          ),
        const SizedBox(height: 6),
        Text(context.tr('cap_min_interval', args: {'s': formatNumber(context, caps.minIntervalSeconds)}),
            style: theme.textTheme.bodySmall),
      ],
    );
  }
}

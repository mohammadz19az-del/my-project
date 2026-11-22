import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/error_messages.dart';
import '../core/localization/app_strings.dart';
import '../core/logging/app_logger.dart';
import '../features/campaigns/campaign_engine.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/domain/app_settings.dart';
import 'app_destinations.dart';

/// Responsive navigation frame: persistent sidebar on wide (desktop) windows,
/// app bar + drawer on compact (phone/tablet portrait) windows.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const double wideBreakpoint = 900;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // In-app notices (no OS notifications): campaign completion, errors, expired credentials.
    ref.listen<AsyncValue<EngineEvent>>(engineEventsProvider, (_, next) {
      final e = next.valueOrNull;
      if (e == null) return;
      final s = ref.read(settingsControllerProvider).valueOrNull ?? const AppSettings();
      final (show, key) = switch (e.type) {
        EngineEventType.completed => (s.notifyCompletion, 'notice_campaign_completed'),
        EngineEventType.failed => (s.notifyErrors, 'notice_campaign_failed'),
        EngineEventType.autoPaused => (s.notifyErrors, 'notice_campaign_paused'),
        EngineEventType.authExpired => (s.notifyAuth, 'notice_auth_expired'),
      };
      if (show) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(key))));
      }
    });
    final index = AppDestinations.indexForLocation(location);
    final destination = AppDestinations.all[index];
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(width: 264, child: _Sidebar(selectedIndex: index)),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  _TopBar(titleKey: destination.labelKey),
                  const Divider(height: 1),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(destination.labelKey)),
        actions: const [_LanguageButton(), _ThemeButton()],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              const _Brand(),
              Expanded(child: _NavList(selectedIndex: index, closeDrawerOnSelect: true)),
            ],
          ),
        ),
      ),
      body: SafeArea(child: child),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        children: [
          Icon(Icons.bolt, color: theme.colorScheme.primary, size: 28),
          const SizedBox(width: 8),
          Text(
            AppConstants.appName.toUpperCase(),
            style: theme.textTheme.titleLarge?.copyWith(
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selectedIndex});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).appBarTheme.backgroundColor ?? Colors.transparent,
      child: Column(
        children: [
          const _Brand(),
          Expanded(child: _NavList(selectedIndex: selectedIndex)),
        ],
      ),
    );
  }
}

class _NavList extends StatelessWidget {
  const _NavList({required this.selectedIndex, this.closeDrawerOnSelect = false});

  final int selectedIndex;
  final bool closeDrawerOnSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        for (var i = 0; i < AppDestinations.all.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ListTile(
              selected: i == selectedIndex,
              leading: Icon(AppDestinations.all[i].icon),
              title: Text(context.tr(AppDestinations.all[i].labelKey)),
              onTap: () {
                if (closeDrawerOnSelect) Navigator.of(context).pop();
                context.go(AppDestinations.all[i].path);
              },
            ),
          ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.titleKey});

  final String titleKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: Theme.of(context).appBarTheme.backgroundColor,
      child: Row(
        children: [
          Text(context.tr(titleKey), style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(),
          const _LanguageButton(),
          const SizedBox(width: 4),
          const _ThemeButton(),
        ],
      ),
    );
  }
}

Future<void> _runSafely(BuildContext context, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.strings;
  try {
    await action();
  } catch (e, s) {
    AppLogger.error('Settings update failed', error: e, stackTrace: s);
    messenger.showSnackBar(SnackBar(content: Text(localizedError(strings, e))));
  }
}

class _LanguageButton extends ConsumerWidget {
  const _LanguageButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(settingsControllerProvider).valueOrNull?.localeCode ?? 'en';
    final next = code == 'en' ? 'fa' : 'en';
    return Tooltip(
      message: context.tr('tooltip_language'),
      child: TextButton.icon(
        icon: const Icon(Icons.translate),
        label: Text(next == 'fa' ? 'فارسی' : 'English'),
        onPressed: () => _runSafely(
          context,
          () => ref.read(settingsControllerProvider.notifier).setLocale(next),
        ),
      ),
    );
  }
}

class _ThemeButton extends ConsumerWidget {
  const _ThemeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsControllerProvider).valueOrNull?.themeMode ?? ThemeMode.dark;
    final (icon, labelKey, next) = switch (mode) {
      ThemeMode.dark => (Icons.dark_mode_outlined, 'theme_dark', ThemeMode.light),
      ThemeMode.light => (Icons.light_mode_outlined, 'theme_light', ThemeMode.system),
      ThemeMode.system => (Icons.brightness_auto_outlined, 'theme_system', ThemeMode.dark),
    };
    return IconButton(
      icon: Icon(icon),
      tooltip: '${context.tr('tooltip_theme')} (${context.tr(labelKey)})',
      onPressed: () => _runSafely(
        context,
        () => ref.read(settingsControllerProvider.notifier).setThemeMode(next),
      ),
    );
  }
}

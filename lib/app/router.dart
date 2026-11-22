import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/localization/app_strings.dart';
import '../features/accounts/presentation/accounts_screen.dart';
import '../features/campaigns/campaigns_screen.dart';
import '../features/groups/groups_screen.dart';
import '../features/messages/messages_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/settings/application/settings_controller.dart';
import 'app_destinations.dart';
import 'app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  bool shouldAnimate() =>
      ref.read(settingsControllerProvider).valueOrNull?.shouldAnimate ?? true;

  final router = GoRouter(
    initialLocation: AppDestinations.dashboard.path,
    routes: [
      GoRoute(path: '/', redirect: (_, __) => AppDestinations.dashboard.path),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          for (final d in AppDestinations.all)
            GoRoute(
              path: d.path,
              pageBuilder: (context, state) => _page(
                state,
                _screenFor(d),
                shouldAnimate(),
              ),
            ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text(context.tr('page_not_found'))),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});

Page<void> _page(GoRouterState state, Widget child, bool animate) {
  if (!animate) return NoTransitionPage<void>(key: state.pageKey, child: child);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondary, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

Widget _screenFor(AppDestination d) {
  if (d == AppDestinations.dashboard) return const DashboardScreen();
  if (d == AppDestinations.accounts) return const AccountsScreen();
  if (d == AppDestinations.messages) return const MessagesScreen();
  if (d == AppDestinations.groups) return const GroupsScreen();
  if (d == AppDestinations.campaigns) return const CampaignsScreen();
  if (d == AppDestinations.reports) return const ReportsScreen();
  return const SettingsScreen();
}

import 'package:flutter/material.dart';

/// A top-level navigation destination. [phase] is the development phase in
/// which the real screen is scheduled (see docs/GENERATION_PROGRESS.md).
class AppDestination {
  const AppDestination({
    required this.path,
    required this.labelKey,
    required this.icon,
    required this.phase,
  });

  final String path;
  final String labelKey;
  final IconData icon;
  final int phase;
}

abstract final class AppDestinations {
  static const dashboard = AppDestination(
    path: '/dashboard',
    labelKey: 'nav_dashboard',
    icon: Icons.space_dashboard_outlined,
    phase: 4,
  );
  static const accounts = AppDestination(
    path: '/accounts',
    labelKey: 'nav_accounts',
    icon: Icons.person_add_alt_1_outlined,
    phase: 5,
  );
  static const messages = AppDestination(
    path: '/messages',
    labelKey: 'nav_messages',
    icon: Icons.chat_bubble_outline,
    phase: 7,
  );
  static const groups = AppDestination(
    path: '/groups',
    labelKey: 'nav_groups',
    icon: Icons.link,
    phase: 8,
  );
  static const campaigns = AppDestination(
    path: '/campaigns',
    labelKey: 'nav_campaigns',
    icon: Icons.campaign_outlined,
    phase: 9,
  );
  static const reports = AppDestination(
    path: '/reports',
    labelKey: 'nav_reports',
    icon: Icons.insights_outlined,
    phase: 11,
  );
  static const settings = AppDestination(
    path: '/settings',
    labelKey: 'nav_settings',
    icon: Icons.settings_outlined,
    phase: 10,
  );

  static const List<AppDestination> all = [
    dashboard,
    accounts,
    messages,
    groups,
    campaigns,
    reports,
    settings,
  ];

  static int indexForLocation(String location) {
    for (var i = 0; i < all.length; i++) {
      final path = all[i].path;
      if (location == path || location.startsWith('$path/')) return i;
    }
    return 0;
  }
}

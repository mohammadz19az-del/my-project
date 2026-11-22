import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_data.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => SqliteDashboardRepository(ref.watch(appDatabaseProvider).db),
);

/// Loads fresh data whenever the dashboard is opened; `ref.invalidate` refreshes.
final dashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) async {
  final stats = await ref.watch(dashboardRepositoryProvider).loadStats();
  final events = await ref.watch(activityRepositoryProvider).recent(limit: 8);
  return DashboardData(stats: stats, recentEvents: events, loadedAt: DateTime.now());
});

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_destinations.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/widgets/glow_card.dart';
import '../../../core/widgets/responsive_wrap.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../integrations/common/integration_status_provider.dart';
import '../../../shared/enums/enums.dart';
import '../application/dashboard_providers.dart';
import '../domain/dashboard_data.dart';
import 'platform_status_card.dart';
import 'recent_activity_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (error, _) => ErrorState(
        message: localizedError(context.strings, error),
        onRetry: () => ref.invalidate(dashboardProvider),
      ),
      data: (data) => _DashboardBody(data: data, refreshing: async.isLoading),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.data, required this.refreshing});

  final DashboardData data;
  final bool refreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = data.stats;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final integration = ref.watch(integrationStatusesProvider);

    String t(String key) => context.tr(key);
    void go(AppDestination d) => context.go(d.path);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardProvider);
        await ref.read(dashboardProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(wide ? 28 : 16),
        children: [
          // ---- header: last updated + manual refresh
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('dash_last_updated',
                      args: {'time': formatRelative(context, data.loadedAt)}),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (refreshing)
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 8),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              TextButton.icon(
                onPressed: refreshing ? null : () => ref.invalidate(dashboardProvider),
                icon: const Icon(Icons.refresh),
                label: Text(t('dash_refresh')),
              ),
            ],
          ),

          // ---- quick actions
          SectionHeader(title: t('dash_quick_actions')),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => go(AppDestinations.accounts),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(t('qa_add_account')),
              ),
              FilledButton.tonalIcon(
                onPressed: () => go(AppDestinations.messages),
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(t('qa_new_message')),
              ),
              FilledButton.tonalIcon(
                onPressed: () => go(AppDestinations.groups),
                icon: const Icon(Icons.link),
                label: Text(t('qa_group_links')),
              ),
              FilledButton.tonalIcon(
                onPressed: () => go(AppDestinations.campaigns),
                icon: const Icon(Icons.campaign_outlined),
                label: Text(t('qa_new_campaign')),
              ),
              FilledButton.tonalIcon(
                onPressed: () => go(AppDestinations.reports),
                icon: const Icon(Icons.insights_outlined),
                label: Text(t('qa_reports')),
              ),
            ],
          ),

          // ---- first-run empty state
          if (!s.hasAnyAccounts) ...[
            const SizedBox(height: 24),
            GlowCard(
              child: EmptyState(
                icon: Icons.hub_outlined,
                title: t('empty_accounts_title'),
                message: t('empty_accounts_body'),
                actionLabel: t('qa_add_account'),
                onAction: () => go(AppDestinations.accounts),
              ),
            ),
          ],

          // ---- overview numbers
          SectionHeader(title: t('dash_overview')),
          ResponsiveWrap(
            minItemWidth: 230,
            children: [
              StatCard(
                icon: Icons.groups_2_outlined,
                label: t('stat_total_accounts'),
                value: s.totalAccounts,
                accent: AppColors.cyan,
                onTap: () => go(AppDestinations.accounts),
              ),
              StatCard(
                icon: Icons.link_rounded,
                label: t('stat_connected'),
                value: s.connectedAccounts,
                accent: AppColors.emerald,
              ),
              StatCard(
                icon: Icons.link_off_rounded,
                label: t('stat_disconnected'),
                value: s.disconnectedAccounts,
                accent: AppColors.blue,
              ),
              StatCard(
                icon: Icons.report_gmailerrorred_outlined,
                label: t('stat_other_states'),
                value: s.otherStateAccounts,
                accent: AppColors.amber,
              ),
              StatCard(
                icon: Icons.chat_bubble_outline,
                label: t('stat_templates'),
                value: s.totalTemplates,
                accent: AppColors.violet,
                onTap: () => go(AppDestinations.messages),
              ),
              StatCard(
                icon: Icons.play_circle_outline,
                label: t('stat_active_campaigns'),
                value: s.activeCampaigns,
                accent: AppColors.cyan,
                onTap: () => go(AppDestinations.campaigns),
              ),
              StatCard(
                icon: Icons.task_alt_outlined,
                label: t('stat_completed_campaigns'),
                value: s.completedCampaigns,
                accent: AppColors.emerald,
              ),
              StatCard(
                icon: Icons.mark_email_read_outlined,
                label: t('stat_successful_deliveries'),
                value: s.successfulDeliveries,
                accent: AppColors.emerald,
                onTap: () => go(AppDestinations.reports),
              ),
              StatCard(
                icon: Icons.cancel_outlined,
                label: t('stat_failed_deliveries'),
                value: s.failedDeliveries,
                accent: AppColors.red,
                onTap: () => go(AppDestinations.reports),
              ),
            ],
          ),

          // ---- platforms + integration status
          SectionHeader(title: t('dash_platforms')),
          ResponsiveWrap(
            minItemWidth: 270,
            children: [
              for (final p in MessagingPlatform.values)
                PlatformStatusCard(
                  stats: s.platforms[p]!,
                  integration: integration[p] ?? IntegrationStatus.notVerified,
                ),
            ],
          ),

          // ---- recent activity
          SectionHeader(
            title: t('dash_recent'),
            trailing: TextButton(
              onPressed: () => go(AppDestinations.reports),
              child: Text(t('dash_view_all')),
            ),
          ),
          RecentActivityCard(events: data.recentEvents),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/localization/app_strings.dart';
import '../../core/storage/app_files.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utilities/formatters.dart';
import '../../core/widgets/glow_card.dart';
import '../../core/widgets/platform_visuals.dart';
import '../../core/widgets/responsive_wrap.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/status_chip.dart';
import '../../shared/enums/enums.dart';
import '../accounts/application/account_providers.dart';
import '../campaigns/campaigns_screen.dart';
import 'reports_repository.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _view = 0; // 0 campaigns, 1 deliveries, 2 activity

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(reportDataProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorState(
        message: localizedError(context.strings, e),
        onRetry: () => ref.invalidate(reportDataProvider),
      ),
      data: (d) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(reportDataProvider);
          await ref.read(reportDataProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(wide ? 28 : 16),
          children: [
            const _FilterBar(),
            SectionHeader(title: context.tr('dash_overview')),
            ResponsiveWrap(minItemWidth: 210, children: [
              StatCard(icon: Icons.groups_2_outlined, label: context.tr('stat_total_accounts'), value: d.accountsTotal, accent: AppColors.cyan),
              StatCard(icon: Icons.link_rounded, label: context.tr('stat_connected'), value: d.accountsConnected, accent: AppColors.emerald),
              StatCard(icon: Icons.link_off_rounded, label: context.tr('stat_disconnected'), value: d.accountsDisconnected, accent: AppColors.blue),
              StatCard(icon: Icons.chat_bubble_outline, label: context.tr('stat_templates'), value: d.templates, accent: AppColors.violet),
              StatCard(icon: Icons.campaign_outlined, label: context.tr('stat_total_campaigns'), value: d.campaignsTotal, accent: AppColors.cyan),
              StatCard(icon: Icons.play_circle_outline, label: context.tr('stat_active_campaigns'), value: d.campaignsActive, accent: AppColors.blue),
              StatCard(icon: Icons.task_alt_outlined, label: context.tr('stat_completed_campaigns'), value: d.campaignsCompleted, accent: AppColors.emerald),
              StatCard(icon: Icons.error_outline, label: context.tr('stat_failed_campaigns'), value: d.campaignsFailed, accent: AppColors.red),
              StatCard(icon: Icons.send_outlined, label: context.tr('stat_attempted'), value: d.deliveriesAttempted, accent: AppColors.cyan),
              StatCard(icon: Icons.mark_email_read_outlined, label: context.tr('stat_successful_deliveries'), value: d.deliveriesSuccess, accent: AppColors.emerald),
              StatCard(icon: Icons.cancel_outlined, label: context.tr('stat_failed_deliveries'), value: d.deliveriesFailed, accent: AppColors.red),
              StatCard(icon: Icons.hourglass_bottom, label: context.tr('stat_pending'), value: d.deliveriesPending, accent: AppColors.amber),
              StatCard(icon: Icons.science_outlined, label: context.tr('stat_skipped'), value: d.deliveriesSkipped, accent: AppColors.violet),
            ]),
            SectionHeader(title: context.tr('charts_title')),
            ResponsiveWrap(minItemWidth: 360, maxColumns: 2, children: [
              _ChartCard(
                title: context.tr('chart_success_failed'),
                child: _SplitBar(parts: [
                  (context.tr('stat_successful_deliveries'), d.deliveriesSuccess, AppColors.emerald),
                  (context.tr('stat_failed_deliveries'), d.deliveriesFailed, AppColors.red),
                  (context.tr('stat_pending'), d.deliveriesPending, AppColors.amber),
                  (context.tr('stat_skipped'), d.deliveriesSkipped, AppColors.violet),
                ]),
              ),
              _ChartCard(title: context.tr('chart_daily'), child: _DailyChart(points: d.daily)),
              _ChartCard(
                title: context.tr('chart_platforms'),
                child: _HBars(entries: [
                  for (final p in MessagingPlatform.values)
                    (p.label, d.accountsByPlatform[p] ?? 0, platformColor(p)),
                ]),
              ),
              _ChartCard(
                title: context.tr('chart_deliveries_platform'),
                child: _HBars(entries: [
                  for (final p in MessagingPlatform.values)
                    (p.label, d.deliveriesByPlatform[p] ?? 0, platformColor(p)),
                ]),
              ),
              _ChartCard(
                title: context.tr('chart_accounts'),
                child: _HBars(entries: [for (final e in d.accountActivity) (e.key, e.value, AppColors.cyan)]),
              ),
              _ChartCard(
                title: context.tr('chart_campaign_status'),
                child: _HBars(entries: [
                  for (final s in CampaignStatus.values)
                    (context.tr('campaign_status_${s.dbValue}'), d.campaignStatus[s] ?? 0, AppColors.blue),
                ]),
              ),
            ]),
            SectionHeader(
              title: context.tr('rep_details'),
              trailing: Wrap(spacing: 4, children: [
                TextButton.icon(
                  onPressed: () => _export(context, ref, d, _view, csv: true),
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('CSV'),
                ),
                TextButton.icon(
                  onPressed: () => _export(context, ref, d, _view, csv: false),
                  icon: const Icon(Icons.data_object),
                  label: const Text('JSON'),
                ),
              ]),
            ),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(context.tr('rep_tab_campaigns'))),
                ButtonSegment(value: 1, label: Text(context.tr('rep_tab_deliveries'))),
                ButtonSegment(value: 2, label: Text(context.tr('rep_tab_activity'))),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            const SizedBox(height: 12),
            _DetailList(view: _view, data: d),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- filters

class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  Widget _dd<T>(BuildContext context, String label, T? value, Map<T, String> options, ValueChanged<T?> onChanged) {
    return SizedBox(
      width: 190,
      child: DropdownButtonFormField<T?>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          DropdownMenuItem<T?>(value: null, child: Text(context.tr('rep_all'))),
          for (final e in options.entries) DropdownMenuItem<T?>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(reportFilterProvider);
    final n = ref.read(reportFilterProvider.notifier);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final campaigns = ref.watch(campaignsProvider).valueOrNull ?? const [];
    return Wrap(spacing: 12, runSpacing: 12, children: [
      _dd<int>(context, context.tr('rep_period'), f.days, {
        7: context.tr('rep_days', args: {'n': formatNumber(context, 7)}),
        30: context.tr('rep_days', args: {'n': formatNumber(context, 30)}),
        90: context.tr('rep_days', args: {'n': formatNumber(context, 90)}),
      }, (v) => n.state = f.withDays(v)),
      _dd<MessagingPlatform>(context, context.tr('field_platform'), f.platform,
          {for (final p in MessagingPlatform.values) p: p.label}, (v) => n.state = f.withPlatform(v)),
      _dd<int>(context, context.tr('select_account'), f.accountId,
          {for (final a in accounts) a.id: a.displayName ?? a.accountIdentifier}, (v) => n.state = f.withAccount(v)),
      _dd<int>(context, context.tr('rep_campaign'), f.campaignId,
          {for (final c in campaigns) c.id: c.name}, (v) => n.state = f.withCampaign(v)),
      _dd<DeliveryStatus>(context, context.tr('rep_delivery_status'), f.deliveryStatus,
          {for (final s in DeliveryStatus.values) s: context.tr('delivery_${s.dbValue}')},
          (v) => n.state = f.withDeliveryStatus(v)),
      _dd<EventSeverity>(context, context.tr('rep_severity'), f.severity,
          {for (final s in EventSeverity.values) s: context.tr('severity_${s.dbValue}')},
          (v) => n.state = f.withSeverity(v)),
    ]);
  }
}

// ------------------------------------------------------------------ charts

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => GlowCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

/// Horizontal bars; values come straight from stored records.
class _HBars extends StatelessWidget {
  const _HBars({required this.entries});

  final List<(String, int, Color)> entries;

  @override
  Widget build(BuildContext context) {
    final maxValue = entries.fold<int>(0, (m, e) => e.$2 > m ? e.$2 : m);
    if (entries.isEmpty || maxValue == 0) {
      return Text(context.tr('rep_no_data'), style: Theme.of(context).textTheme.bodySmall);
    }
    return Column(children: [
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 110, child: Text(e.$1, overflow: TextOverflow.ellipsis)),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: e.$2 / maxValue, minHeight: 10, color: e.$3, backgroundColor: e.$3.withAlpha(28)),
              ),
            ),
            SizedBox(width: 44, child: Text(formatNumber(context, e.$2), textAlign: TextAlign.end)),
          ]),
        ),
    ]);
  }
}

class _SplitBar extends StatelessWidget {
  const _SplitBar({required this.parts});

  final List<(String, int, Color)> parts;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<int>(0, (s, p) => s + p.$2);
    if (total == 0) return Text(context.tr('rep_no_data'), style: Theme.of(context).textTheme.bodySmall);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Row(children: [
          for (final p in parts)
            if (p.$2 > 0) Expanded(flex: p.$2, child: Container(height: 16, color: p.$3)),
        ]),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 14, runSpacing: 4, children: [
        for (final p in parts)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, color: p.$3),
            const SizedBox(width: 6),
            Text('${p.$1}: ${formatNumber(context, p.$2)}', style: Theme.of(context).textTheme.bodySmall),
          ]),
      ]),
    ]);
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.points});

  final List<DayPoint> points;

  @override
  Widget build(BuildContext context) {
    final shown = points.length > 31 ? points.sublist(points.length - 31) : points;
    final maxTotal = shown.fold<int>(0, (m, p) => p.ok + p.failed > m ? p.ok + p.failed : m);
    if (shown.isEmpty || maxTotal == 0) {
      return Text(context.tr('rep_no_data'), style: Theme.of(context).textTheme.bodySmall);
    }
    const height = 130.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final p in shown)
            Expanded(
              child: Tooltip(
                message: '${p.day}  ✓ ${p.ok}  ✗ ${p.failed}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Container(height: height * p.failed / maxTotal, color: AppColors.red),
                    Container(height: height * p.ok / maxTotal, color: AppColors.emerald),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(formatDateFor(Localizations.localeOf(context), DateTime.parse(shown.first.day)), style: Theme.of(context).textTheme.bodySmall),
        Text(formatDateFor(Localizations.localeOf(context), DateTime.parse(shown.last.day)), style: Theme.of(context).textTheme.bodySmall),
      ]),
    ]);
  }
}

// ------------------------------------------------------------------- lists

class _DetailList extends StatelessWidget {
  const _DetailList({required this.view, required this.data});

  final int view;
  final ReportData data;

  static Color _sev(EventSeverity s) => switch (s) {
        EventSeverity.info => AppColors.blue,
        EventSeverity.warning => AppColors.amber,
        EventSeverity.error => AppColors.red,
        EventSeverity.security => AppColors.violet,
      };

  @override
  Widget build(BuildContext context) {
    final List<Widget> tiles;
    if (view == 0) {
      tiles = [
        for (final r in data.campaigns.take(100))
          ListTile(
            dense: true,
            title: Text('${r['name']}'),
            subtitle: Text('${r['account_name']} · ✓ ${r['ok']}  ✗ ${r['failed']}  ~ ${r['skipped']}'),
            trailing: StatusChip(
              label: context.tr('campaign_status_${r['status']}'),
              color: Colors.blueGrey,
            ),
          ),
      ];
    } else if (view == 1) {
      tiles = [
        for (final r in data.deliveries.take(100))
          ListTile(
            dense: true,
            title: Text('${r['destination']}'),
            subtitle: Text([
              '${r['campaign']}',
              '${r['account']}',
              if (r['error_code'] != null) '${r['error_code']}',
            ].join(' · ')),
            trailing: StatusChip(
              label: context.tr('delivery_${r['status']}'),
              color: switch (r['status']) {
                'sent' || 'delivered' => AppColors.emerald,
                'failed' => AppColors.red,
                'skipped' => AppColors.amber,
                _ => Colors.blueGrey,
              },
            ),
          ),
      ];
    } else {
      final strings = context.strings;
      tiles = [
        for (final e in data.events.take(100))
          ListTile(
            dense: true,
            leading: Icon(Icons.circle, size: 12, color: _sev(e.severity)),
            title: Text(strings.has('event_${e.eventType}') ? strings.t('event_${e.eventType}') : e.description),
            subtitle: Text('${context.tr('severity_${e.severity.dbValue}')} · ${formatDateTime(context, e.createdAt)}'),
          ),
      ];
    }
    if (tiles.isEmpty) {
      return EmptyState(
        compact: true,
        icon: Icons.inbox_outlined,
        title: context.tr('rep_empty_title'),
        message: context.tr('rep_empty_body'),
      );
    }
    return GlowCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: tiles));
  }
}

// ------------------------------------------------------------------ export

Future<void> _export(BuildContext context, WidgetRef ref, ReportData d, int view, {required bool csv}) async {
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.strings;
  try {
    final (headers, rows) = switch (view) {
      0 => ReportsRepository.campaignTable(d),
      1 => ReportsRepository.deliveryTable(d),
      _ => ReportsRepository.eventTable(d),
    };
    final kind = ['campaigns', 'deliveries', 'activity'][view];
    final content = csv ? toCsv(headers, rows) : toJsonText(headers, rows);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final file = await ref.read(appFilesProvider).write('exports', 'tesla_${kind}_$stamp.${csv ? 'csv' : 'json'}', content);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('export_done')),
        content: SelectableText('${ctx.tr('export_path')}\n${file.path}\n\n${ctx.tr('export_note')}', textDirection: TextDirection.ltr),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: content));
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(ctx.tr('export_copy')),
          ),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.tr('action_close'))),
        ],
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(localizedError(strings, e))));
  }
}

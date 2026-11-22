import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors/error_messages.dart';
import '../../core/localization/app_strings.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utilities/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/glow_card.dart';
import '../../core/widgets/responsive_wrap.dart';
import '../../core/widgets/simple_form_dialog.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/status_chip.dart';
import '../../integrations/common/adapter_registry_provider.dart';
import '../../shared/enums/enums.dart';
import '../../shared/models/account.dart';
import '../../shared/models/campaign.dart';
import '../../shared/models/delivery_record.dart';
import '../../shared/models/destination.dart';
import '../../shared/models/message_template.dart';
import '../accounts/application/account_providers.dart';
import 'campaign_engine.dart';

final campaignsProvider = FutureProvider.autoDispose<List<Campaign>>(
  (ref) => ref.watch(campaignRepositoryProvider).list(),
);

final campaignCountsProvider = FutureProvider.autoDispose.family<Map<DeliveryStatus, int>, int>(
  (ref, id) => ref.watch(deliveryRepositoryProvider).countsByStatus(campaignId: id),
);

final campaignDestinationsProvider = FutureProvider.autoDispose.family<List<CampaignDestination>, int>(
  (ref, id) => ref.watch(campaignRepositoryProvider).listDestinations(id),
);

Color _campaignColor(CampaignStatus s, {bool interrupted = false}) {
  if (interrupted) return AppColors.amber;
  return switch (s) {
    CampaignStatus.draft => Colors.blueGrey,
    CampaignStatus.scheduled => AppColors.blue,
    CampaignStatus.running => AppColors.cyan,
    CampaignStatus.paused => AppColors.amber,
    CampaignStatus.completed => AppColors.emerald,
    CampaignStatus.cancelled => Colors.blueGrey,
    CampaignStatus.failed => AppColors.red,
  };
}

Color _deliveryColor(DeliveryStatus s) => switch (s) {
      DeliveryStatus.pending => Colors.blueGrey,
      DeliveryStatus.sending => AppColors.cyan,
      DeliveryStatus.sent => AppColors.emerald,
      DeliveryStatus.delivered => AppColors.emerald,
      DeliveryStatus.failed => AppColors.red,
      DeliveryStatus.skipped => AppColors.amber,
    };

/// Destination identifier rules per platform (format only).
String? validateDestinationId(MessagingPlatform p, String value) {
  final v = value.trim();
  if (v.isEmpty) return 'validation_required';
  switch (p) {
    case MessagingPlatform.telegram:
      return RegExp(r'^(-?\d{5,20}|@[A-Za-z][A-Za-z0-9_]{4,31})$').hasMatch(v)
          ? null
          : 'validation_destination_telegram';
    case MessagingPlatform.whatsapp:
      return RegExp(r'^\+\d{7,15}$').hasMatch(v) ? null : 'validation_destination_whatsapp';
    case MessagingPlatform.rubika:
    case MessagingPlatform.soroush:
      return v.length <= 128 ? null : 'validation_identifier_length';
  }
}

class CampaignsScreen extends ConsumerStatefulWidget {
  const CampaignsScreen({super.key});

  @override
  ConsumerState<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends ConsumerState<CampaignsScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Live progress while something is running.
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final list = ref.read(campaignsProvider).valueOrNull;
      if (list != null && list.any((c) => c.status == CampaignStatus.running)) {
        ref.invalidate(campaignsProvider);
        for (final c in list.where((c) => c.status == CampaignStatus.running)) {
          ref.invalidate(campaignCountsProvider(c.id));
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(engineEventsProvider, (_, __) => ref.invalidate(campaignsProvider));
    final async = ref.watch(campaignsProvider);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorState(
        message: localizedError(context.strings, e),
        onRetry: () => ref.invalidate(campaignsProvider),
      ),
      data: (campaigns) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(campaignsProvider);
          await ref.read(campaignsProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(wide ? 28 : 16),
          children: [
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Tooltip(
                message: accounts.isEmpty ? context.tr('need_account_first') : '',
                child: FilledButton.icon(
                  onPressed: accounts.isEmpty
                      ? null
                      : () => _openEditor(context, ref, accounts),
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('campaign_add')),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(context.tr('campaign_run_note'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            if (campaigns.isEmpty)
              EmptyState(
                icon: Icons.campaign_outlined,
                title: context.tr('campaigns_empty_title'),
                message: context.tr('campaigns_empty_body'),
              )
            else
              ResponsiveWrap(
                minItemWidth: 380,
                children: [
                  for (final c in campaigns)
                    _CampaignCard(
                      campaign: c,
                      account: accounts.where((a) => a.id == c.accountId).firstOrNull,
                      accounts: accounts,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _act(BuildContext context, WidgetRef ref, Future<void> Function(CampaignEngine e) action,
    {String? successKey}) async {
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.strings;
  try {
    await action(ref.read(campaignEngineProvider));
    if (successKey != null) messenger.showSnackBar(SnackBar(content: Text(strings.t(successKey))));
  } catch (e, s) {
    AppLogger.error('Campaign action failed', error: e.runtimeType, stackTrace: s);
    messenger.showSnackBar(SnackBar(content: Text(localizedError(strings, e))));
  } finally {
    ref.invalidate(campaignsProvider);
  }
}

class _CampaignCard extends ConsumerWidget {
  const _CampaignCard({required this.campaign, required this.account, required this.accounts});

  final Campaign campaign;
  final Account? account;
  final List<Account> accounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final engine = ref.watch(campaignEngineProvider);
    final counts = ref.watch(campaignCountsProvider(campaign.id)).valueOrNull ?? const {};
    final dests = ref.watch(campaignDestinationsProvider(campaign.id)).valueOrNull ?? const [];

    // A campaign is only "running" while a worker is really active.
    final interrupted = campaign.status == CampaignStatus.running && !engine.isRunning(campaign.id);
    final statusKey = interrupted ? 'campaign_status_interrupted' : 'campaign_status_${campaign.status.dbValue}';

    final done = (counts[DeliveryStatus.sent] ?? 0) +
        (counts[DeliveryStatus.delivered] ?? 0) +
        (counts[DeliveryStatus.failed] ?? 0) +
        (counts[DeliveryStatus.skipped] ?? 0);
    final planned = dests.length * campaign.rounds;

    final canStart = campaign.status == CampaignStatus.draft || campaign.status == CampaignStatus.scheduled;
    final canSchedule = campaign.status == CampaignStatus.draft &&
        campaign.scheduleStart != null &&
        campaign.scheduleStart!.isAfter(DateTime.now());
    final canPause = campaign.status == CampaignStatus.running && !interrupted;
    final canResume = campaign.status == CampaignStatus.paused || interrupted;
    final canStop = const {
      CampaignStatus.scheduled,
      CampaignStatus.running,
      CampaignStatus.paused,
    }.contains(campaign.status);
    final isDraft = campaign.status == CampaignStatus.draft;

    return GlowCard(
      accent: _campaignColor(campaign.status, interrupted: interrupted),
      onTap: () => _showDetails(context, ref, campaign, account),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(campaign.name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
          Text(account == null ? '' : '${account!.platform.label} · ${account!.displayName ?? account!.accountIdentifier}',
              style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            StatusChip(label: context.tr(statusKey), color: _campaignColor(campaign.status, interrupted: interrupted)),
            StatusChip(
              label: context.tr('campaign_interval_label', args: {'s': formatNumber(context, campaign.sendIntervalSeconds)}),
              color: Colors.blueGrey,
            ),
            if (campaign.rounds > 1)
              StatusChip(
                label: context.tr('campaign_rounds_label', args: {'n': formatNumber(context, campaign.rounds)}),
                color: Colors.blueGrey,
              ),
          ]),
          if (interrupted) ...[
            const SizedBox(height: 6),
            Text(context.tr('campaign_interrupted_note'), style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: planned == 0 ? 0 : (done / planned).clamp(0.0, 1.0),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('campaign_progress', args: {
              'sent': formatNumber(context, (counts[DeliveryStatus.sent] ?? 0) + (counts[DeliveryStatus.delivered] ?? 0)),
              'failed': formatNumber(context, counts[DeliveryStatus.failed] ?? 0),
              'pending': formatNumber(context, (counts[DeliveryStatus.pending] ?? 0) + (counts[DeliveryStatus.sending] ?? 0)),
              'skipped': formatNumber(context, counts[DeliveryStatus.skipped] ?? 0),
            }),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 4, children: [
            if (canStart)
              FilledButton.tonal(
                onPressed: () => _act(context, ref, (e) => e.start(campaign.id), successKey: 'campaign_started'),
                child: Text(context.tr('campaign_start')),
              ),
            if (canSchedule)
              OutlinedButton(
                onPressed: () => _act(context, ref, (e) => e.schedule(campaign.id), successKey: 'campaign_scheduled'),
                child: Text(context.tr('campaign_schedule')),
              ),
            if (canPause)
              FilledButton.tonal(
                onPressed: () => _act(context, ref, (e) => e.pause(campaign.id)),
                child: Text(context.tr('campaign_pause')),
              ),
            if (canResume)
              FilledButton.tonal(
                onPressed: () => _act(context, ref, (e) => e.resume(campaign.id), successKey: 'campaign_started'),
                child: Text(context.tr('campaign_resume')),
              ),
            if (canStop)
              TextButton(
                onPressed: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: context.tr('campaign_stop_title'),
                    message: context.tr('campaign_stop_body'),
                    confirmLabel: context.tr('campaign_stop'),
                    destructive: true,
                  );
                  if (ok && context.mounted) await _act(context, ref, (e) => e.stop(campaign.id));
                },
                child: Text(context.tr('campaign_stop')),
              ),
            if (isDraft)
              TextButton(
                onPressed: () => _openEditor(context, ref, accounts, existing: campaign),
                child: Text(context.tr('account_edit')),
              ),
            if (isDraft)
              TextButton(
                onPressed: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: context.tr('campaign_delete_title'),
                    message: context.tr('campaign_delete_body'),
                    confirmLabel: context.tr('account_delete'),
                    destructive: true,
                  );
                  if (ok && context.mounted) {
                    await _act(context, ref, (_) => ref.read(campaignRepositoryProvider).delete(campaign.id));
                  }
                },
                child: Text(context.tr('account_delete')),
              ),
          ]),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ details

Future<void> _showDetails(BuildContext context, WidgetRef ref, Campaign c, Account? account) async {
  final campaigns = ref.read(campaignRepositoryProvider);
  final deliveries = ref.read(deliveryRepositoryProvider);
  final destinations = await campaigns.listDestinations(c.id);
  final records = await deliveries.listForCampaign(c.id);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => _DetailsDialog(campaign: c, account: account, destinations: destinations, records: records),
  );
}

class _DetailsDialog extends StatelessWidget {
  const _DetailsDialog({
    required this.campaign,
    required this.account,
    required this.destinations,
    required this.records,
  });

  final Campaign campaign;
  final Account? account;
  final List<CampaignDestination> destinations;
  final List<DeliveryRecord> records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String when(DateTime? t) => t == null ? '—' : formatDateTime(context, t);
    final names = {for (final d in destinations) d.destinationId: d.displayName ?? d.platformDestinationId};

    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 140, child: Text(k, style: theme.textTheme.bodySmall)),
            Expanded(child: Text(v)),
          ]),
        );

    return AlertDialog(
      title: Text(campaign.name),
      content: SizedBox(
        width: 560,
        height: 480,
        child: ListView(children: [
          row(context.tr('field_platform'), account?.platform.label ?? '—'),
          row(context.tr('details_status'), context.tr('campaign_status_${campaign.status.dbValue}')),
          row(context.tr('campaign_schedule_start'), when(campaign.scheduleStart)),
          row(context.tr('campaign_schedule_end'), when(campaign.scheduleEnd)),
          row(context.tr('campaign_interval'), '${campaign.sendIntervalSeconds}'),
          row(context.tr('campaign_rounds'), '${campaign.rounds}'),
          row(context.tr('campaign_max_deliveries'), campaign.maxDeliveries?.toString() ?? '—'),
          row(context.tr('campaign_started_at'), when(campaign.startedAt)),
          row(context.tr('campaign_completed_at'), when(campaign.completedAt)),
          const Divider(),
          Text(context.tr('campaign_destinations'), style: theme.textTheme.titleSmall),
          for (final d in destinations)
            ListTile(
              dense: true,
              title: Text(d.displayName ?? d.platformDestinationId),
              subtitle: Text(d.platformDestinationId, textDirection: TextDirection.ltr),
              trailing: Icon(d.isDeliverable ? Icons.verified_user_outlined : Icons.block,
                  color: d.isDeliverable ? AppColors.emerald : AppColors.amber),
            ),
          const Divider(),
          Text(context.tr('campaign_history'), style: theme.textTheme.titleSmall),
          if (records.isEmpty) Text(context.tr('campaign_no_deliveries'), style: theme.textTheme.bodySmall),
          for (final r in records.reversed.take(100))
            ListTile(
              dense: true,
              title: Text(names[r.destinationId] ?? '#${r.destinationId}'),
              subtitle: Text([
                if (r.errorCode != null) r.errorCode!,
                '${context.tr('campaign_attempts')}: ${r.attemptCount}',
                formatDateTime(context, r.updatedAt),
              ].join(' · ')),
              trailing: StatusChip(
                label: context.tr('delivery_${r.status.dbValue}'),
                color: _deliveryColor(r.status),
              ),
            ),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('action_close')))],
    );
  }
}

// ------------------------------------------------------------------- editor

Future<void> _openEditor(BuildContext context, WidgetRef ref, List<Account> accounts,
    {Campaign? existing}) async {
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.strings;
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CampaignEditor(accounts: accounts, existing: existing),
  );
  ref.invalidate(campaignsProvider);
  if (saved == true) messenger.showSnackBar(SnackBar(content: Text(strings.t('campaign_saved'))));
}

class _CampaignEditor extends ConsumerStatefulWidget {
  const _CampaignEditor({required this.accounts, this.existing});

  final List<Account> accounts;
  final Campaign? existing;

  @override
  ConsumerState<_CampaignEditor> createState() => _CampaignEditorState();
}

class _CampaignEditorState extends ConsumerState<_CampaignEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _interval = TextEditingController(text: '${widget.existing?.sendIntervalSeconds ?? 5}');
  late final _max = TextEditingController(text: widget.existing?.maxDeliveries?.toString() ?? '');
  late Account _account = widget.accounts.firstWhere(
    (a) => a.id == widget.existing?.accountId,
    orElse: () => widget.accounts.first,
  );
  late int _rounds = widget.existing?.rounds ?? 1;
  late int? _templateId = widget.existing?.templateId;
  late DateTime? _start = widget.existing?.scheduleStart?.toLocal();
  late DateTime? _end = widget.existing?.scheduleEnd?.toLocal();
  final Map<int, bool> _selected = {}; // destinationId -> consent confirmed
  late Future<List<MessageTemplate>> _templates;
  late Future<List<Destination>> _destinations;
  int? _createdId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAccountData();
    final e = widget.existing;
    if (e != null) {
      ref.read(campaignRepositoryProvider).listDestinations(e.id).then((list) {
        if (!mounted) return;
        setState(() {
          for (final cd in list) {
            _selected[cd.destinationId] = cd.isDeliverable;
          }
        });
      });
    }
  }

  void _loadAccountData() {
    _templates = ref.read(messageTemplateRepositoryProvider).listForAccount(_account.id);
    _destinations = ref.read(destinationRepositoryProvider).listForAccount(_account.id);
  }

  @override
  void dispose() {
    _name.dispose();
    _interval.dispose();
    _max.dispose();
    super.dispose();
  }

  int get _minInterval =>
      ref.read(adapterRegistryProvider).forPlatform(_account.platform).capabilities.minIntervalSeconds;

  Future<void> _pick({required bool start}) async {
    final now = DateTime.now();
    final current = (start ? _start : _end) ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (t == null || !mounted) return;
    final value = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() => start ? _start = value : _end = value);
  }

  Future<void> _addDestination() async {
    final platform = _account.platform;
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => SimpleFormDialog(
        title: context.tr('destination_add'),
        note: context.tr('destination_note_${platform.dbValue}'),
        choices: [
          FormChoiceSpec('type',
              label: context.tr('destination_type'),
              initial: DestinationType.user.dbValue,
              options: {for (final t in DestinationType.values) t.dbValue: context.tr('dtype_${t.dbValue}')}),
        ],
        fields: [
          FormFieldSpec('id',
              label: context.tr('destination_id'),
              ltr: true,
              required: true,
              validator: (v) {
                final key = validateDestinationId(platform, v);
                return key == null ? null : context.tr(key);
              }),
          FormFieldSpec('name', label: context.tr('destination_name')),
        ],
        onSubmit: (v) async {
          await ref.read(destinationRepositoryProvider).create(DestinationInput(
                accountId: _account.id,
                platformDestinationId: v['id']!,
                displayName: v['name'],
                destinationType: enumFromDb(DestinationType.values, v['type'], fallback: DestinationType.other),
              ));
        },
      ),
    );
    if (added == true && mounted) setState(_loadAccountData);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_templateId == null) {
      setState(() => _error = context.tr('campaign_pick_template'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(campaignRepositoryProvider);
      final input = CampaignInput(
        name: _name.text,
        accountId: _account.id,
        templateId: _templateId!,
        scheduleStart: _start,
        scheduleEnd: _end,
        timezone: DateTime.now().timeZoneName,
        sendIntervalSeconds: int.parse(_interval.text.trim()),
        rounds: _rounds,
        maxDeliveries: _max.text.trim().isEmpty ? null : int.parse(_max.text.trim()),
      );
      final existingId = widget.existing?.id ?? _createdId;
      final Campaign c = existingId == null ? await repo.create(input) : await repo.updateDraft(existingId, input);
      _createdId = c.id; // a retry after a partial failure must not create a second campaign

      final current = {for (final cd in await repo.listDestinations(c.id)) cd.destinationId: cd};
      for (final e in _selected.entries) {
        final consent = e.value ? ConsentStatus.granted : ConsentStatus.pending;
        final auth = e.value ? AuthorizationStatus.authorized : AuthorizationStatus.unknown;
        if (current[e.key] == null) {
          await repo.addDestination(c.id, e.key, consent: consent, authorization: auth);
        } else {
          await repo.setDestinationConsent(c.id, e.key, consent);
          await repo.setDestinationAuthorization(c.id, e.key, auth);
        }
      }
      for (final id in current.keys) {
        if (!_selected.containsKey(id)) await repo.removeDestination(c.id, id);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = localizedError(context.strings, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(context.tr(editing ? 'campaign_edit' : 'campaign_add')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  decoration: InputDecoration(labelText: context.tr('campaign_name')),
                  validator: (v) => (v ?? '').trim().isEmpty ? context.tr('validation_required') : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _account.id,
                  decoration: InputDecoration(labelText: context.tr('select_account')),
                  items: [
                    for (final a in widget.accounts)
                      DropdownMenuItem(value: a.id, child: Text('${a.platform.label} · ${a.displayName ?? a.accountIdentifier}')),
                  ],
                  // Destinations belong to one account, so the account is fixed once saved.
                  onChanged: (_saving || editing || _createdId != null)
                      ? null
                      : (id) => setState(() {
                            _account = widget.accounts.firstWhere((a) => a.id == id);
                            _templateId = null;
                            _selected.clear();
                            _loadAccountData();
                          }),
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<MessageTemplate>>(
                  future: _templates,
                  builder: (context, snap) {
                    final items = (snap.data ?? const <MessageTemplate>[]).where((t) => t.enabled || t.id == _templateId).toList();
                    if (snap.connectionState == ConnectionState.done && items.isEmpty) {
                      return Text(context.tr('campaign_no_templates'), style: TextStyle(color: theme.colorScheme.error));
                    }
                    return DropdownButtonFormField<int>(
                      value: items.any((t) => t.id == _templateId) ? _templateId : null,
                      decoration: InputDecoration(labelText: context.tr('campaign_template')),
                      items: [for (final t in items) DropdownMenuItem(value: t.id, child: Text(t.title, overflow: TextOverflow.ellipsis))],
                      onChanged: _saving ? null : (id) => setState(() => _templateId = id),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pick(start: true),
                    icon: const Icon(Icons.event),
                    label: Text(_start == null
                        ? context.tr('campaign_schedule_start')
                        : '${context.tr('campaign_schedule_start')}: ${formatDateTime(context, _start!)}'),
                  ),
                  if (_start != null)
                    IconButton(onPressed: () => setState(() => _start = null), icon: const Icon(Icons.clear), tooltip: context.tr('action_clear')),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pick(start: false),
                    icon: const Icon(Icons.event_busy),
                    label: Text(_end == null
                        ? context.tr('campaign_schedule_end')
                        : '${context.tr('campaign_schedule_end')}: ${formatDateTime(context, _end!)}'),
                  ),
                  if (_end != null)
                    IconButton(onPressed: () => setState(() => _end = null), icon: const Icon(Icons.clear), tooltip: context.tr('action_clear')),
                ]),
                const SizedBox(height: 4),
                Text(context.tr('campaign_schedule_note'), style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _interval,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: context.tr('campaign_interval')),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null) return context.tr('validation_number');
                        if (n < _minInterval) {
                          return context.tr('validation_interval_min', args: {'min': '$_minInterval'});
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _rounds,
                      decoration: InputDecoration(labelText: context.tr('campaign_rounds')),
                      items: [for (var i = 1; i <= 5; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                      onChanged: _saving ? null : (v) => setState(() => _rounds = v ?? 1),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _max,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.tr('campaign_max_deliveries'),
                    helperText: context.tr('campaign_max_hint'),
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    final n = int.tryParse(t);
                    return (n == null || n < 1) ? context.tr('validation_number') : null;
                  },
                ),
                const Divider(height: 28),
                Row(children: [
                  Expanded(child: Text(context.tr('campaign_destinations'), style: theme.textTheme.titleSmall)),
                  TextButton.icon(
                    onPressed: _saving ? null : _addDestination,
                    icon: const Icon(Icons.add),
                    label: Text(context.tr('destination_add')),
                  ),
                ]),
                Text(context.tr('campaign_consent_note'), style: theme.textTheme.bodySmall),
                FutureBuilder<List<Destination>>(
                  future: _destinations,
                  builder: (context, snap) {
                    final list = snap.data ?? const <Destination>[];
                    if (snap.connectionState == ConnectionState.done && list.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(context.tr('destinations_empty')),
                      );
                    }
                    return Column(children: [
                      for (final d in list) ...[
                        CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _selected.containsKey(d.id),
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => v == true ? _selected[d.id] = false : _selected.remove(d.id)),
                          title: Text(d.displayName ?? d.platformDestinationId),
                          subtitle: Text('${context.tr('dtype_${d.destinationType.dbValue}')} · ${d.platformDestinationId}',
                              textDirection: TextDirection.ltr),
                        ),
                        if (_selected.containsKey(d.id))
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 40),
                            child: SwitchListTile(
                              dense: true,
                              value: _selected[d.id]!,
                              onChanged: _saving ? null : (v) => setState(() => _selected[d.id] = v),
                              title: Text(context.tr('campaign_consent_confirmed')),
                            ),
                          ),
                      ],
                    ]);
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(_createdId != null),
          child: Text(context.tr('action_cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.tr('form_save')),
        ),
      ],
    );
  }
}

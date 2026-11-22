import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/security/credential_store.dart';
import '../../integrations/common/adapter_registry_provider.dart';
import '../../integrations/common/platform_adapter.dart';
import '../../shared/enums/enums.dart';
import '../../shared/models/account.dart';
import '../../shared/models/activity_event.dart';
import '../../shared/models/campaign.dart';
import '../../shared/models/delivery_record.dart';
import '../../shared/models/message_template.dart';
import '../accounts/application/account_providers.dart';
import '../accounts/data/account_repository.dart';
import '../messages/data/message_template_repository.dart';
import '../reports/data/activity_repository.dart';
import 'data/campaign_repository.dart';
import 'data/delivery_repository.dart';

enum EngineEventType { completed, failed, autoPaused, authExpired }

class EngineEvent {
  const EngineEvent(this.type, this.campaignId);

  final EngineEventType type;
  final int campaignId;
}

class _Run {
  bool stop = false;
  late Future<void> done;
}

/// Executes campaigns while the app is running. It is independent of the UI.
///
/// Honest limits: it runs only in this process (no background service). If the
/// app is closed the work stops; on next start [recover] turns any campaign that
/// was `running` into `paused`, so a campaign is never shown as running without
/// an active worker.
///
/// Safety rules enforced here (and by database triggers):
/// account connected, adapter credentials present, template enabled, interval
/// at least the platform minimum, per-destination consent + authorization
/// re-checked before EVERY send, one delivery record per idempotency key,
/// platform rate limits (`retry_after`) honoured, no randomised intervals and no
/// account rotation.
class CampaignEngine {
  CampaignEngine({
    required CampaignRepository campaigns,
    required DeliveryRepository deliveries,
    required MessageTemplateRepository templates,
    required AccountRepository accounts,
    required CredentialStore store,
    required AdapterRegistry registry,
    required ActivityRepository activity,
    Future<void> Function(Duration)? delay,
    DateTime Function()? now,
  })  : _campaigns = campaigns,
        _deliveries = deliveries,
        _templates = templates,
        _accounts = accounts,
        _store = store,
        _registry = registry,
        _activity = activity,
        _delay = delay ?? Future<void>.delayed,
        _now = now ?? DateTime.now;

  final CampaignRepository _campaigns;
  final DeliveryRepository _deliveries;
  final MessageTemplateRepository _templates;
  final AccountRepository _accounts;
  final CredentialStore _store;
  final AdapterRegistry _registry;
  final ActivityRepository _activity;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _now;

  final Map<int, _Run> _runs = {};
  final StreamController<EngineEvent> _events = StreamController<EngineEvent>.broadcast();

  Stream<EngineEvent> get events => _events.stream;

  /// True only while a worker for this campaign is actually active.
  bool isRunning(int campaignId) => _runs.containsKey(campaignId);

  /// Completes when the worker of [campaignId] (if any) has finished. For tests.
  Future<void> whenIdle(int campaignId) async => _runs[campaignId]?.done;

  void _emit(EngineEventType type, int id) {
    if (!_events.isClosed) _events.add(EngineEvent(type, id));
  }

  Future<Campaign> _require(int id) async {
    final c = await _campaigns.getById(id);
    if (c == null) throw const NotFoundException('Campaign not found.');
    return c;
  }

  // ------------------------------------------------------------ public API

  /// Starts a draft/scheduled campaign, or resumes a paused one.
  Future<void> start(int campaignId) async {
    if (_runs.containsKey(campaignId)) {
      throw const ValidationException(
          ErrorCodes.invalidCampaignTransition, 'Campaign already has an active worker.');
    }
    final c = await _require(campaignId);
    const startable = {CampaignStatus.draft, CampaignStatus.scheduled, CampaignStatus.paused};
    if (!startable.contains(c.status)) {
      throw const ValidationException(
          ErrorCodes.invalidCampaignTransition, 'Campaign cannot be started from this status.');
    }
    await _preflight(c);
    await _campaigns.transition(campaignId, CampaignStatus.running);
    final run = _Run();
    _runs[campaignId] = run;
    run.done = _loop(campaignId, run).whenComplete(() => _runs.remove(campaignId));
  }

  Future<void> resume(int campaignId) => start(campaignId);

  /// Draft -> scheduled. The in-app scheduler starts it at `scheduleStart`
  /// (the app must be running at that time).
  Future<void> schedule(int campaignId) async {
    final c = await _require(campaignId);
    final start = c.scheduleStart;
    if (start == null || !start.isAfter(_now())) {
      throw const ValidationException(
          ErrorCodes.campaignScheduleInvalid, 'Schedule start must be in the future.');
    }
    await _preflight(c);
    await _campaigns.transition(campaignId, CampaignStatus.scheduled);
  }

  Future<void> pause(int campaignId) async {
    _runs[campaignId]?.stop = true;
    await _campaigns.transition(campaignId, CampaignStatus.paused);
  }

  /// Cancels the campaign (terminal). Already-created delivery records are kept.
  Future<void> stop(int campaignId) async {
    _runs[campaignId]?.stop = true;
    await _campaigns.transition(campaignId, CampaignStatus.cancelled);
  }

  /// Call once at app start. Interrupted `sending` records go back to `pending`
  /// and campaigns left `running` become `paused` (no worker survived the restart).
  Future<int> recover() async {
    await _deliveries.recoverInterrupted();
    final stale = await _campaigns.list(status: CampaignStatus.running);
    for (final c in stale) {
      if (_runs.containsKey(c.id)) continue;
      await _campaigns.transition(c.id, CampaignStatus.paused);
      await _activity.log(ActivityEventInput(
        eventType: 'campaign_interrupted',
        description: 'Campaign #${c.id} was interrupted by an app restart and paused',
        severity: EventSeverity.warning,
        campaignId: c.id,
        accountId: c.accountId,
      ));
    }
    return stale.length;
  }

  /// Starts scheduled campaigns whose start time has arrived. Returns how many started.
  Future<int> startDueCampaigns() async {
    var started = 0;
    final due = await _campaigns.list(status: CampaignStatus.scheduled);
    for (final c in due) {
      final at = c.scheduleStart;
      if (at == null || at.isAfter(_now()) || _runs.containsKey(c.id)) continue;
      try {
        await start(c.id);
        started++;
      } catch (e) {
        AppLogger.warning('Scheduled campaign could not start');
        await _campaigns.transition(c.id, CampaignStatus.draft);
        await _activity.log(ActivityEventInput(
          eventType: 'campaign_schedule_failed',
          description: 'Scheduled start of campaign #${c.id} failed; returned to draft',
          severity: EventSeverity.error,
          campaignId: c.id,
          accountId: c.accountId,
          metadata: {'code': e is AppException ? e.code : 'UNKNOWN'},
        ));
        _emit(EngineEventType.failed, c.id);
      }
    }
    return started;
  }

  // -------------------------------------------------------------- internals

  /// Pre-send checks from the specification (campaign active, account connected,
  /// destination authorised, consent, template valid, platform limits).
  Future<void> _preflight(Campaign c) async {
    final account = await _accounts.getById(c.accountId);
    if (account == null) throw const NotFoundException('Account not found.');
    // A rate-limited account is still a valid, authenticated account: the engine
    // simply waits again. Anything else (disconnected, auth problems, errors) must
    // be fixed by connecting the account first.
    final live = account.connectionStatus == ConnectionStatus.connected ||
        account.connectionStatus == ConnectionStatus.mockConnection ||
        account.connectionStatus == ConnectionStatus.rateLimited;
    if (!live) {
      throw const ValidationException(
          ErrorCodes.accountNotConnected, 'The account is not connected.');
    }
    final template = await _templates.getById(c.templateId);
    if (template == null) throw const NotFoundException('Template not found.');
    if (!template.enabled) {
      throw const ValidationException(ErrorCodes.templateDisabled, 'The template is disabled.');
    }
    final adapter = _registry.forPlatform(account.platform);
    final caps = adapter.capabilities;
    if (c.sendIntervalSeconds < caps.minIntervalSeconds) {
      throw const ValidationException(
          ErrorCodes.intervalTooShort, 'Interval is below the platform minimum.');
    }
    final usesTemplate = (template.waTemplateName ?? '').isNotEmpty;
    if (!usesTemplate && template.body.length > caps.maxTextLength) {
      throw const ValidationException(ErrorCodes.templateTooLong, 'Message is too long.');
    }
    if (adapter.mode == AdapterMode.real) {
      final ref = account.credentialReference;
      final stored = ref == null ? null : await _store.read(ref);
      if (stored == null || stored.isEmpty) {
        throw const ValidationException(
            ErrorCodes.accountNotConnected, 'Credentials are missing.');
      }
    }
    final end = c.scheduleEnd;
    if (end != null && end.isBefore(_now())) {
      throw const ValidationException(ErrorCodes.campaignScheduleInvalid, 'Schedule already ended.');
    }
    final destinations = await _campaigns.listDestinations(c.id);
    if (!destinations.any((d) => d.isDeliverable)) {
      throw const ValidationException(
          ErrorCodes.campaignNoDestinations, 'No destination has consent and authorization.');
    }
  }

  Future<void> _wait(_Run run, Duration total) async {
    var remaining = total;
    while (remaining > Duration.zero && !run.stop) {
      final step = remaining < const Duration(seconds: 1) ? remaining : const Duration(seconds: 1);
      await _delay(step);
      remaining -= step;
    }
  }

  Future<void> _autoPause(Campaign c, String reason, EngineEventType type) async {
    try {
      await _campaigns.transition(c.id, CampaignStatus.paused);
    } catch (_) {
      return; // status already changed by the user
    }
    await _activity.log(ActivityEventInput(
      eventType: 'campaign_auto_paused',
      description: 'Campaign #${c.id} was paused automatically',
      severity: EventSeverity.warning,
      campaignId: c.id,
      accountId: c.accountId,
      metadata: {'reason': reason},
    ));
    _emit(type, c.id);
  }

  Future<void> _complete(int id) async {
    try {
      await _campaigns.transition(id, CampaignStatus.completed);
      _emit(EngineEventType.completed, id);
    } catch (_) {
      // user paused/cancelled in the meantime
    }
  }

  Future<bool> _limitReached(Campaign c) async {
    final max = c.maxDeliveries;
    if (max == null) return false;
    final counts = await _deliveries.countsByStatus(campaignId: c.id);
    final attempted = (counts[DeliveryStatus.sent] ?? 0) +
        (counts[DeliveryStatus.delivered] ?? 0) +
        (counts[DeliveryStatus.failed] ?? 0);
    return attempted >= max;
  }

  Future<void> _loop(int id, _Run run) async {
    try {
      final campaign = await _require(id);
      final template = (await _templates.getById(campaign.templateId))!;
      final account = (await _accounts.getById(campaign.accountId))!;
      final adapter = _registry.forPlatform(account.platform);
      var credentials = const AccountCredentials({});
      if (adapter.mode == AdapterMode.real) {
        final ref = account.credentialReference;
        credentials = AccountCredentials((ref == null ? null : await _store.read(ref)) ?? {});
      }
      var first = true;
      var limited = account.connectionStatus == ConnectionStatus.rateLimited;

      for (var round = 1; round <= campaign.rounds; round++) {
        final destinations = await _campaigns.listDestinations(id);
        for (final planned in destinations) {
          if (run.stop) return;
          // Consent and authorization are re-read before every single send.
          final current = (await _campaigns.listDestinations(id))
              .where((d) => d.destinationId == planned.destinationId);
          if (current.isEmpty || !current.first.isDeliverable) continue;
          final end = campaign.scheduleEnd;
          if (end != null && end.isBefore(_now())) {
            await _complete(id);
            return;
          }
          if (await _limitReached(campaign)) {
            await _complete(id);
            return;
          }
          final created = await _deliveries.createOrGet(DeliveryInput(
            campaignId: id,
            destinationId: planned.destinationId,
            templateId: template.id,
            idempotencyKey: DeliveryRepository.buildIdempotencyKey(
              campaignId: id,
              destinationId: planned.destinationId,
              templateId: template.id,
              round: round,
            ),
          ));
          // Duplicate prevention: only a pending record is (still) to be sent.
          if (created.record.status != DeliveryStatus.pending) continue;

          if (!first) {
            await _wait(run, Duration(seconds: campaign.sendIntervalSeconds));
            if (run.stop) return;
          }
          first = false;

          final proceed = await _attempt(
            campaign: campaign,
            template: template,
            account: account,
            adapter: adapter,
            credentials: credentials,
            destination: current.first,
            record: created.record,
            run: run,
            wasLimited: limited,
            onLimitedChanged: (v) => limited = v,
          );
          if (!proceed) return;
        }
      }
      if (!run.stop) await _complete(id);
    } catch (e, s) {
      AppLogger.error('Campaign worker crashed', error: e.runtimeType, stackTrace: s);
      try {
        await _campaigns.transition(id, CampaignStatus.failed);
        _emit(EngineEventType.failed, id);
      } catch (_) {}
    }
  }

  /// Sends one delivery (up to 3 tries for temporary problems).
  /// Returns false when the whole campaign must stop (paused/auth failure).
  Future<bool> _attempt({
    required Campaign campaign,
    required MessageTemplate template,
    required Account account,
    required PlatformAdapter adapter,
    required AccountCredentials credentials,
    required CampaignDestination destination,
    required DeliveryRecord record,
    required _Run run,
    required bool wasLimited,
    required void Function(bool) onLimitedChanged,
  }) async {
    var rec = record;
    for (var attempt = 1; attempt <= 3; attempt++) {
      rec = await _deliveries.markSending(rec.id);
      SendResult result;
      try {
        result = await adapter.sendText(SendRequest(
          accountIdentifier: account.accountIdentifier,
          credentials: credentials,
          destinationId: destination.platformDestinationId,
          text: template.body,
          templateName: template.waTemplateName,
          templateLanguage: template.waTemplateLanguage,
        ));
      } catch (e) {
        result = const SendResult(SendOutcome.retryable, errorCode: 'ADAPTER_EXCEPTION');
      }

      switch (result.outcome) {
        case SendOutcome.sent:
          await _deliveries.markSent(rec.id, platformMessageId: result.messageId);
          await _accounts.touchActivity(account.id);
          if (wasLimited) {
            await _accounts.updateConnectionStatus(account.id, ConnectionStatus.connected);
            onLimitedChanged(false);
          }
          return true;
        case SendOutcome.simulated:
          await _deliveries.markSkipped(rec.id,
              reason: 'Simulated (mock integration): nothing was sent.');
          return true;
        case SendOutcome.rejected:
          await _deliveries.markFailed(rec.id,
              errorCode: result.errorCode ?? 'REJECTED', errorMessage: result.errorMessage);
          return true;
        case SendOutcome.authFailed:
          await _deliveries.markFailed(rec.id,
              errorCode: result.errorCode ?? 'AUTH', errorMessage: result.errorMessage);
          await _accounts.updateConnectionStatus(account.id, ConnectionStatus.authenticationRequired);
          await _autoPause(campaign, 'AUTH_FAILED', EngineEventType.authExpired);
          return false;
        case SendOutcome.rateLimited:
          await _deliveries.releaseToPending(rec.id);
          await _accounts.updateConnectionStatus(account.id, ConnectionStatus.rateLimited);
          onLimitedChanged(true);
          wasLimited = true;
          if (attempt == 3) {
            await _autoPause(campaign, 'RATE_LIMITED', EngineEventType.autoPaused);
            return false;
          }
          await _wait(run, (result.retryAfter ?? const Duration(seconds: 30)) + const Duration(seconds: 1));
          if (run.stop) return false;
        case SendOutcome.retryable:
          if (attempt == 3) {
            await _deliveries.markFailed(rec.id,
                errorCode: result.errorCode ?? 'RETRY_EXHAUSTED', errorMessage: result.errorMessage);
            return true;
          }
          await _deliveries.releaseToPending(rec.id);
          await _wait(run, Duration(seconds: 5 * attempt));
          if (run.stop) return false;
      }
    }
    return true;
  }
}

// ------------------------------------------------------------------ providers

final campaignEngineProvider = Provider<CampaignEngine>((ref) {
  final engine = CampaignEngine(
    campaigns: ref.watch(campaignRepositoryProvider),
    deliveries: ref.watch(deliveryRepositoryProvider),
    templates: ref.watch(messageTemplateRepositoryProvider),
    accounts: ref.watch(accountRepositoryProvider),
    store: ref.watch(credentialStoreProvider),
    registry: ref.watch(adapterRegistryProvider),
    activity: ref.watch(activityRepositoryProvider),
  );
  return engine;
});

final engineEventsProvider =
    StreamProvider<EngineEvent>((ref) => ref.watch(campaignEngineProvider).events);

/// Watched once by the app: recovers interrupted work, then checks for due
/// scheduled campaigns every 20 seconds while the app is running.
final engineStartupProvider = FutureProvider<void>((ref) async {
  final engine = ref.watch(campaignEngineProvider);
  await engine.recover();
  final timer = Timer.periodic(const Duration(seconds: 20), (_) {
    engine.startDueCampaigns().catchError((Object _) => 0);
  });
  ref.onDispose(timer.cancel);
});

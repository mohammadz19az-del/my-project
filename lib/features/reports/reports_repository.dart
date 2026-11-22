import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../app/providers.dart';
import '../../core/database/db_guard.dart';
import '../../shared/enums/enums.dart';
import '../../shared/models/activity_event.dart';

/// Immutable report filter; the `with*` helpers return a changed copy.
class ReportFilter {
  const ReportFilter({
    this.days = 30,
    this.platform,
    this.accountId,
    this.campaignId,
    this.deliveryStatus,
    this.severity,
  });

  /// Look-back window in days; null = all time.
  final int? days;
  final MessagingPlatform? platform;
  final int? accountId;
  final int? campaignId;
  final DeliveryStatus? deliveryStatus;
  final EventSeverity? severity;

  ReportFilter withDays(int? v) => ReportFilter(days: v, platform: platform, accountId: accountId, campaignId: campaignId, deliveryStatus: deliveryStatus, severity: severity);
  ReportFilter withPlatform(MessagingPlatform? v) => ReportFilter(days: days, platform: v, accountId: accountId, campaignId: campaignId, deliveryStatus: deliveryStatus, severity: severity);
  ReportFilter withAccount(int? v) => ReportFilter(days: days, platform: platform, accountId: v, campaignId: campaignId, deliveryStatus: deliveryStatus, severity: severity);
  ReportFilter withCampaign(int? v) => ReportFilter(days: days, platform: platform, accountId: accountId, campaignId: v, deliveryStatus: deliveryStatus, severity: severity);
  ReportFilter withDeliveryStatus(DeliveryStatus? v) => ReportFilter(days: days, platform: platform, accountId: accountId, campaignId: campaignId, deliveryStatus: v, severity: severity);
  ReportFilter withSeverity(EventSeverity? v) => ReportFilter(days: days, platform: platform, accountId: accountId, campaignId: campaignId, deliveryStatus: deliveryStatus, severity: v);
}

class DayPoint {
  const DayPoint(this.day, this.ok, this.failed);
  final String day; // yyyy-MM-dd (UTC)
  final int ok;
  final int failed;
}

class ReportData {
  const ReportData({
    required this.accountsTotal,
    required this.accountsConnected,
    required this.accountsDisconnected,
    required this.templates,
    required this.campaignsTotal,
    required this.campaignsActive,
    required this.campaignsCompleted,
    required this.campaignsFailed,
    required this.deliveriesAttempted,
    required this.deliveriesSuccess,
    required this.deliveriesFailed,
    required this.deliveriesPending,
    required this.deliveriesSkipped,
    required this.daily,
    required this.accountsByPlatform,
    required this.deliveriesByPlatform,
    required this.accountActivity,
    required this.campaignStatus,
    required this.campaigns,
    required this.deliveries,
    required this.events,
  });

  final int accountsTotal, accountsConnected, accountsDisconnected, templates;
  final int campaignsTotal, campaignsActive, campaignsCompleted, campaignsFailed;
  final int deliveriesAttempted, deliveriesSuccess, deliveriesFailed, deliveriesPending, deliveriesSkipped;
  final List<DayPoint> daily;
  final Map<MessagingPlatform, int> accountsByPlatform;
  final Map<MessagingPlatform, int> deliveriesByPlatform;
  final List<MapEntry<String, int>> accountActivity;
  final Map<CampaignStatus, int> campaignStatus;
  final List<Map<String, Object?>> campaigns;
  final List<Map<String, Object?>> deliveries;
  final List<ActivityEvent> events;
}

/// CSV with a UTF-8 BOM so spreadsheet apps read Persian text correctly.
String toCsv(List<String> headers, List<List<Object?>> rows) {
  String cell(Object? v) {
    final s = v?.toString() ?? '';
    return (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r'))
        ? '"${s.replaceAll('"', '""')}"'
        : s;
  }

  final b = StringBuffer('\uFEFF')..writeln(headers.map(cell).join(','));
  for (final r in rows) {
    b.writeln(r.map(cell).join(','));
  }
  return b.toString();
}

String toJsonText(List<String> headers, List<List<Object?>> rows) => const JsonEncoder.withIndent('  ').convert([
      for (final r in rows) {for (var i = 0; i < headers.length; i++) headers[i]: r[i]},
    ]);

/// Exports never include credentials: no query here touches `credential_reference`.
class ReportsRepository {
  ReportsRepository(this._db);

  final Database _db;

  (String, List<Object?>) _where(
    ReportFilter f, {
    String? date,
    String? platform,
    String? account,
    String? campaign,
    String? status,
    String? severity,
  }) {
    final c = <String>[];
    final a = <Object?>[];
    if (date != null && f.days != null) {
      c.add('$date >= ?');
      a.add(DateTime.now().toUtc().subtract(Duration(days: f.days!)).toIso8601String());
    }
    if (platform != null && f.platform != null) {
      c.add('$platform = ?');
      a.add(f.platform!.dbValue);
    }
    if (account != null && f.accountId != null) {
      c.add('$account = ?');
      a.add(f.accountId);
    }
    if (campaign != null && f.campaignId != null) {
      c.add('$campaign = ?');
      a.add(f.campaignId);
    }
    if (status != null && f.deliveryStatus != null) {
      c.add('$status = ?');
      a.add(f.deliveryStatus!.dbValue);
    }
    if (severity != null && f.severity != null) {
      c.add('$severity = ?');
      a.add(f.severity!.dbValue);
    }
    return (c.isEmpty ? '' : 'WHERE ${c.join(' AND ')}', a);
  }

  static int _i(Object? v) => (v as int?) ?? 0;

  static const _deliveryFrom = '''
FROM delivery_records d
JOIN campaigns c ON c.id = d.campaign_id
JOIN accounts a ON a.id = c.account_id
JOIN destinations ds ON ds.id = d.destination_id''';

  Future<ReportData> load(ReportFilter f) => guardDb(() => _db.transaction((txn) async {
        // ---- accounts (current state, filtered by platform/account only)
        final (accW, accA) = _where(f, platform: 'platform', account: 'id');
        final accRows = await txn.rawQuery(
          'SELECT platform, COUNT(*) AS n, '
          "SUM(CASE WHEN connection_status='connected' THEN 1 ELSE 0 END) AS conn, "
          "SUM(CASE WHEN connection_status='disconnected' THEN 1 ELSE 0 END) AS disc "
          'FROM accounts $accW GROUP BY platform',
          accA,
        );
        final accountsByPlatform = {for (final p in MessagingPlatform.values) p: 0};
        var accTotal = 0, accConn = 0, accDisc = 0;
        for (final r in accRows) {
          accountsByPlatform[enumFromDb(MessagingPlatform.values, r['platform'])] = _i(r['n']);
          accTotal += _i(r['n']);
          accConn += _i(r['conn']);
          accDisc += _i(r['disc']);
        }
        final templates = Sqflite.firstIntValue(await txn.rawQuery(
              f.accountId == null
                  ? 'SELECT COUNT(*) FROM message_templates'
                  : 'SELECT COUNT(*) FROM message_templates WHERE account_id = ?',
              f.accountId == null ? null : [f.accountId],
            )) ??
            0;

        // ---- campaigns
        final (cW, cA) = _where(f, date: 'c.created_at', platform: 'a.platform', account: 'a.id', campaign: 'c.id');
        final campaignRows = await txn.rawQuery('''
SELECT c.id, c.name, c.status, c.created_at, c.started_at, c.completed_at,
       a.platform, COALESCE(a.display_name, a.account_identifier) AS account_name,
       (SELECT COUNT(*) FROM delivery_records x WHERE x.campaign_id = c.id AND x.status IN ('sent','delivered')) AS ok,
       (SELECT COUNT(*) FROM delivery_records x WHERE x.campaign_id = c.id AND x.status = 'failed') AS failed,
       (SELECT COUNT(*) FROM delivery_records x WHERE x.campaign_id = c.id AND x.status = 'skipped') AS skipped
FROM campaigns c JOIN accounts a ON a.id = c.account_id $cW ORDER BY c.id DESC LIMIT 300''', cA);
        final campaignStatus = {for (final s in CampaignStatus.values) s: 0};
        var cTotal = 0, cActive = 0, cDone = 0, cFailed = 0;
        for (final r in campaignRows) {
          final s = enumFromDb(CampaignStatus.values, r['status']);
          campaignStatus[s] = campaignStatus[s]! + 1;
          cTotal++;
          if (s == CampaignStatus.scheduled || s == CampaignStatus.running || s == CampaignStatus.paused) cActive++;
          if (s == CampaignStatus.completed) cDone++;
          if (s == CampaignStatus.failed) cFailed++;
        }

        // ---- deliveries
        final (dW, dA) = _where(f,
            date: 'd.created_at', platform: 'a.platform', account: 'a.id', campaign: 'c.id', status: 'd.status');
        final statusRows =
            await txn.rawQuery('SELECT d.status AS s, COUNT(*) AS n $_deliveryFrom $dW GROUP BY d.status', dA);
        var ok = 0, failed = 0, pending = 0, skipped = 0;
        for (final r in statusRows) {
          final n = _i(r['n']);
          switch (enumFromDb(DeliveryStatus.values, r['s'])) {
            case DeliveryStatus.sent:
            case DeliveryStatus.delivered:
              ok += n;
            case DeliveryStatus.failed:
              failed += n;
            case DeliveryStatus.pending:
            case DeliveryStatus.sending:
              pending += n;
            case DeliveryStatus.skipped:
              skipped += n;
          }
        }
        final dailyRows = await txn.rawQuery(
          "SELECT substr(d.created_at,1,10) AS day, "
          "SUM(CASE WHEN d.status IN ('sent','delivered') THEN 1 ELSE 0 END) AS ok, "
          "SUM(CASE WHEN d.status = 'failed' THEN 1 ELSE 0 END) AS failed "
          '$_deliveryFrom $dW GROUP BY day ORDER BY day',
          dA,
        );
        final byPlatformRows =
            await txn.rawQuery('SELECT a.platform AS p, COUNT(*) AS n $_deliveryFrom $dW GROUP BY a.platform', dA);
        final deliveriesByPlatform = {for (final p in MessagingPlatform.values) p: 0};
        for (final r in byPlatformRows) {
          deliveriesByPlatform[enumFromDb(MessagingPlatform.values, r['p'])] = _i(r['n']);
        }
        final activityRows = await txn.rawQuery(
          'SELECT COALESCE(a.display_name, a.account_identifier) AS name, COUNT(*) AS n '
          '$_deliveryFrom $dW GROUP BY a.id ORDER BY n DESC LIMIT 8',
          dA,
        );
        final deliveryRows = await txn.rawQuery('''
SELECT d.id, d.status, d.error_code, d.attempt_count, d.created_at, d.updated_at,
       c.name AS campaign, a.platform, COALESCE(a.display_name, a.account_identifier) AS account,
       COALESCE(ds.display_name, ds.platform_destination_id) AS destination
$_deliveryFrom $dW ORDER BY d.id DESC LIMIT 500''', dA);

        // ---- events
        final (eW, eA) = _where(f,
            date: 'e.created_at', platform: 'a.platform', account: 'e.account_id', campaign: 'e.campaign_id', severity: 'e.severity');
        final eventRows = await txn.rawQuery(
          'SELECT e.* FROM activity_events e LEFT JOIN accounts a ON a.id = e.account_id '
          '$eW ORDER BY e.created_at DESC, e.id DESC LIMIT 300',
          eA,
        );

        return ReportData(
          accountsTotal: accTotal,
          accountsConnected: accConn,
          accountsDisconnected: accDisc,
          templates: templates,
          campaignsTotal: cTotal,
          campaignsActive: cActive,
          campaignsCompleted: cDone,
          campaignsFailed: cFailed,
          deliveriesAttempted: ok + failed,
          deliveriesSuccess: ok,
          deliveriesFailed: failed,
          deliveriesPending: pending,
          deliveriesSkipped: skipped,
          daily: [for (final r in dailyRows) DayPoint(r['day']! as String, _i(r['ok']), _i(r['failed']))],
          accountsByPlatform: accountsByPlatform,
          deliveriesByPlatform: deliveriesByPlatform,
          accountActivity: [for (final r in activityRows) MapEntry(r['name']! as String, _i(r['n']))],
          campaignStatus: campaignStatus,
          campaigns: campaignRows.map((r) => Map<String, Object?>.of(r)).toList(),
          deliveries: deliveryRows.map((r) => Map<String, Object?>.of(r)).toList(),
          events: eventRows.map(ActivityEvent.fromMap).toList(),
        );
      }));

  // ------------------------------------------------------------- export rows

  static (List<String>, List<List<Object?>>) campaignTable(ReportData d) => (
        ['id', 'name', 'status', 'platform', 'account', 'successful', 'failed', 'skipped', 'created_at', 'started_at', 'completed_at'],
        [
          for (final r in d.campaigns)
            [r['id'], r['name'], r['status'], r['platform'], r['account_name'], r['ok'], r['failed'], r['skipped'], r['created_at'], r['started_at'], r['completed_at']],
        ],
      );

  static (List<String>, List<List<Object?>>) deliveryTable(ReportData d) => (
        ['id', 'campaign', 'platform', 'account', 'destination', 'status', 'error_code', 'attempts', 'created_at', 'updated_at'],
        [
          for (final r in d.deliveries)
            [r['id'], r['campaign'], r['platform'], r['account'], r['destination'], r['status'], r['error_code'], r['attempt_count'], r['created_at'], r['updated_at']],
        ],
      );

  static (List<String>, List<List<Object?>>) eventTable(ReportData d) => (
        ['id', 'created_at', 'type', 'severity', 'account_id', 'campaign_id', 'description'],
        [for (final e in d.events) [e.id, e.createdAt.toUtc().toIso8601String(), e.eventType, e.severity.dbValue, e.accountId, e.campaignId, e.description]],
      );
}

final reportsRepositoryProvider =
    Provider<ReportsRepository>((ref) => ReportsRepository(ref.watch(appDatabaseProvider).db));

final reportFilterProvider = StateProvider<ReportFilter>((ref) => const ReportFilter());

final reportDataProvider = FutureProvider.autoDispose<ReportData>(
  (ref) => ref.watch(reportsRepositoryProvider).load(ref.watch(reportFilterProvider)),
);

import 'package:sqflite/sqflite.dart';

import '../../../core/database/db_guard.dart';
import '../../../shared/enums/enums.dart';
import '../../../shared/models/campaign.dart';
import '../domain/dashboard_data.dart';

abstract class DashboardRepository {
  Future<DashboardStats> loadStats();
}

class SqliteDashboardRepository implements DashboardRepository {
  SqliteDashboardRepository(this._db);

  final Database _db;

  static int _int(Object? v) => (v as int?) ?? 0;

  @override
  Future<DashboardStats> loadStats() => guardDb(() => _db.transaction((txn) async {
        // One consistent snapshot for all numbers.
        final accountRows = await txn.rawQuery('''
SELECT platform,
       COUNT(*) AS total,
       SUM(CASE WHEN connection_status = 'connected' THEN 1 ELSE 0 END) AS connected,
       SUM(CASE WHEN connection_status = 'disconnected' THEN 1 ELSE 0 END) AS disconnected
FROM accounts GROUP BY platform''');

        final platforms = {
          for (final p in MessagingPlatform.values)
            p: PlatformStats(platform: p, total: 0, connected: 0),
        };
        var total = 0, connected = 0, disconnected = 0;
        for (final r in accountRows) {
          final p = enumFromDb(MessagingPlatform.values, r['platform']);
          final t = _int(r['total']);
          final c = _int(r['connected']);
          platforms[p] = PlatformStats(platform: p, total: t, connected: c);
          total += t;
          connected += c;
          disconnected += _int(r['disconnected']);
        }

        final templates = Sqflite.firstIntValue(
                await txn.rawQuery('SELECT COUNT(*) FROM message_templates')) ??
            0;

        final campaignRows =
            await txn.rawQuery('SELECT status, COUNT(*) AS c FROM campaigns GROUP BY status');
        var active = 0, completed = 0;
        for (final r in campaignRows) {
          final s = enumFromDb(CampaignStatus.values, r['status']);
          if (Campaign.activeStatuses.contains(s)) active += _int(r['c']);
          if (s == CampaignStatus.completed) completed += _int(r['c']);
        }

        final deliveryRows =
            await txn.rawQuery('SELECT status, COUNT(*) AS c FROM delivery_records GROUP BY status');
        var ok = 0, failed = 0, pending = 0;
        for (final r in deliveryRows) {
          final c = _int(r['c']);
          switch (enumFromDb(DeliveryStatus.values, r['status'])) {
            case DeliveryStatus.sent:
            case DeliveryStatus.delivered:
              ok += c;
            case DeliveryStatus.failed:
              failed += c;
            case DeliveryStatus.pending:
            case DeliveryStatus.sending:
              pending += c;
            case DeliveryStatus.skipped:
              break;
          }
        }

        return DashboardStats(
          totalAccounts: total,
          connectedAccounts: connected,
          disconnectedAccounts: disconnected,
          otherStateAccounts: total - connected - disconnected,
          platforms: platforms,
          totalTemplates: templates,
          activeCampaigns: active,
          completedCampaigns: completed,
          successfulDeliveries: ok,
          failedDeliveries: failed,
          pendingDeliveries: pending,
        );
      }));
}

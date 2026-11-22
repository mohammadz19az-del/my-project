import '../../../shared/enums/enums.dart';
import '../../../shared/models/activity_event.dart';

class PlatformStats {
  const PlatformStats({required this.platform, required this.total, required this.connected});

  final MessagingPlatform platform;
  final int total;
  final int connected;
}

/// All dashboard numbers come from database aggregates (nothing is invented).
/// Definitions:
/// * disconnected = status `disconnected`; otherStates = every other non-connected status
///   (connecting, auth required, expired, rate limited, unsupported, error, mock).
/// * active campaigns = scheduled + running + paused.
/// * successful deliveries = sent + delivered; pending = pending + sending.
class DashboardStats {
  const DashboardStats({
    required this.totalAccounts,
    required this.connectedAccounts,
    required this.disconnectedAccounts,
    required this.otherStateAccounts,
    required this.platforms,
    required this.totalTemplates,
    required this.activeCampaigns,
    required this.completedCampaigns,
    required this.successfulDeliveries,
    required this.failedDeliveries,
    required this.pendingDeliveries,
  });

  final int totalAccounts;
  final int connectedAccounts;
  final int disconnectedAccounts;
  final int otherStateAccounts;
  final Map<MessagingPlatform, PlatformStats> platforms;
  final int totalTemplates;
  final int activeCampaigns;
  final int completedCampaigns;
  final int successfulDeliveries;
  final int failedDeliveries;
  final int pendingDeliveries;

  bool get hasAnyAccounts => totalAccounts > 0;
}

class DashboardData {
  const DashboardData({required this.stats, required this.recentEvents, required this.loadedAt});

  final DashboardStats stats;
  final List<ActivityEvent> recentEvents;
  final DateTime loadedAt;
}

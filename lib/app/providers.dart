import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../features/accounts/data/account_repository.dart';
import '../features/campaigns/data/campaign_repository.dart';
import '../features/campaigns/data/delivery_repository.dart';
import '../features/campaigns/data/destination_repository.dart';
import '../features/groups/data/group_link_repository.dart';
import '../features/messages/data/message_template_repository.dart';
import '../features/reports/data/activity_repository.dart';
import '../features/settings/data/settings_repository.dart';

/// Overridden in bootstrap with the opened database.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider must be overridden in bootstrap'),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => SqliteAccountRepository(ref.watch(appDatabaseProvider).db),
);

final messageTemplateRepositoryProvider = Provider<MessageTemplateRepository>(
  (ref) => SqliteMessageTemplateRepository(ref.watch(appDatabaseProvider).db),
);

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => SqliteActivityRepository(ref.watch(appDatabaseProvider).db),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SqliteSettingsRepository(ref.watch(appDatabaseProvider).db),
);

final groupLinkRepositoryProvider = Provider<GroupLinkRepository>(
  (ref) => SqliteGroupLinkRepository(ref.watch(appDatabaseProvider).db),
);

final destinationRepositoryProvider = Provider<DestinationRepository>(
  (ref) => SqliteDestinationRepository(ref.watch(appDatabaseProvider).db),
);

final campaignRepositoryProvider = Provider<CampaignRepository>(
  (ref) => SqliteCampaignRepository(ref.watch(appDatabaseProvider).db),
);

final deliveryRepositoryProvider = Provider<DeliveryRepository>(
  (ref) => SqliteDeliveryRepository(ref.watch(appDatabaseProvider).db),
);

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tesla_org/core/database/app_database.dart';
import 'package:tesla_org/features/accounts/data/account_repository.dart';
import 'package:tesla_org/features/campaigns/data/campaign_repository.dart';
import 'package:tesla_org/features/campaigns/data/delivery_repository.dart';
import 'package:tesla_org/features/campaigns/data/destination_repository.dart';
import 'package:tesla_org/features/groups/data/group_link_repository.dart';
import 'package:tesla_org/features/messages/data/message_template_repository.dart';
import 'package:tesla_org/features/reports/data/activity_repository.dart';
import 'package:tesla_org/shared/enums/enums.dart';
import 'package:tesla_org/shared/models/account.dart';
import 'package:tesla_org/shared/models/message_template.dart';

/// In-memory database with every repository wired up, for repository tests.
class TestFixture {
  TestFixture._(this.appDb)
      : accounts = SqliteAccountRepository(appDb.db),
        templates = SqliteMessageTemplateRepository(appDb.db),
        groupLinks = SqliteGroupLinkRepository(appDb.db),
        destinations = SqliteDestinationRepository(appDb.db),
        campaigns = SqliteCampaignRepository(appDb.db),
        deliveries = SqliteDeliveryRepository(appDb.db),
        activity = SqliteActivityRepository(appDb.db);

  final AppDatabase appDb;
  final AccountRepository accounts;
  final MessageTemplateRepository templates;
  final GroupLinkRepository groupLinks;
  final DestinationRepository destinations;
  final CampaignRepository campaigns;
  final DeliveryRepository deliveries;
  final ActivityRepository activity;

  static Future<TestFixture> create() async {
    sqfliteFfiInit();
    final db = await AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    return TestFixture._(db);
  }

  Future<void> close() => appDb.close();

  Future<Account> account(MessagingPlatform platform, [String identifier = 'acc']) =>
      accounts.create(AccountInput(platform: platform, accountIdentifier: identifier));

  Future<MessageTemplate> template(int accountId, [String title = 'Template']) =>
      templates.create(MessageTemplateInput(accountId: accountId, title: title, body: 'Hello'));
}

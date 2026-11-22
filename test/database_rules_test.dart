import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tesla_org/core/database/app_database.dart';
import 'package:tesla_org/core/database/migrations.dart';
import 'package:tesla_org/core/errors/app_exception.dart';
import 'package:tesla_org/features/accounts/data/account_repository.dart';
import 'package:tesla_org/features/messages/data/message_template_repository.dart';
import 'package:tesla_org/features/reports/data/activity_repository.dart';
import 'package:tesla_org/shared/enums/enums.dart';
import 'package:tesla_org/shared/models/account.dart';
import 'package:tesla_org/shared/models/message_template.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDb;
  late AccountRepository accounts;
  late MessageTemplateRepository templates;
  late ActivityRepository activity;

  setUp(() async {
    appDb = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    accounts = SqliteAccountRepository(appDb.db);
    templates = SqliteMessageTemplateRepository(appDb.db);
    activity = SqliteActivityRepository(appDb.db);
  });

  tearDown(() => appDb.close());

  Future<Account> addAccount(MessagingPlatform p, String id) =>
      accounts.create(AccountInput(platform: p, accountIdentifier: id));

  test('schema version matches latest migration', () async {
    expect(await appDb.schemaVersion(), latestSchemaVersion);
  });

  test('repository enforces 10 accounts per platform, other platforms unaffected', () async {
    for (var i = 0; i < 10; i++) {
      await addAccount(MessagingPlatform.telegram, 'bot$i');
    }
    await expectLater(
      addAccount(MessagingPlatform.telegram, 'bot10'),
      throwsA(isA<LimitExceededException>()),
    );
    await addAccount(MessagingPlatform.whatsapp, 'wa0');
    final counts = await accounts.countByPlatform();
    expect(counts[MessagingPlatform.telegram], 10);
    expect(counts[MessagingPlatform.whatsapp], 1);
  });

  test('database trigger blocks the 11th account even when the repository is bypassed', () async {
    for (var i = 0; i < 10; i++) {
      await addAccount(MessagingPlatform.rubika, 'r$i');
    }
    await expectLater(
      appDb.db.insert('accounts', {'platform': 'rubika', 'account_identifier': 'raw'}),
      throwsA(predicate((e) => e.toString().contains('LIMIT_ACCOUNTS_PER_PLATFORM'))),
    );
  });

  test('duplicate (platform, identifier) is rejected', () async {
    await addAccount(MessagingPlatform.soroush, 'same');
    await expectLater(
      addAccount(MessagingPlatform.soroush, 'same'),
      throwsA(isA<DuplicateRecordException>()),
    );
  });

  test('20 templates per account, exact body preserved', () async {
    final a = await addAccount(MessagingPlatform.whatsapp, 'wa');
    const body = '  سلام Hello\n  چند خط  ';
    for (var i = 0; i < 20; i++) {
      await templates.create(MessageTemplateInput(accountId: a.id, title: 't$i', body: body));
    }
    final first = (await templates.listForAccount(a.id)).first;
    expect(first.body, body);
    await expectLater(
      templates.create(MessageTemplateInput(accountId: a.id, title: 'extra', body: 'x')),
      throwsA(isA<LimitExceededException>()),
    );
  });

  test('connection status change is audited; mock never sets last_connected_at', () async {
    final a = await addAccount(MessagingPlatform.telegram, 'bot');
    await accounts.updateConnectionStatus(a.id, ConnectionStatus.mockConnection);
    expect((await accounts.getById(a.id))!.lastConnectedAt, isNull);
    await accounts.updateConnectionStatus(a.id, ConnectionStatus.connected);
    expect((await accounts.getById(a.id))!.lastConnectedAt, isNotNull);

    final events = await activity.recent();
    expect(events.where((e) => e.eventType == 'account_connection_changed').length, 2);
  });

  test('delivery record requires granted consent and authorized destination', () async {
    final a = await addAccount(MessagingPlatform.telegram, 'bot');
    final t = await templates.create(
      MessageTemplateInput(accountId: a.id, title: 't', body: 'hello'),
    );
    final db = appDb.db;
    final campaignId = await db.insert(
      'campaigns',
      {'name': 'c', 'account_id': a.id, 'template_id': t.id},
    );
    final destId = await db.insert(
      'destinations',
      {'account_id': a.id, 'platform_destination_id': 'chat-1'},
    );
    await db.insert('campaign_destinations', {'campaign_id': campaignId, 'destination_id': destId});

    Future<int> insertDelivery(String key) => db.insert('delivery_records', {
          'campaign_id': campaignId,
          'destination_id': destId,
          'template_id': t.id,
          'idempotency_key': key,
        });

    await expectLater(
      insertDelivery('k1'),
      throwsA(predicate((e) => e.toString().contains('DELIVERY_CONSENT_REQUIRED'))),
    );
    await db.update('campaign_destinations',
        {'consent_status': 'granted', 'authorization_status': 'authorized'});
    await insertDelivery('k1');
    await expectLater(
      insertDelivery('k1'),
      throwsA(predicate((e) => e.toString().contains('UNIQUE'))),
    );
  });

  test('an account with campaign history cannot be deleted', () async {
    final a = await addAccount(MessagingPlatform.telegram, 'bot');
    final t = await templates.create(
      MessageTemplateInput(accountId: a.id, title: 't', body: 'hello'),
    );
    await appDb.db.insert('campaigns', {'name': 'c', 'account_id': a.id, 'template_id': t.id});
    await expectLater(
      accounts.delete(a.id),
      throwsA(isA<ConstraintViolationException>()),
    );
  });
}

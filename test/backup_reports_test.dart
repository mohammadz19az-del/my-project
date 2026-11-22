import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tesla_org/core/errors/app_exception.dart';
import 'package:tesla_org/core/security/credential_store.dart';
import 'package:tesla_org/core/storage/app_files.dart';
import 'package:tesla_org/features/campaigns/data/delivery_repository.dart';
import 'package:tesla_org/features/reports/reports_repository.dart';
import 'package:tesla_org/features/settings/backup_service.dart';
import 'package:tesla_org/shared/enums/enums.dart';
import 'package:tesla_org/shared/models/campaign.dart';
import 'package:tesla_org/shared/models/delivery_record.dart';
import 'package:tesla_org/shared/models/destination.dart';
import 'package:tesla_org/shared/models/group_link.dart';

import 'support/test_fixture.dart';

void main() {
  late TestFixture f;
  late InMemoryCredentialStore store;
  late Directory tmp;
  late BackupService backup;
  late int accountId;
  late int campaignId;

  setUp(() async {
    f = await TestFixture.create();
    store = InMemoryCredentialStore();
    tmp = await Directory.systemTemp.createTemp('tesla_files');
    backup = BackupService(db: f.appDb.db, store: store, files: AppFiles(() async => tmp));

    await store.write('cred_telegram_abc', {'bot_token': 'TOP-SECRET-TOKEN'});
    final a = await f.accounts.create(const AccountInput(
        platform: MessagingPlatform.telegram,
        accountIdentifier: '@backup_bot',
        displayName: 'سلام',
        credentialReference: 'cred_telegram_abc'));
    accountId = a.id;
    final t = await f.template(a.id);
    await f.groupLinks.create(GroupLinkInput(accountId: a.id, url: 'https://t.me/devs', title: 'Devs'));
    final c = await f.campaigns.create(CampaignInput(
        name: 'نمونه, "quoted"', accountId: a.id, templateId: t.id, sendIntervalSeconds: 3, rounds: 2));
    campaignId = c.id;
    final d = await f.destinations.create(DestinationInput(accountId: a.id, platformDestinationId: '555', displayName: 'Bob'));
    await f.campaigns.addDestination(c.id, d.id,
        consent: ConsentStatus.granted, authorization: AuthorizationStatus.authorized);
    for (final status in ['ok', 'bad', 'sim']) {
      final dest = status == 'ok'
          ? d
          : await f.destinations.create(DestinationInput(accountId: a.id, platformDestinationId: 'x$status'));
      if (status != 'ok') {
        await f.campaigns.addDestination(c.id, dest.id,
            consent: ConsentStatus.granted, authorization: AuthorizationStatus.authorized);
      }
      final r = (await f.deliveries.createOrGet(DeliveryInput(
        campaignId: c.id, destinationId: dest.id, templateId: t.id,
        idempotencyKey: DeliveryRepository.buildIdempotencyKey(campaignId: c.id, destinationId: dest.id, templateId: t.id),
      ))).record;
      await f.deliveries.markSending(r.id);
      if (status == 'ok') await f.deliveries.markSent(r.id, platformMessageId: 'm1');
      if (status == 'bad') await f.deliveries.markFailed(r.id, errorCode: 'TG_403');
      if (status == 'sim') await f.deliveries.markSkipped(r.id, reason: 'sim');
    }
  });

  tearDown(() async {
    await f.close();
    await tmp.delete(recursive: true);
  });

  group('backup & restore', () {
    test('a backup contains no credentials or credential references', () async {
      final json = await backup.createBackupJson();
      expect(json.contains('TOP-SECRET-TOKEN'), isFalse);
      expect(json.contains('cred_telegram_abc'), isFalse);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['format'], BackupService.format);
      expect(decoded['secretsIncluded'], false);
    });

    test('wipe then restore brings everything back (Persian text intact), secrets are gone', () async {
      final json = await backup.createBackupJson();
      final eventsBefore = (await f.activity.recent(limit: 1000)).length;

      await backup.wipeAll();
      expect(await f.accounts.list(), isEmpty);
      expect(store.length, 0);

      final counts = await backup.restoreFromJson(json);
      expect(counts['accounts'], 1);
      expect(counts['delivery_records'], 3);

      final accounts = await f.accounts.list();
      expect(accounts.single.displayName, 'سلام');
      expect(accounts.single.credentialReference, isNull);
      expect((await f.campaigns.getById(campaignId))!.name, 'نمونه, "quoted"');
      expect((await f.campaigns.getById(campaignId))!.rounds, 2);
      expect((await f.deliveries.listForCampaign(campaignId)).length, 3);
      expect((await f.groupLinks.listForAccount(accountId)).single.title, 'Devs');
      expect((await f.activity.recent(limit: 1000)).length, eventsBefore); // history not inflated by triggers
    });

    test('restore deletes the secrets of the data it replaces and writes a safety backup', () async {
      final json = await backup.createBackupJson();
      await backup.restoreFromJson(json);
      expect(await store.contains('cred_telegram_abc'), isFalse);
      final files = await backup.listBackups();
      expect(files.any((x) => x.path.contains('tesla_prerestore_')), isTrue);
    });

    test('invalid backups are rejected before anything changes', () async {
      final good = jsonDecode(await backup.createBackupJson()) as Map<String, dynamic>;
      Future<void> rejects(Object? data) => expectLater(
            backup.restoreFromJson(data is String ? data : jsonEncode(data)),
            throwsA(isA<ValidationException>().having((e) => e.code, 'code', ErrorCodes.backupInvalid)),
          );
      await rejects('not json');
      await rejects({...good, 'format': 'other'});
      await rejects({...good, 'schemaVersion': 999});
      final badTables = Map<String, dynamic>.from(good['tables'] as Map)..remove('campaigns');
      await rejects({...good, 'tables': badTables});
      final badColumn = jsonDecode(jsonEncode(good)) as Map<String, dynamic>;
      ((badColumn['tables'] as Map)['accounts'] as List).first['evil; DROP TABLE accounts'] = 1;
      await rejects(badColumn);
      expect((await f.accounts.list()).length, 1); // untouched
    });

    test('a restore that violates database rules rolls back completely', () async {
      final data = jsonDecode(await backup.createBackupJson()) as Map<String, dynamic>;
      final rows = (data['tables'] as Map)['accounts'] as List;
      final template = Map<String, dynamic>.from(rows.first as Map);
      for (var i = 0; i < 11; i++) {
        rows.add({...template, 'id': 100 + i, 'account_identifier': '@limit${i}_bot'});
      }
      await expectLater(backup.restoreFromJson(jsonEncode(data)), throwsA(isA<AppException>()));
      expect((await f.accounts.list()).length, 1);
      expect((await f.deliveries.listForCampaign(campaignId)).length, 3);
    });

    test('wipeAll removes records and stored credentials', () async {
      await backup.wipeAll();
      expect(await f.campaigns.list(), isEmpty);
      expect(await store.contains('cred_telegram_abc'), isFalse);
    });
  });

  group('reports', () {
    late ReportsRepository reports;
    setUp(() => reports = ReportsRepository(f.appDb.db));

    test('statistics come from stored records', () async {
      final d = await reports.load(const ReportFilter(days: null));
      expect(d.accountsTotal, 1);
      expect(d.templates, 1);
      expect(d.campaignsTotal, 1);
      expect(d.deliveriesSuccess, 1);
      expect(d.deliveriesFailed, 1);
      expect(d.deliveriesSkipped, 1);
      expect(d.deliveriesAttempted, 2);
      expect(d.deliveriesByPlatform[MessagingPlatform.telegram], 3);
      expect(d.accountsByPlatform[MessagingPlatform.rubika], 0);
      expect(d.daily.fold<int>(0, (s, p) => s + p.ok + p.failed), 2);
      expect(d.events, isNotEmpty);
    });

    test('filters narrow every figure', () async {
      final none = await reports.load(const ReportFilter(days: null, platform: MessagingPlatform.rubika));
      expect(none.deliveriesSuccess + none.deliveriesFailed + none.campaignsTotal, 0);

      final failed = await reports.load(const ReportFilter(days: null, deliveryStatus: DeliveryStatus.failed));
      expect(failed.deliveries.length, 1);
      expect(failed.deliveries.single['error_code'], 'TG_403');

      final byCampaign = await reports.load(ReportFilter(days: null, campaignId: campaignId));
      expect(byCampaign.deliveries.length, 3);
      final other = await reports.load(const ReportFilter(days: null, campaignId: 9999));
      expect(other.deliveries, isEmpty);

      final warnings = await reports.load(const ReportFilter(days: null, severity: EventSeverity.error));
      expect(warnings.events, isEmpty);
    });

    test('CSV escapes properly, is Excel-safe for Persian, and exports contain no credentials', () async {
      final d = await reports.load(const ReportFilter(days: null));
      final (headers, rows) = ReportsRepository.campaignTable(d);
      final csv = toCsv(headers, rows);
      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(csv.contains('"نمونه, ""quoted"""'), isTrue);
      expect(toCsv(['a'], [['x\ny']]).contains('"x\ny"'), isTrue);

      final json = jsonDecode(toJsonText(headers, rows)) as List;
      expect(json.single['name'], 'نمونه, "quoted"');

      for (final (h, r) in [
        ReportsRepository.campaignTable(d),
        ReportsRepository.deliveryTable(d),
        ReportsRepository.eventTable(d),
      ]) {
        final all = '$h$r'.toLowerCase();
        expect(all.contains('credential'), isFalse);
        expect(all.contains('top-secret'), isFalse);
      }
    });
  });
}

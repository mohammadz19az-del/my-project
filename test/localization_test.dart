import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tesla_org/core/errors/app_exception.dart';
import 'package:tesla_org/core/errors/error_messages.dart';
import 'package:tesla_org/core/localization/app_strings.dart';
import 'package:tesla_org/core/localization/strings_en.dart';
import 'package:tesla_org/core/localization/strings_fa.dart';
import 'package:tesla_org/core/widgets/status_chip.dart';
import 'package:tesla_org/integrations/common/platform_adapter.dart';
import 'package:tesla_org/shared/enums/enums.dart';

void main() {
  test('English and Persian tables have identical keys and placeholders', () {
    expect(stringsFa.keys.toSet(), stringsEn.keys.toSet());
    final ph = RegExp(r'\{\w+\}');
    for (final k in stringsEn.keys) {
      expect(ph.allMatches(stringsFa[k]!).map((m) => m[0]).toSet(),
          ph.allMatches(stringsEn[k]!).map((m) => m[0]).toSet(),
          reason: k);
    }
  });

  test('every enum value shown in the UI has a translation', () {
    for (final s in ConnectionStatus.values) {
      expect(stringsEn.containsKey(connectionStatusKey(s)), isTrue, reason: '$s');
    }
    for (final s in IntegrationStatus.values) {
      expect(stringsEn.containsKey(integrationStatusKey(s)), isTrue, reason: '$s');
    }
    for (final s in EventSeverity.values) {
      expect(stringsEn.containsKey('severity_${s.dbValue}'), isTrue, reason: '$s');
    }
  });

  test('every error code has a localized message', () {
    const codes = [
      ErrorCodes.limitAccountsPerPlatform,
      ErrorCodes.limitTemplatesPerAccount,
      ErrorCodes.limitGroupLinksPerAccount,
      ErrorCodes.groupPlatformMismatch,
      ErrorCodes.campaignTemplateAccountMismatch,
      ErrorCodes.campaignDestinationAccountMismatch,
      ErrorCodes.deliveryConsentRequired,
      ErrorCodes.duplicateRecord,
      ErrorCodes.foreignKey,
      ErrorCodes.checkConstraint,
      ErrorCodes.notFound,
      ErrorCodes.accountIdentifierRequired,
      ErrorCodes.templateTitleRequired,
      ErrorCodes.templateBodyRequired,
      ErrorCodes.databaseFailure,
      ErrorCodes.invalidCampaignTransition,
      ErrorCodes.campaignNotEditable,
      ErrorCodes.campaignNameRequired,
      ErrorCodes.campaignScheduleInvalid,
      ErrorCodes.groupLinkUrlRequired,
      ErrorCodes.destinationIdRequired,
      ErrorCodes.invalidDeliveryTransition,
      ErrorCodes.credentialStorageFailure,
      ErrorCodes.invalidAccountInput,
      ErrorCodes.campaignOptionsInvalid,
      ErrorCodes.campaignNoDestinations,
      ErrorCodes.templateDisabled,
      ErrorCodes.accountNotConnected,
      ErrorCodes.intervalTooShort,
      ErrorCodes.templateTooLong,
      ErrorCodes.backupInvalid,
      ErrorCodes.destinationInvalid,
    ];
    for (final c in codes) {
      expect(stringsEn.containsKey('error_${c.toLowerCase()}'), isTrue, reason: c);
    }
  });

  test('dynamic string families are fully translated', () {
    final keys = <String>[
      for (final s in CampaignStatus.values) 'campaign_status_${s.dbValue}',
      'campaign_status_interrupted',
      for (final s in DeliveryStatus.values) 'delivery_${s.dbValue}',
      for (final s in ValidationStatus.values) 'link_status_${s.dbValue}',
      for (final s in DestinationType.values) 'dtype_${s.dbValue}',
      for (final s in MessageLanguage.values) 'lang_${s.dbValue}',
      for (final p in MessagingPlatform.values) ...['platform_note_${p.dbValue}', 'destination_note_${p.dbValue}'],
      for (final k in AdapterCapabilities.keys) 'cap_$k',
      for (var i = 1; i <= 8; i++) ...['guide_${i}_title', 'guide_${i}_body'],
      for (final m in AdapterMode.values) 'adapter_mode_${m.name}',
    ];
    for (final k in keys) {
      expect(stringsEn.containsKey(k), isTrue, reason: k);
      expect(stringsFa.containsKey(k), isTrue, reason: k);
    }
  });

  test('unknown errors map to the generic message', () {
    const s = AppStrings(Locale('fa'));
    expect(localizedError(s, StateError('x')), stringsFa['error_generic']);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tesla_org/core/localization/app_strings.dart';
import 'package:tesla_org/core/widgets/motion_scope.dart';
import 'package:tesla_org/features/accounts/presentation/account_card.dart';
import 'package:tesla_org/integrations/common/platform_adapter.dart';
import 'package:tesla_org/shared/enums/enums.dart';
import 'package:tesla_org/shared/models/account.dart';

Account account(ConnectionStatus status, {MessagingPlatform platform = MessagingPlatform.rubika}) =>
    Account(
      id: 1,
      platform: platform,
      accountIdentifier: 'demo-id',
      displayName: 'Demo',
      connectionStatus: status,
      capabilitiesJson: '{}',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Widget host(Locale locale, Widget child) => MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MotionScope(
        enabled: false,
        child: Scaffold(body: SizedBox(width: 400, child: SingleChildScrollView(child: child))),
      ),
    );

void main() {
  setUpAll(() async => initializeDateFormatting());

  AccountCard card(Account a, AdapterMode mode, {VoidCallback? onPrimary}) => AccountCard(
        account: a,
        mode: mode,
        busy: false,
        onPrimary: onPrimary ?? () {},
        onMenu: (_) {},
      );

  testWidgets('mock connection is shown as simulated (English)', (tester) async {
    await tester.pumpWidget(host(
      const Locale('en'),
      card(account(ConnectionStatus.mockConnection), AdapterMode.mock),
    ));
    expect(find.text('Mock connection'), findsOneWidget);
    expect(find.text('Simulated connection: this is not a real account link.'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
  });

  testWidgets('pending platform says real connection is unavailable (Persian, RTL)', (tester) async {
    const fa = AppStrings(Locale('fa'));
    await tester.pumpWidget(host(
      const Locale('fa'),
      card(account(ConnectionStatus.unsupported, platform: MessagingPlatform.telegram), AdapterMode.pending),
    ));
    expect(find.text(fa.t('account_pending_notice')), findsOneWidget);
    expect(find.text(fa.t('account_reconnect')), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(AccountCard))), TextDirection.rtl);
  });

  testWidgets('primary button triggers the callback; disconnected shows Connect', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(
      const Locale('en'),
      card(account(ConnectionStatus.disconnected), AdapterMode.mock, onPrimary: () => taps++),
    ));
    await tester.tap(find.text('Connect'));
    expect(taps, 1);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tesla_org/core/localization/app_strings.dart';
import 'package:tesla_org/core/theme/app_colors.dart';
import 'package:tesla_org/core/utilities/formatters.dart';
import 'package:tesla_org/core/widgets/glow_card.dart';
import 'package:tesla_org/core/widgets/motion_scope.dart';
import 'package:tesla_org/core/widgets/responsive_wrap.dart';
import 'package:tesla_org/core/widgets/state_views.dart';
import 'package:tesla_org/core/widgets/stat_card.dart';

Widget host(Locale locale, Widget child) => MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MotionScope(enabled: false, child: Scaffold(body: child)),
    );

void main() {
  testWidgets('StatCard renders Persian text with RTL direction and Persian digits', (tester) async {
    const fa = Locale('fa');
    await tester.pumpWidget(host(
      fa,
      const StatCard(icon: Icons.groups_2_outlined, label: 'کل حساب‌ها', value: 1234, accent: AppColors.cyan),
    ));
    expect(find.text('کل حساب‌ها'), findsOneWidget);
    expect(find.text(formatNumberFor(fa, 1234)), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(StatCard))), TextDirection.rtl);
  });

  testWidgets('StatCard in English is LTR with grouped digits', (tester) async {
    await tester.pumpWidget(host(
      const Locale('en'),
      const StatCard(icon: Icons.link, label: 'Connected', value: 1234, accent: AppColors.emerald),
    ));
    expect(find.text('1,234'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(StatCard))), TextDirection.ltr);
  });

  testWidgets('GlowCard and EmptyState actions fire', (tester) async {
    var cardTaps = 0;
    var actionTaps = 0;
    await tester.pumpWidget(host(
      const Locale('en'),
      Column(children: [
        GlowCard(onTap: () => cardTaps++, child: const Text('card')),
        EmptyState(
          icon: Icons.inbox,
          title: 'Nothing',
          message: 'Empty',
          actionLabel: 'Add',
          onAction: () => actionTaps++,
        ),
      ]),
    ));
    await tester.tap(find.text('card'));
    await tester.tap(find.text('Add'));
    expect(cardTaps, 1);
    expect(actionTaps, 1);
  });

  test('responsiveColumns', () {
    expect(responsiveColumns(320, minItemWidth: 220, spacing: 16), 1);
    expect(responsiveColumns(700, minItemWidth: 220, spacing: 16), 3);
    expect(responsiveColumns(1200, minItemWidth: 220, spacing: 16), 5);
  });

  testWidgets('ResponsiveWrap splits width into equal columns', (tester) async {
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const keys = [Key('a'), Key('b'), Key('c'), Key('d')];
    await tester.pumpWidget(host(
      const Locale('en'),
      ResponsiveWrap(children: [for (final k in keys) SizedBox(key: k, height: 10)]),
    ));
    final expected = (700 - 16 * 2) / 3;
    expect(tester.getSize(find.byKey(keys[0])).width, closeTo(expected, 0.1));
    // 4th item wraps to a second row
    expect(tester.getTopLeft(find.byKey(keys[3])).dy, greaterThan(tester.getTopLeft(find.byKey(keys[0])).dy));
  });
}

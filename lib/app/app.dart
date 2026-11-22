import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/error_messages.dart';
import '../core/localization/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/motion_scope.dart';
import '../features/campaigns/campaign_engine.dart';
import '../features/settings/application/settings_controller.dart';
import 'router.dart';

const _localizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppStrings.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class TeslaApp extends ConsumerWidget {
  const TeslaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    ref.watch(engineStartupProvider); // recovers interrupted campaigns, runs the scheduler

    return settings.when(
      loading: () => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (error, _) {
        const strings = AppStrings(Locale('en'));
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: Center(child: Text(localizedError(strings, error)))),
        );
      },
      data: (s) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        onGenerateTitle: (context) => context.tr('app_title'),
        locale: s.locale, // Directionality (RTL for fa) follows the locale.
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        themeMode: s.themeMode,
        theme: AppTheme.build(Brightness.light, s.accent),
        darkTheme: AppTheme.build(Brightness.dark, s.accent),
        routerConfig: ref.watch(routerProvider),
        builder: (context, child) => MotionScope(
          enabled: s.shouldAnimate && !MediaQuery.disableAnimationsOf(context),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

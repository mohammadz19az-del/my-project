import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../core/database/app_database.dart';
import '../core/localization/app_strings.dart';
import '../core/logging/app_logger.dart';
import 'app.dart';
import 'providers.dart';

/// Initializes logging, the SQLite backend and the database, then starts the app.
/// If the database cannot be opened the app shows a failure screen and leaves
/// the data file untouched (it is never deleted or recreated automatically).
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();

  FlutterError.onError = (details) {
    AppLogger.error('Flutter framework error',
        error: details.exception, stackTrace: details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('Uncaught platform error', error: error, stackTrace: stack);
    return true;
  };

  AppDatabase database;
  try {
    initDatabaseFactory();
    database = await AppDatabase.open();
  } catch (e, s) {
    AppLogger.error('Database failed to open', error: e, stackTrace: s);
    runApp(BootFailureApp(detail: AppLogger.redact('$e')));
    return;
  }

  runApp(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      child: const TeslaApp(),
    ),
  );
}

class BootFailureApp extends StatelessWidget {
  const BootFailureApp({super.key, required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    const strings = AppStrings(Locale('en'));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.t('boot_failed_title'),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text(strings.t('boot_failed_body')),
                  const SizedBox(height: 12),
                  SelectableText(detail, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

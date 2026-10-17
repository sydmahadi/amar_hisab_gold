
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/app_settings.dart';
import 'services/money_db.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await MoneyDb.instance.init();
  await AppSettings.instance.init();

  runApp(const AmarHisabApp());

  _initializeNotifications();
}

Future<void> _initializeNotifications() async {
  try {
    final service = NotificationService.instance;
    await service.init();
    await service.requestPermission();
    await service.syncFinancialReminders();
  } catch (e, stackTrace) {
    debugPrint('NOTIFICATION ERROR: $e');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class AmarHisabApp extends StatefulWidget {
  const AmarHisabApp({super.key});

  @override
  State<AmarHisabApp> createState() => _AmarHisabAppState();
}

class _AmarHisabAppState extends State<AmarHisabApp> {
  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_settingsChanged);
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_settingsChanged);
    super.dispose();
  }

  void _settingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: settings.t('appName'),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode:
          settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const HomeScreen(),
    );
  }
}

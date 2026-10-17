
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/app_settings.dart';
import 'services/money_db.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AmarHisabApp());
}

class AmarHisabApp extends StatefulWidget {
  const AmarHisabApp({super.key});

  @override
  State<AmarHisabApp> createState() => _AmarHisabAppState();
}

class _AmarHisabAppState extends State<AmarHisabApp> {
  late Future<void> _startup;

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_settingsChanged);
    _startup = _initializeApp();
  }

  Future<void> _initializeApp() async {
    await MoneyDb.instance.init();
    await AppSettings.instance.init();
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
      title: 'আমার হিসাব',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode:
          settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: FutureBuilder<void>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('Startup Error')),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: SelectableText(
                  'অ্যাপ চালু করতে সমস্যা হয়েছে।\n\n'
                  '${snapshot.error}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
              ),
            );
          }

          _startNotificationsOnce();
          return const HomeScreen();
        },
      ),
    );
  }

  bool _notificationsStarted = false;

  void _startNotificationsOnce() {
    if (_notificationsStarted) return;
    _notificationsStarted = true;
    _initializeNotifications();
  }
}

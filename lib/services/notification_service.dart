
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const AndroidNotificationChannel _channel =
      AndroidNotificationChannel(
    'amar_hisab_reminders',
    'আমার হিসাব রিমাইন্ডার',
    description: 'দেনা-পাওনা, বাজেট ও সঞ্চয়ের রিমাইন্ডার',
    importance: Importance.max,
  );

  Future<void> init() async {
    if (_initialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(settings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(_channel);

    _initialized = true;
  }

  Future<bool?> requestPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    return androidPlugin?.requestNotificationsPermission();
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) {
      await init();
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'amar_hisab_reminders',
      'আমার হিসাব রিমাইন্ডার',
      channelDescription: 'দেনা-পাওনা, বাজেট ও সঞ্চয়ের রিমাইন্ডার',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _plugin.show(
      id,
      title,
      body,
      details,
    );
  }

  Future<void> showTestNotification() async {
    await showNotification(
      id: 1001,
      title: 'আমার হিসাব',
      body: 'নোটিফিকেশন ঠিকভাবে কাজ করছে।',
    );
  }
}

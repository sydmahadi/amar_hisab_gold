
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const String _channelId = 'amar_hisab_reminders';

  static const AndroidNotificationChannel _channel =
      AndroidNotificationChannel(
    _channelId,
    'Amar Hisab Reminders',
    description: 'Loan, budget and savings reminders',
    importance: Importance.max,
  );

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    // Bangladesh local time.
    tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const settings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(settings);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await android?.createNotificationChannel(_channel);
    _initialized = true;
  }

  Future<bool?> requestPermission() async {
    await init();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    return android?.requestNotificationsPermission();
  }

  NotificationDetails _details() {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      'Amar Hisab Reminders',
      channelDescription: 'Loan, budget and savings reminders',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    return const NotificationDetails(android: androidDetails);
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();

    await _plugin.show(
      id,
      title,
      body,
      _details(),
    );
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    await init();

    if (!scheduledDate.isAfter(DateTime.now())) {
      return;
    }

    final scheduledTime = tz.TZDateTime.from(
      scheduledDate,
      tz.local,
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledTime,
      _details(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: id.toString(),
    );
  }

  Future<void> cancelNotification(int id) async {
    await init();
    await _plugin.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await init();
    await _plugin.cancelAll();
  }

  Future<void> showTestNotification() async {
    await showNotification(
      id: 1001,
      title: 'আমার হিসাব',
      body: 'নোটিফিকেশন ঠিকভাবে কাজ করছে।',
    );
  }
}

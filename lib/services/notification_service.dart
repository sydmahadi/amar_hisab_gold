
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'money_db.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _syncing = false;

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
    tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
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
    const android = AndroidNotificationDetails(
      _channelId,
      'Amar Hisab Reminders',
      channelDescription: 'Loan, budget and savings reminders',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    return const NotificationDetails(android: android);
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(id, title, body, _details());
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    await init();

    if (!scheduledDate.isAfter(DateTime.now())) return;

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      _details(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: id.toString(),
    );
  }

  /// ডেটাবেসের ঋণ, DPS ও বাজেট থেকে রিমাইন্ডার তৈরি করে।
  Future<int> syncFinancialReminders() async {
    await init();

    if (_syncing) return 0;
    _syncing = true;

    try {
      // পুরোনো শিডিউল সরিয়ে বর্তমান ডেটা অনুযায়ী নতুন করে তৈরি।
      await _plugin.cancelAll();

      var scheduledCount = 0;
      final now = DateTime.now();

      Future<bool> scheduleIfFuture({
        required int id,
        required String title,
        required String body,
        required DateTime date,
      }) async {
        final reminderDate = DateTime(
          date.year,
          date.month,
          date.day,
          9,
        );

        if (!reminderDate.isAfter(DateTime.now())) return false;

        await scheduleNotification(
          id: id,
          title: title,
          body: body,
          scheduledDate: reminderDate,
        );
        return true;
      }

      // 1. সক্রিয় ঋণের শেষ তারিখ
      final loans = await MoneyDb.instance.getLoans(activeOnly: true);

      for (final loan in loans) {
        final dueText = loan['due_date']?.toString();
        if (dueText == null || dueText.isEmpty) continue;

        final dueDate = DateTime.tryParse(dueText);
        if (dueDate == null) continue;

        final loanId = (loan['id'] as num).toInt();
        final person = loan['person_name']?.toString() ?? '';
        final remaining =
            (loan['remaining'] as num?)?.toDouble() ?? 0;

        if (remaining <= 0) continue;

        final title = 'আমার হিসাব — ঋণের তারিখ';
        final body =
            '$person: ঋণ পরিশোধ/আদায়ের শেষ তারিখ ${dueDate.day}/${dueDate.month}/${dueDate.year}';

        // প্রতিটি ঋণের জন্য একটি নির্দিষ্ট Notification ID।
        if (await scheduleIfFuture(
          id: 100000 + loanId,
          title: title,
          body: body,
          date: dueDate,
        )) {
          scheduledCount++;
        }
      }

      // 2. DPS-এর পরবর্তী কিস্তির তারিখ
      final savings = await MoneyDb.instance.getSavings();

      for (final saving in savings) {
        final isDps = (saving['is_dps'] as num?)?.toInt() == 1;
        if (!isDps) continue;

        final dueText = saving['next_due_date']?.toString();
        if (dueText == null || dueText.isEmpty) continue;

        final dueDate = DateTime.tryParse(dueText);
        if (dueDate == null) continue;

        final savingId = (saving['id'] as num).toInt();
        final name = saving['name']?.toString() ?? 'DPS';
        final installment =
            (saving['installment_amount'] as num?)?.toDouble() ?? 0;

        final title = 'আমার হিসাব — DPS কিস্তি';
        final body =
            '$name: কিস্তি ৳${installment.toStringAsFixed(2)}। তারিখ ${dueDate.day}/${dueDate.month}/${dueDate.year}';

        if (await scheduleIfFuture(
          id: 200000 + savingId,
          title: title,
          body: body,
          date: dueDate,
        )) {
          scheduledCount++;
        }
      }

      // 3. বাজেট পর্যালোচনার মাসিক রিমাইন্ডার
      final currentBudgets =
          await MoneyDb.instance.getBudgets(month: now);

      final nextMonth = DateTime(now.year, now.month + 1, 1);
      final nextBudgets =
          await MoneyDb.instance.getBudgets(month: nextMonth);

      if (currentBudgets.isNotEmpty || nextBudgets.isNotEmpty) {
        var reminderDate = DateTime(now.year, now.month + 1, 0, 20);

        if (!reminderDate.isAfter(now)) {
          reminderDate = DateTime(now.year, now.month + 2, 0, 20);
        }

        await scheduleNotification(
          id: 900001,
          title: 'আমার হিসাব — বাজেট রিমাইন্ডার',
          body: 'আপনার মাসিক বাজেট ও খরচ পর্যালোচনা করুন।',
          scheduledDate: reminderDate,
        );
        scheduledCount++;
      }

      return scheduledCount;
    } finally {
      _syncing = false;
    }
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


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

  // প্রতি বকেয়ার জন্য due date-এর আগে ও পরে রিমাইন্ডার শিডিউল।
  static const int _loanBase = 1000000;
  static const int _savingsBase = 2000000;
  static const int _oldLoanBase = 100000;
  static const int _oldSavingsBase = 200000;

  static const int _beforeDueDays = 7;
  static const int _afterDueDays = 30;

  static const AndroidNotificationChannel _channel =
      AndroidNotificationChannel(
    _channelId,
    'Amar Hisab Reminders',
    description: 'Loan and DPS reminders',
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
      channelDescription: 'Loan and DPS reminders',
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

  DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _dateText(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  DateTime _day(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _atNine(DateTime date) {
    return DateTime(date.year, date.month, date.day, 9);
  }

  double _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _cancelPreviousFinancialReminders() async {
    final pending = await _plugin.pendingNotificationRequests();

    for (final item in pending) {
      final id = item.id;

      final isOldLoan = id >= _oldLoanBase && id < _oldSavingsBase;
      final isOldSavings = id >= _oldSavingsBase && id < _loanBase;
      final isLoan = id >= _loanBase && id < _savingsBase;
      final isSavings = id >= _savingsBase && id < 3000000;

      if (isOldLoan || isOldSavings || isLoan || isSavings) {
        await _plugin.cancel(id);
      }
    }
  }

  Future<int> _scheduleDailyReminders({
    required int baseId,
    required int recordId,
    required DateTime dueDate,
    required String title,
    required String body,
  }) async {
    final today = _day(DateTime.now());
    final dueDay = _day(dueDate);

    // Due date-এর ৭ দিন আগে থেকে শুরু।
    // Due date পার হলে আজ থেকে পরবর্তী ৩০ দিন পর্যন্ত শিডিউল।
    var firstDay = dueDay.subtract(
      const Duration(days: _beforeDueDays),
    );

    if (firstDay.isBefore(today)) {
      firstDay = today;
    }

    final lastDay = dueDay.add(
      const Duration(days: _afterDueDays),
    );

    var count = 0;
    var index = 0;

    for (
      var date = firstDay;
      !date.isAfter(lastDay);
      date = date.add(const Duration(days: 1))
    ) {
      final scheduledAt = _atNine(date);

      // আজ সকাল ৯টা পার হলে আজকের notification না দিয়ে
      // পরের দিনের reminder রাখা হবে।
      if (!scheduledAt.isAfter(DateTime.now())) {
        index++;
        continue;
      }

      // প্রতিটি তারিখের notification-এর আলাদা ID।
      // record ID-এর জন্য 100টি ID-এর আলাদা ব্লক রাখা হয়েছে।
      final notificationId = baseId + recordId * 100 + index;

      await scheduleNotification(
        id: notificationId,
        title: title,
        body: '$body\nতারিখ: ${_dateText(date)}',
        scheduledDate: scheduledAt,
      );

      count++;
      index++;
    }

    return count;
  }

  Future<int> syncFinancialReminders() async {
    await init();

    if (_syncing) return 0;
    _syncing = true;

    try {
      // শুধু এই সার্ভিসের আর্থিক রিমাইন্ডার বাতিল হবে।
      // অন্য scheduled notification বাতিল হবে না।
      await _cancelPreviousFinancialReminders();

      var count = 0;

      final loans = await MoneyDb.instance.getLoansDueForReminder(
        daysAhead: 7,
      );

      for (final loan in loans) {
        final idValue = loan['id'];
        if (idValue is! num) continue;

        final dueDate = _parseDate(loan['due_date']);
        if (dueDate == null) continue;

        final remaining = _number(loan['remaining']);
        if (remaining <= 0) continue;

        final person = loan['person_name']?.toString().trim() ?? '';
        final type = loan['type']?.toString() ?? '';
        final receivable = type == 'receivable';

        final overdue = _day(dueDate).isBefore(_day(DateTime.now()));

        final title = overdue
            ? 'আমার হিসাব — মেয়াদোত্তীর্ণ বকেয়া'
            : 'আমার হিসাব — দেনা-পাওনা রিমাইন্ডার';

        final body = overdue
            ? '${person.isEmpty ? 'গ্রাহক' : person}: '
                '${receivable ? 'পাওনা' : 'দেনা'} '
                '${remaining.toStringAsFixed(2)} টাকা এখনো বাকি।'
            : '${person.isEmpty ? 'গ্রাহক' : person}: '
                '${receivable ? 'পাওনা আদায়' : 'দেনা পরিশোধ'}-এর '
                'তারিখ ${_dateText(dueDate)}। '
                'বাকি ${remaining.toStringAsFixed(2)} টাকা।';

        count += await _scheduleDailyReminders(
          baseId: _loanBase,
          recordId: idValue.toInt(),
          dueDate: dueDate,
          title: title,
          body: body,
        );
      }

      final savings = await MoneyDb.instance.getDpsDueForReminder(
        daysAhead: 7,
      );

      for (final saving in savings) {
        final idValue = saving['id'];
        if (idValue is! num) continue;

        final dueDate = _parseDate(saving['next_due_date']);
        if (dueDate == null) continue;

        final installment = _number(saving['installment_amount']);
        if (installment <= 0) continue;

        final name = saving['name']?.toString().trim() ?? '';
        final overdue = _day(dueDate).isBefore(_day(DateTime.now()));

        final title = overdue
            ? 'আমার হিসাব — DPS কিস্তি বকেয়া'
            : 'আমার হিসাব — DPS কিস্তি';

        final body = overdue
            ? '${name.isEmpty ? 'DPS' : name}: '
                '${installment.toStringAsFixed(2)} টাকার কিস্তি বাকি।'
            : '${name.isEmpty ? 'DPS' : name}: '
                '${installment.toStringAsFixed(2)} টাকার কিস্তি '
                '${_dateText(dueDate)} তারিখে।';

        count += await _scheduleDailyReminders(
          baseId: _savingsBase,
          recordId: idValue.toInt(),
          dueDate: dueDate,
          title: title,
          body: body,
        );
      }

      return count;
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
}

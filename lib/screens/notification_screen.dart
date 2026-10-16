
import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../services/notification_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final AppSettings _settings = AppSettings.instance;
  final NotificationService _notifications = NotificationService.instance;

  bool _enabled = true;
  bool _loading = false;

  bool get _bn => _settings.isBangla;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleNotifications(bool value) async {
    if (_loading) return;

    setState(() => _loading = true);

    try {
      if (value) {
        final granted = await _notifications.requestPermission();

        if (!mounted) return;

        if (granted == false) {
          setState(() => _enabled = false);
          _message(
            _bn
                ? 'ফোনের Settings থেকে নোটিফিকেশন অনুমতি চালু করুন।'
                : 'Enable notification permission in phone Settings.',
          );
          return;
        }

        setState(() => _enabled = true);
        _message(
          _bn ? 'নোটিফিকেশন চালু হয়েছে।' : 'Notifications enabled.',
        );
      } else {
        await _notifications.cancelAllNotifications();

        if (!mounted) return;

        setState(() => _enabled = false);
        _message(
          _bn
              ? 'বর্তমান সব নির্ধারিত নোটিফিকেশন বাতিল হয়েছে।'
              : 'All scheduled notifications have been cancelled.',
        );
      }
    } catch (e) {
      if (mounted) {
        _message(
          _bn ? 'নোটিফিকেশন সেট করতে সমস্যা হয়েছে।' : 'Could not update notifications.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendTestNotification() async {
    if (_loading) return;

    setState(() => _loading = true);

    try {
      final granted = await _notifications.requestPermission();

      if (!mounted) return;

      if (granted == false) {
        _message(
          _bn
              ? 'প্রথমে নোটিফিকেশনের অনুমতি দিন।'
              : 'Please grant notification permission first.',
        );
        return;
      }

      await _notifications.showTestNotification();

      if (!mounted) return;

      _message(
        _bn
            ? 'টেস্ট নোটিফিকেশন পাঠানো হয়েছে।'
            : 'Test notification sent.',
      );
    } catch (e) {
      if (mounted) {
        _message(
          _bn
              ? 'টেস্ট নোটিফিকেশন পাঠানো যায়নি।'
              : 'Could not send test notification.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scheduleTestReminder() async {
    if (_loading) return;

    final now = DateTime.now();
    final scheduledDate = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 2));

    setState(() => _loading = true);

    try {
      final granted = await _notifications.requestPermission();

      if (!mounted) return;

      if (granted == false) {
        _message(
          _bn
              ? 'প্রথমে নোটিফিকেশনের অনুমতি দিন।'
              : 'Please grant notification permission first.',
        );
        return;
      }

      await _notifications.scheduleNotification(
        id: 1002,
        title: _bn ? 'আমার হিসাব' : 'Amar Hisab',
        body: _bn
            ? 'এটি আপনার পরীক্ষামূলক রিমাইন্ডার।'
            : 'This is your test reminder.',
        scheduledDate: scheduledDate,
      );

      if (!mounted) return;

      _message(
        _bn
            ? '২ মিনিট পরের রিমাইন্ডার সেট হয়েছে।'
            : 'A reminder has been scheduled for 2 minutes from now.',
      );
    } catch (e) {
      if (mounted) {
        _message(
          _bn ? 'রিমাইন্ডার সেট করা যায়নি।' : 'Could not schedule reminder.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final dark = _settings.isDarkMode;
    final primary = dark
        ? const Color(0xFF176B45)
        : const Color(0xFF0F5132);
    final gold = const Color(0xFFC9A45C);
    final surface = Theme.of(context).colorScheme.surface;
    final textColor = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: Text(_bn ? 'নোটিফিকেশন' : 'Notifications'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  color: Color(0xFFC9A45C),
                  size: 44,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _bn ? 'রিমাইন্ডার সেন্টার' : 'Reminder Center',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _bn
                            ? 'আপনার গুরুত্বপূর্ণ হিসাবের কথা মনে রাখুন।'
                            : 'Keep track of important financial reminders.',
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            color: surface,
            child: SwitchListTile(
              value: _enabled,
              onChanged: _loading ? null : _toggleNotifications,
              activeTrackColor: primary,
              secondary: Icon(
                Icons.notifications_rounded,
                color: primary,
              ),
              title: Text(
                _bn ? 'নোটিফিকেশন অনুমতি' : 'Notification controls',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _bn
                    ? 'চালু করলে অনুমতি চাইবে; বন্ধ করলে নির্ধারিত নোটিফিকেশন বাতিল হবে।'
                    : 'Enable permission or cancel scheduled notifications.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          _sectionTitle(
            _bn ? 'পরীক্ষা ও রিমাইন্ডার' : 'Test and reminders',
            textColor,
          ),
          const SizedBox(height: 8),
          Card(
            color: surface,
            child: ListTile(
              leading: Icon(Icons.send_rounded, color: primary),
              title: Text(
                _bn ? 'টেস্ট নোটিফিকেশন' : 'Test notification',
              ),
              subtitle: Text(
                _bn
                    ? 'এখনই একটি পরীক্ষামূলক নোটিফিকেশন পাঠান।'
                    : 'Send a test notification immediately.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _loading ? null : _sendTestNotification,
            ),
          ),
          Card(
            color: surface,
            child: ListTile(
              leading: Icon(Icons.alarm_rounded, color: primary),
              title: Text(
                _bn ? 'টেস্ট রিমাইন্ডার' : 'Test reminder',
              ),
              subtitle: Text(
                _bn
                    ? '২ মিনিট পর একটি পরীক্ষামূলক রিমাইন্ডার।'
                    : 'Schedule a test reminder in 2 minutes.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _loading ? null : _scheduleTestReminder,
            ),
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: gold.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: gold),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _bn
                        ? 'দ্রষ্টব্য: এই স্ক্রিনে পরীক্ষামূলক নোটিফিকেশন ও রিমাইন্ডার আছে। দেনা-পাওনা বা বাজেটের তথ্য থেকে স্বয়ংক্রিয় রিমাইন্ডার তৈরি করতে আলাদা সংযোগ প্রয়োজন।'
                        : 'Note: This screen provides test notifications and reminders. Automatic loan and budget reminders require additional integration.',
                    style: TextStyle(
                      color: textColor,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8),
      child: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

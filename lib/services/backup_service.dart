
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'money_db.dart';

/// Backup and restore service for Amar Hisab.
class BackupService {
  BackupService._();

  static final BackupService instance = BackupService._();

  static const MethodChannel _channel =
      MethodChannel('amar_hisab/backup');

  static const String _lastBackupKey =
      'amar_hisab_last_backup_date';

  static const String _folderSelectedKey =
      'amar_hisab_backup_folder_selected';

  static const String _autoBackupEnabledKey =
      'amar_hisab_auto_backup_enabled';

  static const String _backupPrefix = 'amar_hisab_backup_';

  /// Whether weekly automatic backup is enabled.
  Future<bool> isAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoBackupEnabledKey) ?? true;
  }

  Future<void> setAutoBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoBackupEnabledKey, enabled);
  }

  /// Returns the date of the most recent successful backup.
  Future<DateTime?> getLastBackupDate() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_lastBackupKey);

    if (value == null || value.isEmpty) return null;

    return DateTime.tryParse(value);
  }

  /// Requests permission to use a folder chosen by the user.
  ///
  /// The native Android SAF implementation will be added in the
  /// next step. The selected folder must remain accessible after
  /// the app is closed or restarted.
  Future<bool> chooseBackupFolder() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'chooseBackupFolder',
      );

      if (result != true) return false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_folderSelectedKey, true);

      return true;
    } on PlatformException catch (e) {
      throw Exception(
        'ব্যাকআপ ফোল্ডার নির্বাচন করা যায়নি: ${e.message ?? e.code}',
      );
    } on MissingPluginException {
      throw Exception(
        'Android backup integration এখনো যুক্ত করা হয়নি। '
        'পরবর্তী ধাপে এটি যুক্ত করা হবে।',
      );
    }
  }

  Future<bool> hasBackupFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_folderSelectedKey) ?? false;
  }

  /// Creates a JSON backup containing all supported database tables.
  Future<String> createBackupJson({
    Map<String, dynamic> settings = const {},
  }) async {
    final json = await MoneyDb.instance.exportBackup(
      settings: settings,
    );

    // Validate that the generated JSON can be decoded.
    final decoded = jsonDecode(json);

    if (decoded is! Map<String, dynamic> ||
        decoded['app'] != 'AmarHisab' ||
        decoded['tables'] is! Map) {
      throw Exception('ব্যাকআপ তৈরি করা যায়নি: তথ্য যাচাই ব্যর্থ।');
    }

    return json;
  }

  /// Saves the backup in the previously selected phone folder.
  ///
  /// Requires the native Android SAF integration from the next step.
  Future<String> saveBackupToPhone({
    Map<String, dynamic> settings = const {},
  }) async {
    if (!await hasBackupFolder()) {
      throw Exception('প্রথমে ব্যাকআপ রাখার ফোল্ডার নির্বাচন করো।');
    }

    final json = await createBackupJson(settings: settings);
    final now = DateTime.now();

    final filename = '$_backupPrefix'
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}.json';

    try {
      await _channel.invokeMethod<bool>(
        'saveBackupToFolder',
        <String, dynamic>{
          'filename': filename,
          'content': json,
        },
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastBackupKey,
        now.toIso8601String(),
      );

      return filename;
    } on PlatformException catch (e) {
      throw Exception(
        'ব্যাকআপ সংরক্ষণ করা যায়নি: ${e.message ?? e.code}',
      );
    } on MissingPluginException {
      throw Exception(
        'Android backup integration এখনো যুক্ত করা হয়নি।',
      );
    }
  }

  /// Lets the user export a backup to a location they choose.
  Future<String?> exportBackupFile({
    Map<String, dynamic> settings = const {},
  }) async {
    final json = await createBackupJson(settings: settings);
    final now = DateTime.now();

    final filename = '$_backupPrefix'
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}.json';

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'আমার হিসাব ব্যাকআপ সংরক্ষণ করুন',
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: utf8.encode(json),
    );

    if (path == null) return null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastBackupKey,
      now.toIso8601String(),
    );

    return path;
  }

  /// Opens a JSON backup file and restores the database.
  ///
  /// The caller must ask the user for confirmation before calling
  /// this method, because restoration replaces existing records.
  Future<Map<String, dynamic>> restoreFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'আমার হিসাব ব্যাকআপ ফাইল নির্বাচন করুন',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      throw Exception('কোনো ব্যাকআপ ফাইল নির্বাচন করা হয়নি।');
    }

    final file = result.files.single;
    final bytes = file.bytes;

    if (bytes == null || bytes.isEmpty) {
      throw Exception('ব্যাকআপ ফাইলটি খোলা যাচ্ছে না বা খালি।');
    }

    final json = utf8.decode(bytes, allowMalformed: false);

    // MoneyDb validates the backup structure and restores it
    // inside a database transaction.
    final restoredSettings =
        await MoneyDb.instance.restoreBackup(json);

    return restoredSettings;
  }

  /// Runs a backup if at least seven days have passed.
  ///
  /// Call this when the app starts. For scheduled execution while
  /// the app is closed, Android WorkManager integration is required.
  Future<String?> runWeeklyBackupIfDue({
    Map<String, dynamic> settings = const {},
  }) async {
    if (!await isAutoBackupEnabled()) return null;
    if (!await hasBackupFolder()) return null;

    final lastBackup = await getLastBackupDate();
    final now = DateTime.now();

    if (lastBackup != null &&
        now.difference(lastBackup).inDays < 7) {
      return null;
    }

    return saveBackupToPhone(settings: settings);
  }
}

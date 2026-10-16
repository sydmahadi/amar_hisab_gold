
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
        'Android backup integration এখনো যুক্ত করা হয়নি।',
      );
    }
  }

  Future<bool> hasBackupFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_folderSelectedKey) ?? false;
  }

  /// Creates a JSON backup containing supported database tables.
  Future<String> createBackupJson({
    Map<String, dynamic> settings = const {},
  }) async {
    final json = await MoneyDb.instance.exportBackup(
      settings: settings,
    );

    final decoded = jsonDecode(json);

    if (decoded is! Map<String, dynamic> ||
        decoded['app'] != 'AmarHisab' ||
        decoded['tables'] is! Map) {
      throw Exception(
        'ব্যাকআপ তৈরি করা যায়নি: তথ্য যাচাই ব্যর্থ।',
      );
    }

    return json;
  }

  /// Saves a backup to the previously selected phone folder.
  ///
  /// Requires the native Android SAF integration.
  Future<String> saveBackupToPhone({
    Map<String, dynamic> settings = const {},
  }) async {
    if (!await hasBackupFolder()) {
      throw Exception(
        'প্রথমে ব্যাকআপ রাখার ফোল্ডার নির্বাচন করো।',
      );
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
      final result = await _channel.invokeMethod<bool>(
        'saveBackupToFolder',
        <String, dynamic>{
          'filename': filename,
          'content': json,
        },
      );

      if (result != true) {
        throw Exception('ব্যাকআপ ফাইল সংরক্ষণ নিশ্চিত করা যায়নি।');
      }

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

  /// Exports a JSON backup using the system save-file dialog.
  Future<String?> exportBackupFile({
    Map<String, dynamic> settings = const {},
  }) async {
    final json = await createBackupJson(settings: settings);
    final now = DateTime.now();

    final filename = '$_backupPrefix'
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}.json';

    final path = await FilePicker.saveFile(
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

  /// Opens a JSON backup and restores the database.
  ///
  /// The caller should obtain user confirmation before restoration.
  Future<Map<String, dynamic>> restoreFromFile() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'আমার হিসাব ব্যাকআপ ফাইল নির্বাচন করুন',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (file == null) {
      throw Exception('কোনো ব্যাকআপ ফাইল নির্বাচন করা হয়নি।');
    }

    final bytes = await file.readAsBytes();

    if (bytes.isEmpty) {
      throw Exception('ব্যাকআপ ফাইলটি খালি।');
    }

    late final String json;

    try {
      json = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw Exception(
        'ব্যাকআপ ফাইলের লেখা সঠিক UTF-8 ফরম্যাটে নেই।',
      );
    }

    // MoneyDb validates the backup and performs the restoration.
    // Existing records are replaced according to MoneyDb's logic.
    final restoredSettings =
        await MoneyDb.instance.restoreBackup(json);

    return restoredSettings;
  }

  /// Runs a backup if at least seven days have passed.
  ///
  /// For execution while the app is closed, Android WorkManager
  /// integration is required.
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

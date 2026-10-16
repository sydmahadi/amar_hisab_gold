
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'money_db.dart';

class BackupService {
  BackupService._();

  static final BackupService instance = BackupService._();

  static const MethodChannel _channel =
      MethodChannel('amar_hisab/backup');

  static const String _lastBackupDateKey =
      'amar_hisab_last_backup_date';

  static const String _backupFolderKey =
      'amar_hisab_backup_folder';

  static const String _autoBackupEnabledKey =
      'amar_hisab_auto_backup_enabled';

  static const String _backupPrefix = 'amar_hisab_backup_';

  Future<bool> isAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoBackupEnabledKey) ?? true;
  }

  Future<void> setAutoBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoBackupEnabledKey, enabled);
  }

  Future<DateTime?> getLastBackupDate() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_lastBackupDateKey);

    if (value == null || value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  Future<bool> chooseBackupFolder() async {
    final result = await _channel.invokeMethod<bool>(
      'chooseBackupFolder',
    );

    if (result == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_backupFolderKey, true);
      return true;
    }

    return false;
  }

  Future<bool> hasBackupFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_backupFolderKey) ?? false;
  }

  Future<String> createBackupJson() async {
    final settings = await SharedPreferences.getInstance();

    final backupData = await MoneyDb.instance.exportBackup(
      settings: settings,
    );

    final decoded = jsonDecode(backupData);

    if (decoded is! Map<String, dynamic> ||
        decoded['app'] != 'AmarHisab' ||
        decoded['tables'] is! Map) {
      throw Exception('ব্যাকআপ ডেটার ফরম্যাট সঠিক নয়।');
    }

    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  Future<bool> saveBackupToPhone() async {
    if (!await hasBackupFolder()) {
      throw Exception('আগে ব্যাকআপ ফোল্ডার নির্বাচন করুন।');
    }

    final json = await createBackupJson();
    final now = DateTime.now();

    final timestamp =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';

    final filename = '$_backupPrefix$timestamp.json';

    final result = await _channel.invokeMethod<bool>(
      'saveBackupToFolder',
      <String, dynamic>{
        'filename': filename,
        'content': json,
      },
    );

    if (result != true) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastBackupDateKey,
      now.toIso8601String(),
    );

    return true;
  }

  Future<String?> exportBackupFile() async {
    final json = await createBackupJson();

    final now = DateTime.now();

    final timestamp =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';

    final filename = '$_backupPrefix$timestamp.json';

    final path = await FilePicker.saveFile(
      dialogTitle: 'আমার হিসাব ব্যাকআপ সংরক্ষণ করুন',
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: utf8.encode(json),
    );

    if (path == null || path.isEmpty) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastBackupDateKey,
      now.toIso8601String(),
    );

    return path;
  }

  Future<Map<String, dynamic>?> restoreFromFile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'আমার হিসাব ব্যাকআপ ফাইল নির্বাচন করুন',
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final bytes = file.bytes ?? await file.readAsBytes();
    final jsonString = utf8.decode(bytes);

    final decoded = jsonDecode(jsonString);

    if (decoded is! Map<String, dynamic> ||
        decoded['app'] != 'AmarHisab' ||
        decoded['tables'] is! Map) {
      throw Exception('নির্বাচিত ফাইলটি সঠিক আমার হিসাব ব্যাকআপ নয়।');
    }

    final restoredSettings =
        await MoneyDb.instance.restoreBackup(jsonString);

    return restoredSettings;
  }

  Future<bool> runWeeklyBackupIfDue() async {
    if (!await isAutoBackupEnabled()) {
      return false;
    }

    if (!await hasBackupFolder()) {
      return false;
    }

    final lastBackup = await getLastBackupDate();
    final now = DateTime.now();

    if (lastBackup != null &&
        now.difference(lastBackup).inDays < 7) {
      return false;
    }

    return saveBackupToPhone();
  }
}

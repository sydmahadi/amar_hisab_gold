
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/money_db.dart';

class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});

  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  static const String _passwordKey = 'savings_password_hash';
  static const String _recoveryKey = 'savings_recovery_hash';

  bool _authorized = false;
  bool _loading = true;
  List<Map<String, Object?>> _savings = [];

  bool get _bn =>
      Localizations.localeOf(context).languageCode == 'bn';

  String _hash(String value) =>
      sha256.convert(value.trim().codeUnits).toString();

  String _text(String bn, String en) => _bn ? bn : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _start();
    });
  }

  Future<void> _start() async {
    final prefs = await SharedPreferences.getInstance();
    final savedHash = prefs.getString(_passwordKey);

    if (savedHash == null) {
      await _setupPassword();
    } else {
      await _login();
    }

    if (!mounted) return;

    if (_authorized) {
      await _initializeSavingsTable();
      await _loadSavings();
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  bool _validPassword(String value) {
    return value.length >= 6 &&
        RegExp(r'[A-Za-z]').hasMatch(value) &&
        RegExp(r'[0-9]').hasMatch(value);
  }

  String _generateRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();

    return List.generate(
      12,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  Future<void> _setupPassword() async {
    final password = TextEditingController();
    final confirm = TextEditingController();
    String? error;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(_text('Savings Password সেট করুন',
                  'Set Savings Password')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _text(
                        'পাসওয়ার্ডে অন্তত ৬টি অক্ষর থাকতে হবে এবং কমপক্ষে একটি ইংরেজি অক্ষর ও একটি সংখ্যা থাকতে হবে।',
                        'Use at least 6 characters, including an English letter and a number.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _text('নতুন পাসওয়ার্ড',
                            'New password'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirm,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _text('আবার লিখুন',
                            'Confirm password'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    if (!_validPassword(password.text)) {
                      setDialogState(() {
                        error = _text(
                          'অক্ষর ও সংখ্যা-সহ কমপক্ষে ৬টি অক্ষর দিন।',
                          'Use at least 6 characters with a letter and a number.',
                        );
                      });
                      return;
                    }

                    if (password.text != confirm.text) {
                      setDialogState(() {
                        error = _text(
                          'দুটি পাসওয়ার্ড মিলছে না।',
                          'Passwords do not match.',
                        );
                      });
                      return;
                    }

                    Navigator.pop(dialogContext, true);
                  },
                  child: Text(_text('সেট করুন', 'Set password')),
                ),
              ],
            );
          },
        );
      },
    );

    if (accepted != true || !mounted) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final recoveryCode = _generateRecoveryCode();
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_passwordKey, _hash(password.text));
    await prefs.setString(_recoveryKey, _hash(recoveryCode));

    password.dispose();
    confirm.dispose();

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(_text('Recovery Code সংরক্ষণ করুন',
            'Save your Recovery Code')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_text(
              'পাসওয়ার্ড ভুলে গেলে এই কোড প্রয়োজন হবে। এটি নিরাপদ জায়গায় লিখে রাখুন।',
              'You need this code if you forget your password. Store it somewhere safe.',
            )),
            const SizedBox(height: 16),
            SelectableText(
              recoveryCode,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: recoveryCode),
                );
              },
              icon: const Icon(Icons.copy),
              label: Text(_text('কপি করুন', 'Copy code')),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_text('সংরক্ষণ করেছি', 'I saved it')),
          ),
        ],
      ),
    );

    if (!mounted) return;
    setState(() => _authorized = true);
  }

  Future<void> _login() async {
    final prefs = await SharedPreferences.getInstance();
    final savedHash = prefs.getString(_passwordKey);

    if (savedHash == null) {
      await _setupPassword();
      return;
    }

    final password = TextEditingController();
    String? error;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(_text('Savings লক করা আছে',
                  'Savings is locked')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: password,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: _text('পাসওয়ার্ড',
                          'Password'),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) {
                      if (_hash(password.text) == savedHash) {
                        Navigator.pop(dialogContext, 'login');
                      } else {
                        setDialogState(() {
                          error = _text(
                            'পাসওয়ার্ড সঠিক নয়।',
                            'Incorrect password.',
                          );
                        });
                      }
                    },
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, 'reset'),
                  child: Text(_text(
                    'Recovery Code',
                    'Recovery Code',
                  )),
                ),
                FilledButton(
                  onPressed: () {
                    if (_hash(password.text) == savedHash) {
                      Navigator.pop(dialogContext, 'login');
                    } else {
                      setDialogState(() {
                        error = _text(
                          'পাসওয়ার্ড সঠিক নয়।',
                          'Incorrect password.',
                        );
                      });
                    }
                  },
                  child: Text(_text('খুলুন', 'Unlock')),
                ),
              ],
            );
          },
        );
      },
    );

    password.dispose();

    if (!mounted) return;

    if (result == 'login') {
      setState(() => _authorized = true);
    } else if (result == 'reset') {
      await _resetPassword();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _resetPassword() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRecovery = prefs.getString(_recoveryKey);

    if (savedRecovery == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final recovery = TextEditingController();
    final password = TextEditingController();
    final confirm = TextEditingController();
    String? error;

    final reset = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(_text(
                'পাসওয়ার্ড রিসেট',
                'Reset password',
              )),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: recovery,
                      decoration: InputDecoration(
                        labelText: _text(
                          'Recovery Code',
                          'Recovery Code',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _text(
                          'নতুন পাসওয়ার্ড',
                          'New password',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirm,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _text(
                          'আবার লিখুন',
                          'Confirm password',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, false),
                  child: Text(_text('বাতিল', 'Cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    if (_hash(recovery.text) != savedRecovery) {
                      setDialogState(() {
                        error = _text(
                          'Recovery Code সঠিক নয়।',
                          'Incorrect Recovery Code.',
                        );
                      });
                      return;
                    }

                    if (!_validPassword(password.text)) {
                      setDialogState(() {
                        error = _text(
                          'অক্ষর ও সংখ্যা-সহ কমপক্ষে ৬টি অক্ষর দিন।',
                          'Use at least 6 characters with a letter and a number.',
                        );
                      });
                      return;
                    }

                    if (password.text != confirm.text) {
                      setDialogState(() {
                        error = _text(
                          'দুটি পাসওয়ার্ড মিলছে না।',
                          'Passwords do not match.',
                        );
                      });
                      return;
                    }

                    Navigator.pop(dialogContext, true);
                  },
                  child: Text(_text('রিসেট', 'Reset')),
                ),
              ],
            );
          },
        );
      },
    );

    if (reset == true) {
      await prefs.setString(_passwordKey, _hash(password.text));
    }

    recovery.dispose();
    password.dispose();
    confirm.dispose();

    if (!mounted) return;

    if (reset == true) {
      await _login();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _initializeSavingsTable() async {
    final database = await MoneyDb.instance.db;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS savings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        goal_amount REAL NOT NULL DEFAULT 0,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _loadSavings() async {
    final database = await MoneyDb.instance.db;
    final rows = await database.query(
      'savings',
      orderBy: 'id DESC',
    );

    if (!mounted) return;

    setState(() {
      _savings = rows;
    });
  }

  double get _totalSavings {
    return _savings.fold<double>(
      0,
      (total, item) =>
          total + ((item['amount'] as num?)?.toDouble() ?? 0),
    );
  }

  Future<void> _addSaving() async {
    final title = TextEditingController();
    final amount = TextEditingController();
    final goal = TextEditingController();
    final note = TextEditingController();
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(_text('নতুন সঞ্চয়',
                  'New saving')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: title,
                      decoration: InputDecoration(
                        labelText: _text('সঞ্চয়ের নাম',
                            'Saving name'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _text('জমার পরিমাণ',
                            'Saved amount'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: goal,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _text('লক্ষ্যমাত্রা (ঐচ্ছিক)',
                            'Target amount (optional)'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: _text('নোট (ঐচ্ছিক)',
                            'Note (optional)'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, false),
                  child: Text(_text('বাতিল', 'Cancel')),
                ),
                FilledButton(
                  onPressed: () async {
                    final amountValue =
                        double.tryParse(amount.text.trim());
                    final goalValue = goal.text.trim().isEmpty
                        ? 0.0
                        : double.tryParse(goal.text.trim());

                    if (title.text.trim().isEmpty ||
                        amountValue == null ||
                        amountValue < 0 ||
                        goalValue == null ||
                        goalValue < 0) {
                      setDialogState(() {
                        error = _text(
                          'নাম ও সঠিক পরিমাণ লিখুন।',
                          'Enter a name and valid amounts.',
                        );
                      });
                      return;
                    }

                    final database = await MoneyDb.instance.db;

                    await database.insert('savings', {
                      'title': title.text.trim(),
                      'amount': amountValue,
                      'goal_amount': goalValue,
                      'note': note.text.trim(),
                      'created_at': DateTime.now().toIso8601String(),
                    });

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  child: Text(_text('সংরক্ষণ',
                      'Save')),
                ),
              ],
            );
          },
        );
      },
    );

    title.dispose();
    amount.dispose();
    goal.dispose();
    note.dispose();

    if (saved == true) {
      await _loadSavings();
    }
  }

  Future<void> _deleteSaving(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_text('সঞ্চয় মুছবেন?',
            'Delete saving?')),
        content: Text(_text(
          'এই সঞ্চয়ের রেকর্ড মুছে যাবে।',
          'This saving record will be deleted.',
        )),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: Text(_text('বাতিল', 'Cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: Text(_text('মুছুন', 'Delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final database = await MoneyDb.instance.db;
    await database.delete(
      'savings',
      where: 'id = ?',
      whereArgs: [id],
    );

    await _loadSavings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_text('সঞ্চয়', 'Savings')),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_authorized) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_text('সঞ্চয়', 'Savings')),
        ),
        body: Center(
          child: Text(_text(
            'সঞ্চয় খুলতে পাসওয়ার্ড প্রয়োজন।',
            'Password is required to open Savings.',
          )),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_text('সঞ্চয়', 'Savings')),
        actions: [
          IconButton(
            tooltip: _text('পাসওয়ার্ড পরিবর্তন',
                'Change password'),
            icon: const Icon(Icons.password_rounded),
            onPressed: _changePassword,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSaving,
        icon: const Icon(Icons.add),
        label: Text(_text('সঞ্চয় যোগ', 'Add saving')),
      ),
      body: RefreshIndicator(
        onRefresh: _loadSavings,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text('মোট সঞ্চয়', 'Total savings'),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _totalSavings.toStringAsFixed(2),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _text(
                        'রেকর্ড: ${_savings.length}টি',
                        'Records: ${_savings.length}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_savings.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    Icon(
                      Icons.savings_outlined,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _text(
                        'এখনও কোনো সঞ্চয় যোগ করা হয়নি।',
                        'No savings added yet.',
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._savings.map((item) {
                final id = item['id'] as int;
                final savedAmount =
                    (item['amount'] as num).toDouble();
                final target =
                    (item['goal_amount'] as num).toDouble();
                final progress = target > 0
                    ? (savedAmount / target).clamp(0.0, 1.0)
                    : 0.0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.savings_rounded,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      item['title'] as String,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        Text(
                          '${_text('জমা', 'Saved')}: '
                          '${savedAmount.toStringAsFixed(2)}',
                        ),
                        if (target > 0) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: progress),
                          const SizedBox(height: 4),
                          Text(
                            '${_text('লক্ষ্য', 'Target')}: '
                            '${target.toStringAsFixed(2)} '
                            '(${(progress * 100).toStringAsFixed(0)}%)',
                          ),
                        ],
                        if ((item['note'] as String).isNotEmpty)
                          Text(item['note'] as String),
                      ],
                    ),
                    trailing: IconButton(
                      tooltip: _text('মুছুন', 'Delete'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteSaving(id),
                    ),
                    isThreeLine: target > 0,
                  ),
                );
              }),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Future<void> _changePassword() async {
    final prefs = await SharedPreferences.getInstance();
    final oldHash = prefs.getString(_passwordKey);

    if (oldHash == null) return;

    final oldPassword = TextEditingController();
    final newPassword = TextEditingController();
    final confirmPassword = TextEditingController();
    String? error;

    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(_text(
                'পাসওয়ার্ড পরিবর্তন',
                'Change password',
              )),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: oldPassword,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _text(
                          'বর্তমান পাসওয়ার্ড',
                          'Current password',
                        ),
                      ),
                    ),
                    TextField(
                      controller: newPassword,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _text(
                          'নতুন পাসওয়ার্ড',
                          'New password',
                        ),
                      ),
                    ),
                    TextField(
                      controller: confirmPassword,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: _text(
                          'আবার লিখুন',
                          'Confirm password',
                        ),
                      ),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, false),
                  child: Text(_text('বাতিল', 'Cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    if (_hash(oldPassword.text) != oldHash) {
                      setDialogState(() {
                        error = _text(
                          'বর্তমান পাসওয়ার্ড সঠিক নয়।',
                          'Current password is incorrect.',
                        );
                      });
                      return;
                    }

                    if (!_validPassword(newPassword.text)) {
                      setDialogState(() {
                        error = _text(
                          'অক্ষর ও সংখ্যা-সহ কমপক্ষে ৬টি অক্ষর দিন।',
                          'Use at least 6 characters with a letter and a number.',
                        );
                      });
                      return;
                    }

                    if (newPassword.text != confirmPassword.text) {
                      setDialogState(() {
                        error = _text(
                          'দুটি পাসওয়ার্ড মিলছে না।',
                          'Passwords do not match.',
                        );
                      });
                      return;
                    }

                    Navigator.pop(dialogContext, true);
                  },
                  child: Text(_text('পরিবর্তন',
                      'Change')),
                ),
              ],
            );
          },
        );
      },
    );

    if (changed == true) {
      await prefs.setString(
        _passwordKey,
        _hash(newPassword.text),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_text(
              'পাসওয়ার্ড পরিবর্তন হয়েছে।',
              'Password changed.',
            )),
          ),
        );
      }
    }

    oldPassword.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
  }
}

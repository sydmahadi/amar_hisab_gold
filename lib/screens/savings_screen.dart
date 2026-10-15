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
  final Map<int, double> _balances = {};

  bool get _bn =>
      Localizations.localeOf(context).languageCode == 'bn';

  String _text(String bn, String en) => _bn ? bn : en;

  String _hash(String value) =>
      sha256.convert(value.trim().codeUnits).toString();

  bool _validPassword(String value) =>
      value.length >= 6 &&
      RegExp(r'[A-Za-z]').hasMatch(value) &&
      RegExp(r'[0-9]').hasMatch(value);

  String _generateRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();

    return List.generate(
      12,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  double _number(Object? value) =>
      value is num ? value.toDouble() : 0.0;

  int _id(Object? value) =>
      value is num ? value.toInt() : 0;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _start();
    });
  }

  Future<void> _start() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (prefs.getString(_passwordKey) == null) {
        await _setupPassword();
      } else {
        await _login();
      }

      if (!mounted) return;

      if (_authorized) {
        await _loadSavings();
      }
    } catch (e) {
      if (mounted) {
        _showMessage(
          '${_text('ত্রুটি', 'Error')}: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _setupPassword() async {
    final password = TextEditingController();
    final confirm = TextEditingController();
    String? error;

    try {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              _text(
                'সঞ্চয়ের পাসওয়ার্ড সেট করুন',
                'Set Savings Password',
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _text(
                      'কমপক্ষে ৬টি অক্ষর, একটি ইংরেজি অক্ষর ও একটি সংখ্যা দিন।',
                      'Use at least 6 characters, including an English letter and a number.',
                    ),
                  ),
                  const SizedBox(height: 14),
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
              FilledButton(
                onPressed: () {
                  if (!_validPassword(password.text)) {
                    setDialogState(() {
                      error = _text(
                        'কমপক্ষে ৬টি অক্ষর, একটি ইংরেজি অক্ষর ও একটি সংখ্যা দিন।',
                        'Use at least 6 characters, a letter and a number.',
                      );
                    });
                    return;
                  }

                  if (password.text != confirm.text) {
                    setDialogState(() {
                      error = _text(
                        'পাসওয়ার্ড দুটি মিলছে না।',
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
          ),
        ),
      );

      if (accepted != true || !mounted) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final recoveryCode = _generateRecoveryCode();
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(_passwordKey, _hash(password.text));
      await prefs.setString(_recoveryKey, _hash(recoveryCode));

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            _text(
              'Recovery Code সংরক্ষণ করুন',
              'Save your Recovery Code',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(
                  'পাসওয়ার্ড ভুলে গেলে এই কোড লাগবে। নিরাপদ জায়গায় লিখে রাখুন।',
                  'You need this code if you forget your password. Keep it somewhere safe.',
                ),
              ),
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
                  _showMessage(
                    _text('কোড কপি হয়েছে', 'Code copied'),
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
              child: Text(
                _text('সংরক্ষণ করেছি', 'I saved it'),
              ),
            ),
          ],
        ),
      );

      if (mounted) {
        setState(() => _authorized = true);
      }
    } finally {
      password.dispose();
      confirm.dispose();
    }
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

    try {
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              _text('সঞ্চয় লক করা আছে', 'Savings is locked'),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: password,
                  obscureText: true,
                  autofocus: true,
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
                  decoration: InputDecoration(
                    labelText: _text('পাসওয়ার্ড', 'Password'),
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
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, 'reset'),
                child: const Text('Recovery Code'),
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
          ),
        ),
      );

      if (!mounted) return;

      if (result == 'login') {
        setState(() => _authorized = true);
      } else if (result == 'reset') {
        await _resetPassword();
      } else {
        Navigator.pop(context);
      }
    } finally {
      password.dispose();
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

    try {
      final reset = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(_text('পাসওয়ার্ড রিসেট', 'Reset password')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: recovery,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Recovery Code',
                      border: OutlineInputBorder(),
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
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(_text('বাতিল', 'Cancel')),
              ),
              FilledButton(
                onPressed: () {
                  if (_hash(recovery.text.toUpperCase()) !=
                      savedRecovery) {
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
                        'কমপক্ষে ৬টি অক্ষর, একটি ইংরেজি অক্ষর ও একটি সংখ্যা দিন।',
                        'Use at least 6 characters, a letter and a number.',
                      );
                    });
                    return;
                  }

                  if (password.text != confirm.text) {
                    setDialogState(() {
                      error = _text(
                        'পাসওয়ার্ড দুটি মিলছে না।',
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
          ),
        ),
      );

      if (!mounted) return;

      if (reset == true) {
        await prefs.setString(
          _passwordKey,
          _hash(password.text),
        );
        await _login();
      } else {
        Navigator.pop(context);
      }
    } finally {
      recovery.dispose();
      password.dispose();
      confirm.dispose();
    }
  }

  Future<void> _loadSavings() async {
    try {
      final rows = await MoneyDb.instance.getSavings();
      final updatedSavings = <Map<String, Object?>>[];
      final balances = <int, double>{};

      for (final item in rows) {
        final row = Map<String, Object?>.from(item);
        final id = _id(row['id']);
        final balance = _number(row['current_amount']);

        updatedSavings.add(row);
        balances[id] = balance;
      }

      if (!mounted) return;

      setState(() {
        _savings = updatedSavings;
        _balances
          ..clear()
          ..addAll(balances);
      });
    } catch (e) {
      if (mounted) {
        _showMessage(
          '${_text('সঞ্চয়ের তথ্য লোড হয়নি', 'Could not load savings')}: $e',
        );
      }
    }
  }

  double get _totalSavings =>
      _balances.values.fold<double>(0, (sum, value) => sum + value);

  Future<void> _addSaving() async {
    final name = TextEditingController();
    final target = TextEditingController();
    final initialAmount = TextEditingController(text: '0');
    final note = TextEditingController();

    String? error;
    bool saving = false;

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(_text('নতুন সঞ্চয়', 'New saving')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: _text('সঞ্চয়ের নাম', 'Saving name'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: target,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _text(
                        'লক্ষ্যমাত্রা (ঐচ্ছিক)',
                        'Target amount (optional)',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: initialAmount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _text('প্রাথমিক জমা', 'Initial deposit'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: note,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: _text('নোট (ঐচ্ছিক)', 'Note (optional)'),
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
                onPressed: saving
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: Text(_text('বাতিল', 'Cancel')),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final targetValue = target.text.trim().isEmpty
                            ? 0.0
                            : double.tryParse(target.text.trim());
                        final initialValue =
                            double.tryParse(initialAmount.text.trim());

                        if (name.text.trim().isEmpty ||
                            targetValue == null ||
                            initialValue == null ||
                            targetValue < 0 ||
                            initialValue < 0) {
                          setDialogState(() {
                            error = _text(
                              'সঠিক নাম ও পরিমাণ লিখুন।',
                              'Enter a name and valid amounts.',
                            );
                          });
                          return;
                        }

                        setDialogState(() {
                          saving = true;
                          error = null;
                        });

                        try {
                          final id = await MoneyDb.instance.addSavings(
                            name: name.text.trim(),
                            targetAmount: targetValue,
                            note: note.text.trim().isEmpty
                                ? null
                                : note.text.trim(),
                          );

                          if (initialValue > 0) {
                            await MoneyDb.instance.addSavingsTransaction(
                              savingsId: id,
                              type: 'deposit',
                              amount: initialValue,
                              note: _text(
                                'প্রাথমিক জমা',
                                'Initial deposit',
                              ),
                            );
                          }

                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (e) {
                          setDialogState(() {
                            saving = false;
                            error =
                                '${_text('সংরক্ষণ করা যায়নি', 'Could not save')}: $e';
                          });
                        }
                      },
                child: Text(_text('সংরক্ষণ', 'Save')),
              ),
            ],
          ),
        ),
      );

      if (saved == true) await _loadSavings();
    } finally {
      name.dispose();
      target.dispose();
      initialAmount.dispose();
      note.dispose();
    }
  }

  Future<void> _addTransaction(
    int savingId, {
    required bool deposit,
  }) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    String? error;
    bool saving = false;

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              deposit
                  ? _text('টাকা জমা দিন', 'Deposit money')
                  : _text('টাকা উত্তোলন করুন', 'Withdraw money'),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _text('টাকার পরিমাণ', 'Amount'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(
                    labelText: _text('নোট (ঐচ্ছিক)', 'Note (optional)'),
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
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: Text(_text('বাতিল', 'Cancel')),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final amount =
                            double.tryParse(amountController.text.trim());

                        if (amount == null ||
                            !amount.isFinite ||
                            amount <= 0) {
                          setDialogState(() {
                            error = _text(
                              'সঠিক পরিমাণ লিখুন।',
                              'Enter a valid amount.',
                            );
                          });
                          return;
                        }

                        setDialogState(() {
                          saving = true;
                          error = null;
                        });

                        try {
                          await MoneyDb.instance.addSavingsTransaction(
                            savingsId: savingId,
                            type: deposit ? 'deposit' : 'withdrawal',
                            amount: amount,
                            note: noteController.text.trim().isEmpty
                                ? null
                                : noteController.text.trim(),
                          );

                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (e) {
                          setDialogState(() {
                            saving = false;
                            error =
                                '${_text('লেনদেন সংরক্ষণ হয়নি', 'Transaction failed')}: $e';
                          });
                        }
                      },
                child: Text(_text('নিশ্চিত করুন', 'Confirm')),
              ),
            ],
          ),
        ),
      );

      if (saved == true) await _loadSavings();
    } finally {
      amountController.dispose();
      noteController.dispose();
    }
  }

  Future<void> _showTransactions(
    int savingId,
    String savingName,
  ) async {
    try {
      final transactions =
          await MoneyDb.instance.getSavingsTransactions(savingId);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(savingName),
          content: SizedBox(
            width: double.maxFinite,
            child: transactions.isEmpty
                ? Text(
                    _text(
                      'কোনো লেনদেন নেই।',
                      'No transactions yet.',
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: transactions.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final row = transactions[index];
                      final type = row['type'] as String? ?? '';
                      final amount = _number(row['amount']);
                      final isDeposit =
                          type == 'deposit' || type == 'জমা';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          isDeposit
                              ? Icons.add_circle
                              : Icons.remove_circle,
                          color: isDeposit ? Colors.green : Colors.orange,
                        ),
                        title: Text(
                          '${isDeposit ? '+' : '-'}${amount.toStringAsFixed(2)}',
                        ),
                        subtitle: Text(
                          '${row['transaction_date'] ?? ''}\n'
                          '${row['note'] ?? ''}',
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_text('বন্ধ করুন', 'Close')),
            ),
          ],
        ),
      );
    } catch (e) {
      _showMessage(
        '${_text('লেনদেনের ইতিহাস লোড হয়নি', 'Could not load history')}: $e',
      );
    }
  }

  Future<void> _deleteSaving(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_text('সঞ্চয় মুছবেন?', 'Delete saving?')),
        content: Text(
          _text(
            'এই সঞ্চয় ও এর লেনদেনের রেকর্ড মুছে যাবে।',
            'This saving and its transaction records will be deleted.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_text('বাতিল', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_text('মুছুন', 'Delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await MoneyDb.instance.deleteSaving(id);
      await _loadSavings();

      if (mounted) {
        _showMessage(_text('সঞ্চয় মুছে ফেলা হয়েছে।', 'Saving deleted.'));
      }
    } catch (e) {
      _showMessage(
        '${_text('মুছে ফেলা যায়নি', 'Could not delete')}: $e',
      );
    }
  }

  Future<void> _changePassword() async {
    final prefs = await SharedPreferences.getInstance();
    final oldHash = prefs.getString(_passwordKey);

    if (oldHash == null) return;

    final oldPassword = TextEditingController();
    final newPassword = TextEditingController();
    final confirmPassword = TextEditingController();
    String? error;

    try {
      final changed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              _text('পাসওয়ার্ড পরিবর্তন', 'Change password'),
            ),
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
                  const SizedBox(height: 10),
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
                  const SizedBox(height: 10),
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
                onPressed: () => Navigator.pop(dialogContext, false),
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
                        'কমপক্ষে ৬টি অক্ষর, একটি ইংরেজি অক্ষর ও একটি সংখ্যা দিন।',
                        'Use at least 6 characters, a letter and a number.',
                      );
                    });
                    return;
                  }

                  if (newPassword.text != confirmPassword.text) {
                    setDialogState(() {
                      error = _text(
                        'পাসওয়ার্ড দুটি মিলছে না।',
                        'Passwords do not match.',
                      );
                    });
                    return;
                  }

                  Navigator.pop(dialogContext, true);
                },
                child: Text(_text('পরিবর্তন', 'Change')),
              ),
            ],
          ),
        ),
      );

      if (changed == true) {
        await prefs.setString(
          _passwordKey,
          _hash(newPassword.text),
        );

        if (mounted) {
          _showMessage(
            _text(
              'পাসওয়ার্ড পরিবর্তন হয়েছে।',
              'Password changed.',
            ),
          );
        }
      }
    } finally {
      oldPassword.dispose();
      newPassword.dispose();
      confirmPassword.dispose();
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
          child: Text(
            _text(
              'সঞ্চয় খুলতে পাসওয়ার্ড প্রয়োজন।',
              'Password is required to open Savings.',
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_text('সঞ্চয়', 'Savings')),
        actions: [
          IconButton(
            tooltip: _text(
              'পাসওয়ার্ড পরিবর্তন',
              'Change password',
            ),
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
                        'সঞ্চয়ের লক্ষ্য: ${_savings.length}টি',
                        'Savings goals: ${_savings.length}',
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
                final id = _id(item['id']);
                final name = item['name'] as String? ?? '';
                final target = _number(item['target_amount']);
                final balance = _balances[id] ?? 0.0;
                final progress = target > 0
                    ? (balance / target).clamp(0.0, 1.0).toDouble()
                    : 0.0;
                final note = item['note'] as String? ?? '';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor:
                                theme.colorScheme.primaryContainer,
                            child: Icon(
                              Icons.savings_rounded,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            '${_text('বর্তমান সঞ্চয়', 'Current savings')}: '
                            '${balance.toStringAsFixed(2)}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'history') {
                                _showTransactions(id, name);
                              } else if (value == 'delete') {
                                _deleteSaving(id);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'history',
                                child: Text(
                                  _text(
                                    'লেনদেনের ইতিহাস',
                                    'Transaction history',
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  _text('মুছে ফেলুন', 'Delete'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (target > 0) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: progress),
                          const SizedBox(height: 5),
                          Text(
                            '${_text('লক্ষ্যমাত্রা', 'Target')}: '
                            '${target.toStringAsFixed(2)} '
                            '(${(progress * 100).toStringAsFixed(0)}%)',
                          ),
                        ],
                        if (note.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(note),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _addTransaction(
                                  id,
                                  deposit: true,
                                ),
                                icon: const Icon(Icons.add),
                                label: Text(_text('জমা', 'Deposit')),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: balance > 0
                                    ? () => _addTransaction(
                                          id,
                                          deposit: false,
                                        )
                                    : null,
                                icon: const Icon(Icons.remove),
                                label: Text(
                                  _text('উত্তোলন', 'Withdraw'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

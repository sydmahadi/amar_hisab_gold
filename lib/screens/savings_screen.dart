import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/savings_service.dart';
import '../services/app_settings.dart';

class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});

  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  final SavingsService _service = SavingsService.instance;

  bool _loading = true;
  bool _unlocked = false;
  bool _passwordSet = false;

  double _balance = 0;
  double _deposits = 0;
  double _withdrawals = 0;

  List<Map<String, dynamic>> _entries = [];

  bool get _isBangla {
    try {
      return AppSettings.instance.t('appName') == 'আমার হিসাব';
    } catch (_) {
      return true;
    }
  }

  String _t(String bn, String en) => _isBangla ? bn : en;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _service.init();
      final passwordSet = await _service.isPasswordSet();

      if (!mounted) return;

      setState(() {
        _passwordSet = passwordSet;
        _loading = false;
      });

      if (!passwordSet) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _setupPassword();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('${_t('সমস্যা হয়েছে', 'Error')}: $e');
    }
  }

  Future<void> _refresh() async {
    final balance = await _service.getBalance();
    final deposits = await _service.getTotalDeposits();
    final withdrawals = await _service.getTotalWithdrawals();
    final entries = await _service.getEntries();

    if (!mounted) return;

    setState(() {
      _balance = balance;
      _deposits = deposits;
      _withdrawals = withdrawals;
      _entries = entries;
    });
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _money(double amount) {
    return '৳${NumberFormat('#,##,##0.##').format(amount)}';
  }

  Future<void> _setupPassword() async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_t('Savings নিরাপত্তা সেটআপ', 'Set up Savings security')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _t(
                    'Savings সুরক্ষিত রাখতে কমপক্ষে ৬ অক্ষরের পাসওয়ার্ড দিন।',
                    'Set a password of at least 6 characters to protect Savings.',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _t('নতুন পাসওয়ার্ড', 'New password'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _t('পাসওয়ার্ড নিশ্চিত করুন', 'Confirm password'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                if (passwordController.text.length < 6) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        _t(
                          'পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের হতে হবে।',
                          'Password must be at least 6 characters.',
                        ),
                      ),
                    ),
                  );
                  return;
                }

                if (passwordController.text != confirmController.text) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        _t('পাসওয়ার্ড মিলছে না।', 'Passwords do not match.'),
                      ),
                    ),
                  );
                  return;
                }

                Navigator.pop(dialogContext, true);
              },
              child: Text(_t('সেট করুন', 'Set password')),
            ),
          ],
        );
      },
    );

    if (result != true || !mounted) {
      passwordController.dispose();
      confirmController.dispose();
      return;
    }

    try {
      final recoveryCode = await _service.setupSecurity(
        password: passwordController.text,
      );

      if (!mounted) return;

      setState(() {
        _passwordSet = true;
        _unlocked = true;
      });

      await _showRecoveryCode(recoveryCode);
      await _refresh();
    } catch (e) {
      _message('${_t('সেটআপ ব্যর্থ', 'Setup failed')}: $e');
    } finally {
      passwordController.dispose();
      confirmController.dispose();
    }
  }

  Future<void> _showRecoveryCode(String code) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_t('Recovery Code সংরক্ষণ করুন', 'Save your Recovery Code')),
          content: SelectableText(
            '${_t('আপনার Recovery Code:', 'Your Recovery Code:')}\n\n'
            '$code\n\n'
            '${_t(
              'কোডটি নিরাপদ জায়গায় লিখে রাখুন। পাসওয়ার্ড ভুলে গেলে এটি প্রয়োজন হবে। এই কোড আবার দেখানো হবে না।',
              'Keep this code somewhere safe. You will need it if you forget your password. It will not be shown again.',
            )}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_t('সংরক্ষণ করেছি', 'I have saved it')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _unlock() async {
    final controller = TextEditingController();

    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_t('Savings আনলক করুন', 'Unlock Savings')),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: _t('পাসওয়ার্ড', 'Password'),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _forgotPassword();
              },
              child: Text(_t('পাসওয়ার্ড ভুলে গেছি', 'Forgot password?')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                controller.text,
              ),
              child: Text(_t('আনলক', 'Unlock')),
            ),
          ],
        );
      },
    );

    if (password == null) {
      controller.dispose();
      return;
    }

    try {
      final valid = await _service.verifyPassword(password);

      if (!mounted) return;

      if (!valid) {
        _message(_t('পাসওয়ার্ড সঠিক নয়।', 'Incorrect password.'));
        return;
      }

      setState(() => _unlocked = true);
      await _refresh();
    } catch (e) {
      _message('$e');
    } finally {
      controller.dispose();
    }
  }

  Future<void> _forgotPassword() async {
    final recoveryController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_t('পাসওয়ার্ড রিসেট', 'Reset password')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: recoveryController,
                  decoration: InputDecoration(
                    labelText: _t('Recovery Code', 'Recovery Code'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _t('নতুন পাসওয়ার্ড', 'New password'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _t('পাসওয়ার্ড নিশ্চিত করুন', 'Confirm password'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_t('বাতিল', 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (passwordController.text.length < 6) {
                  _message(
                    _t(
                      'পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের হতে হবে।',
                      'Password must be at least 6 characters.',
                    ),
                  );
                  return;
                }

                if (passwordController.text != confirmController.text) {
                  _message(
                    _t('পাসওয়ার্ড মিলছে না।', 'Passwords do not match.'),
                  );
                  return;
                }

                Navigator.pop(dialogContext, true);
              },
              child: Text(_t('রিসেট করুন', 'Reset')),
            ),
          ],
        );
      },
    );

    if (result != true || !mounted) {
      recoveryController.dispose();
      passwordController.dispose();
      confirmController.dispose();
      return;
    }

    try {
      await _service.resetPassword(
        recoveryCode: recoveryController.text,
        newPassword: passwordController.text,
      );

      if (!mounted) return;

      setState(() => _unlocked = true);
      await _refresh();

      _message(_t('পাসওয়ার্ড পরিবর্তন হয়েছে।', 'Password has been reset.'));
    } catch (e) {
      _message('${_t('রিসেট ব্যর্থ', 'Reset failed')}: $e');
    } finally {
      recoveryController.dispose();
      passwordController.dispose();
      confirmController.dispose();
    }
  }

  Future<void> _changePassword() async {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_t('পাসওয়ার্ড পরিবর্তন', 'Change password')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: oldController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _t('পুরোনো পাসওয়ার্ড', 'Old password'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _t('নতুন পাসওয়ার্ড', 'New password'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _t('পাসওয়ার্ড নিশ্চিত করুন', 'Confirm password'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_t('বাতিল', 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (newController.text.length < 6 ||
                    newController.text != confirmController.text) {
                  _message(
                    _t(
                      'নতুন পাসওয়ার্ড যাচাই করুন।',
                      'Check the new password and confirmation.',
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(_t('পরিবর্তন', 'Change')),
            ),
          ],
        );
      },
    );

    if (result != true || !mounted) {
      oldController.dispose();
      newController.dispose();
      confirmController.dispose();
      return;
    }

    try {
      await _service.changePassword(
        oldPassword: oldController.text,
        newPassword: newController.text,
      );

      _message(_t('পাসওয়ার্ড পরিবর্তন হয়েছে।', 'Password changed.'));
    } catch (e) {
      _message('${_t('ব্যর্থ', 'Failed')}: $e');
    } finally {
      oldController.dispose();
      newController.dispose();
      confirmController.dispose();
    }
  }

  Future<void> _addEntry(String type) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    DateTime selectedDate = DateTime.now();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                type == 'deposit'
                    ? _t('Savings জমা', 'Add savings')
                    : _t('Savings উত্তোলন', 'Withdraw savings'),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _t('টাকার পরিমাণ', 'Amount'),
                        prefixText: '৳ ',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      decoration: InputDecoration(
                        labelText: _t('বিবরণ (ঐচ্ছিক)', 'Note (optional)'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );

                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_month),
                      label: Text(
                        DateFormat('dd MMM yyyy').format(selectedDate),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(_t('বাতিল', 'Cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    final amount = double.tryParse(
                      amountController.text.trim().replaceAll(',', ''),
                    );

                    if (amount == null ||
                        !amount.isFinite ||
                        amount <= 0) {
                      _message(
                        _t(
                          'সঠিক টাকার পরিমাণ লিখুন।',
                          'Enter a valid amount.',
                        ),
                      );
                      return;
                    }

                    Navigator.pop(dialogContext, true);
                  },
                  child: Text(_t('সংরক্ষণ', 'Save')),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true || !mounted) {
      amountController.dispose();
      noteController.dispose();
      return;
    }

    try {
      final amount = double.parse(
        amountController.text.trim().replaceAll(',', ''),
      );

      await _service.addEntry(
        amount: amount,
        type: type,
        note: noteController.text,
        date: selectedDate,
      );

      await _refresh();
      _message(_t('লেনদেন সংরক্ষিত হয়েছে।', 'Transaction saved.'));
    } catch (e) {
      _message('${_t('লেনদেন ব্যর্থ', 'Transaction failed')}: $e');
    } finally {
      amountController.dispose();
      noteController.dispose();
    }
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.13),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnlockedContent() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0F5132),
                  Color(0xFF176B45),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('মোট Savings ব্যালেন্স', 'Total savings balance'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _money(_balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF0F5132),
                        ),
                        onPressed: () => _addEntry('deposit'),
                        icon: const Icon(Icons.add),
                        label: Text(_t('জমা', 'Deposit')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white),
                        ),
                        onPressed: () => _addEntry('withdraw'),
                        icon: const Icon(Icons.remove),
                        label: Text(_t('উত্তোলন', 'Withdraw')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _summaryCard(
            title: _t('মোট জমা', 'Total deposits'),
            value: _money(_deposits),
            icon: Icons.savings,
            color: Colors.green,
          ),
          _summaryCard(
            title: _t('মোট উত্তোলন', 'Total withdrawals'),
            value: _money(_withdrawals),
            icon: Icons.money_off,
            color: Colors.orange,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _t('Savings লেনদেন', 'Savings transactions'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              IconButton(
                tooltip: _t('পাসওয়ার্ড পরিবর্তন', 'Change password'),
                onPressed: _changePassword,
                icon: const Icon(Icons.lock_reset),
              ),
            ],
          ),
          if (_entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  _t('এখনও কোনো লেনদেন নেই।', 'No transactions yet.'),
                ),
              ),
            )
          else
            ..._entries.map((entry) {
              final isDeposit = entry['type'] == 'deposit';
              final amount = (entry['amount'] as num).toDouble();
              final date = DateTime.tryParse(
                entry['entry_date']?.toString() ?? '',
              );

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isDeposit
                        ? Colors.green.withValues(alpha: 0.12)
                        : Colors.orange.withValues(alpha: 0.12),
                    child: Icon(
                      isDeposit ? Icons.add : Icons.remove,
                      color: isDeposit ? Colors.green : Colors.orange,
                    ),
                  ),
                  title: Text(
                    '${isDeposit ? '+' : '-'}${_money(amount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDeposit ? Colors.green : Colors.orange,
                    ),
                  ),
                  subtitle: Text(
                    [
                      if ((entry['note'] as String? ?? '').isNotEmpty)
                        entry['note'] as String,
                      if (date != null)
                        DateFormat('dd MMM yyyy').format(date),
                    ].join(' • '),
                  ),
                  trailing: IconButton(
                    tooltip: _t('মুছুন', 'Delete'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(
                      entry['id'] as int,
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _unlocked = false);
            },
            icon: const Icon(Icons.lock),
            label: Text(_t('Savings লক করুন', 'Lock Savings')),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('লেনদেন মুছবেন?', 'Delete transaction?')),
        content: Text(
          _t(
            'এই Savings লেনদেনটি মুছে ফেলা হবে।',
            'This Savings transaction will be deleted.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('বাতিল', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('মুছুন', 'Delete')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.deleteEntry(id);
      await _refresh();
      _message(_t('লেনদেন মুছে ফেলা হয়েছে।', 'Transaction deleted.'));
    } catch (e) {
      _message('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('Savings', 'Savings')),
        actions: [
          if (_unlocked)
            IconButton(
              tooltip: _t('লক করুন', 'Lock'),
              onPressed: () => setState(() => _unlocked = false),
              icon: const Icon(Icons.lock_outline),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_passwordSet
              ? Center(
                  child: FilledButton.icon(
                    onPressed: _setupPassword,
                    icon: const Icon(Icons.lock),
                    label: Text(
                      _t('Savings নিরাপত্তা সেট করুন', 'Set up Savings security'),
                    ),
                  ),
                )
              : !_unlocked
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.savings, size: 70),
                            const SizedBox(height: 16),
                            Text(
                              _t(
                                'Savings সুরক্ষিত আছে',
                                'Savings is locked',
                              ),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _unlock,
                              icon: const Icon(Icons.lock_open),
                              label: Text(_t('আনলক করুন', 'Unlock')),
                            ),
                            TextButton(
                              onPressed: _forgotPassword,
                              child: Text(
                                _t(
                                  'Recovery Code দিয়ে পাসওয়ার্ড রিসেট',
                                  'Reset with Recovery Code',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _buildUnlockedContent(),
    );
  }
}

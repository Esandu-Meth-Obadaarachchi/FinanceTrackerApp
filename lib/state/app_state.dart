import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../models/app_transaction.dart';
import '../models/loan.dart';
import '../models/recurring_rule.dart';
import '../services/firestore_service.dart';
import '../utils/formatters.dart';

/// Holds the signed-in user's live data and exposes CRUD operations.
class AppState extends ChangeNotifier {
  AppState(this.uid) : _service = FirestoreService(uid) {
    _listen();
  }

  final String uid;
  final FirestoreService _service;

  List<Account> accounts = [];
  List<AppTransaction> transactions = [];
  List<Loan> loans = [];
  List<RecurringRule> recurringRules = [];

  bool _accountsReady = false;
  bool _transactionsReady = false;
  bool _loansReady = false;
  bool _recurringReady = false;

  StreamSubscription? _accSub;
  StreamSubscription? _txSub;
  StreamSubscription? _loanSub;
  StreamSubscription? _recurringSub;

  /// True once all collections have produced their first snapshot.
  bool get isLoading =>
      !_accountsReady ||
      !_transactionsReady ||
      !_loansReady ||
      !_recurringReady;

  void _listen() {
    _accSub = _service.accountsStream().listen((data) {
      accounts = data;
      _accountsReady = true;
      notifyListeners();
      _materializeRecurring();
    });
    _txSub = _service.transactionsStream().listen((data) {
      transactions = data;
      _transactionsReady = true;
      notifyListeners();
      _materializeRecurring();
    });
    _loanSub = _service.loansStream().listen((data) {
      loans = data;
      _loansReady = true;
      notifyListeners();
    });
    _recurringSub = _service.recurringStream().listen((data) {
      recurringRules = data;
      _recurringReady = true;
      notifyListeners();
      _materializeRecurring();
    });
  }

  // ── Derived data ───────────────────────────────────────────────────────

  /// Current balance = opening balance + effect of every transaction,
  /// minus any money currently lent out from this account.
  double balanceOf(Account a) {
    double b = a.openingBalance;
    for (final t in transactions) {
      if (t.isIncome && t.status == 'received' && t.accountId == a.id) {
        b += t.amount;
      } else if (t.isExpense && t.accountId == a.id) {
        b -= t.amount;
      } else if (t.isTransfer) {
        if (t.accountId == a.id) b -= t.amount;
        if (t.toAccountId == a.id) b += t.amount;
      }
    }
    // Money lent out (and not yet repaid) has left the account.
    for (final l in loans) {
      if (l.isLent && l.isPending && l.accountId == a.id) {
        b -= l.amount;
      }
    }
    return b;
  }

  double get totalBalance =>
      accounts.fold(0.0, (sum, a) => sum + balanceOf(a));

  /// Outstanding money lent to others (pending repayment) — to be collected.
  double get totalLent => loans
      .where((l) => l.isLent && l.isPending)
      .fold(0.0, (sum, l) => sum + l.amount);

  Account? accountById(String id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<AppTransaction> transactionsInMonth(String monthKey) =>
      transactions.where((t) => t.monthKey == monthKey).toList();

  // ── Account operations ─────────────────────────────────────────────────
  Future<void> addAccount(Account a) => _service.addAccount(a);
  Future<void> updateAccount(Account a) => _service.updateAccount(a);
  Future<void> deleteAccount(String id) => _service.deleteAccount(id);

  // ── Transaction operations ─────────────────────────────────────────────
  Future<void> addTransaction(AppTransaction t) =>
      _service.addTransaction(t);
  Future<void> updateTransaction(AppTransaction t) =>
      _service.updateTransaction(t);
  Future<void> deleteTransaction(String id) =>
      _service.deleteTransaction(id);

  // ── Loan operations ────────────────────────────────────────────────────
  Future<void> addLoan(Loan l) => _service.addLoan(l);
  Future<void> markLoanRepaid(String id) =>
      _service.updateLoan(id, {'status': 'repaid'});
  Future<void> deleteLoan(String id) => _service.deleteLoan(id);

  // ── Recurring rule operations ──────────────────────────────────────────
  Future<void> addRecurring(RecurringRule r) => _service.addRecurring(r);
  Future<void> updateRecurring(RecurringRule r) =>
      _service.updateRecurring(r.id, r.toMap());
  Future<void> setRecurringActive(String id, bool active) =>
      _service.updateRecurring(id, {'active': active});
  Future<void> deleteRecurring(String id) => _service.deleteRecurring(id);

  // ── Recurring materialization ──────────────────────────────────────────
  // Generates the real transactions a rule is due for, one per month from its
  // start month up to the current calendar month (backfilling any gaps).
  // `lastGeneratedMonth` is the high-water mark that makes this idempotent
  // across sessions/devices and ensures a deleted entry is not recreated.
  bool _materializing = false;
  final Set<String> _generated = {}; // "ruleId|YYYY-MM" attempted this session

  Future<void> _materializeRecurring() async {
    if (!_accountsReady || !_transactionsReady || !_recurringReady) return;
    if (_materializing) return;
    _materializing = true;
    try {
      final currentMonth = monthKeyOf(DateTime.now());
      for (final rule in recurringRules) {
        if (!rule.active || rule.startMonth.isEmpty) continue;
        if (accountById(rule.accountId) == null) continue;

        String month = (rule.lastGeneratedMonth == null ||
                rule.lastGeneratedMonth!.isEmpty)
            ? rule.startMonth
            : _addMonths(rule.lastGeneratedMonth!, 1);
        if (month.compareTo(rule.startMonth) < 0) month = rule.startMonth;

        while (month.compareTo(currentMonth) <= 0) {
          final key = '${rule.id}|$month';
          if (!_generated.contains(key)) {
            _generated.add(key);
            try {
              await _generateFor(rule, month);
            } catch (_) {
              // Write failed (likely offline) — allow a later pass to retry.
              _generated.remove(key);
              return;
            }
          }
          month = _addMonths(month, 1);
        }
      }
    } finally {
      _materializing = false;
    }
  }

  Future<void> _generateFor(RecurringRule rule, String monthKey) async {
    final parts = monthKey.split('-');
    final year = int.tryParse(parts[0]) ?? 2000;
    final mo = int.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1;
    final lastDay = DateTime(year, mo + 1, 0).day; // day 0 of next month
    final day = rule.dayOfMonth.clamp(1, lastDay);

    final tx = AppTransaction(
      id: '',
      date: dateKeyOf(DateTime(year, mo, day)),
      type: rule.type,
      accountId: rule.accountId,
      toAccountId: null,
      category: rule.category,
      note: rule.note,
      amount: rule.amount,
      status: rule.isIncome ? rule.status : 'received',
      recurringId: rule.id,
    );
    await _service.addTransaction(tx);
    await _service.updateRecurring(rule.id, {'lastGeneratedMonth': monthKey});
  }

  /// Shifts a "YYYY-MM" key by [n] months.
  String _addMonths(String monthKey, int n) {
    final parts = monthKey.split('-');
    final year = int.tryParse(parts[0]) ?? 2000;
    final mo = int.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1;
    return monthKeyOf(DateTime(year, mo + n, 1));
  }

  @override
  void dispose() {
    _accSub?.cancel();
    _txSub?.cancel();
    _loanSub?.cancel();
    _recurringSub?.cancel();
    super.dispose();
  }
}

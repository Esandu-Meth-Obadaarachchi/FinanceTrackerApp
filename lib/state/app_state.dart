import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../models/app_transaction.dart';
import '../models/budget_plan.dart';
import '../models/loan.dart';
import '../models/loan_math.dart';
import '../models/recurring_rule.dart';
import '../models/reminder.dart';
import '../services/firestore_service.dart';
import '../services/reminder_scheduler.dart';
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
  BudgetPlan? _budget; // the single saved plan for this user
  List<Reminder> reminders = [];

  bool _accountsReady = false;
  bool _transactionsReady = false;
  bool _loansReady = false;
  bool _recurringReady = false;

  StreamSubscription? _accSub;
  StreamSubscription? _txSub;
  StreamSubscription? _loanSub;
  StreamSubscription? _recurringSub;
  StreamSubscription? _budgetSub;
  StreamSubscription? _reminderSub;

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
    // Budgets are independent of the 4-stream load gate — the planner handles
    // its own empty/loading state, so the rest of the app never waits on them.
    _budgetSub = _service.budgetStream().listen((data) {
      _budget = data;
      notifyListeners();
    });
    _reminderSub = _service.remindersStream().listen((data) {
      reminders = data;
      notifyListeners();
      // Keep on-device notifications in sync with the source of truth.
      ReminderScheduler.syncAll(reminders);
    });
  }

  // ── Derived data ───────────────────────────────────────────────────────

  /// Current balance = opening balance + effect of every transaction,
  /// minus any money lent out of this account. See [accountBalance].
  double balanceOf(Account a) => accountBalance(a, transactions, loans);

  double get totalBalance =>
      accounts.fold(0.0, (sum, a) => sum + balanceOf(a));

  /// Outstanding money lent to others — what is still to be collected.
  double get totalLent => loans
      .where((l) => l.isLent && !isSettled(l))
      .fold(0.0, (sum, l) => sum + outstandingOf(l));

  /// Outstanding money owed to others on borrowed loans.
  double get totalBorrowed => loans
      .where((l) => !l.isLent && !isSettled(l))
      .fold(0.0, (sum, l) => sum + outstandingOf(l));

  // ── Loan settlement ────────────────────────────────────────────────────

  /// Every transaction recorded against [loanId]. `transactions` is ordered
  /// by date descending, so this is newest first.
  List<AppTransaction> paymentsOf(String loanId) =>
      loanPayments(transactions, loanId).toList();

  /// How much of [l] has been settled so far.
  double repaidOf(Loan l) => loanRepaid(l, transactions);

  /// What is still to be settled on [l]; never negative.
  double outstandingOf(Loan l) => loanOutstanding(l, transactions);

  /// Whether [l] is fully settled. Prefer this over `loan.isPending` in the
  /// UI: it reopens a loan if its payment entries are deleted.
  bool isSettled(Loan l) => loanIsSettled(l, transactions);

  Account? accountById(String id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<AppTransaction> transactionsInMonth(String monthKey) =>
      transactions.where((t) => t.monthKey == monthKey).toList();

  /// The single saved plan for this user, or a blank one (tagged with the
  /// current month) if none exists yet.
  BudgetPlan get budget =>
      _budget ?? BudgetPlan.empty(monthKeyOf(DateTime.now()));

  /// Actual expense spend per category for [month] (category label -> total).
  Map<String, double> expenseByCategoryInMonth(String month) {
    final out = <String, double>{};
    for (final t in transactions) {
      if (t.isExpense && t.monthKey == month) {
        out[t.category] = (out[t.category] ?? 0) + t.amount;
      }
    }
    return out;
  }

  /// Distinct, non-empty notes from past transactions, most-recent first.
  /// Used to suggest history when typing a new transaction's note.
  /// [transactions] is already ordered by date descending, so first-seen wins.
  List<String> pastNotes({String? type}) {
    final seen = <String>{};
    final out = <String>[];
    for (final t in transactions) {
      if (type != null && t.type != type) continue;
      final note = t.note.trim();
      if (note.isEmpty) continue;
      if (seen.add(note.toLowerCase())) out.add(note);
    }
    return out;
  }

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
  Future<void> deleteLoan(String id) => _service.deleteLoan(id);

  /// Record a full or partial settlement of [l].
  ///
  /// Money coming back on a lent loan is income; money going out to clear a
  /// borrowed one is an expense. Either way the entry is tagged with the loan
  /// id, which is what [repaidOf] counts — so the loan's outstanding figure
  /// and the month's income/expense totals stay in step automatically.
  ///
  /// The loan flips to `repaid` once nothing is left outstanding.
  Future<void> recordLoanPayment(
    Loan l, {
    required double amount,
    required String accountId,
    required String date,
    String note = '',
  }) async {
    if (amount <= 0) return;
    final capped = amount.clamp(0, outstandingOf(l)).toDouble();
    if (capped <= 0) return;

    await _service.addTransaction(AppTransaction(
      id: '',
      date: date,
      type: l.isLent ? 'income' : 'expense',
      accountId: accountId,
      category: l.isLent ? 'Loan Received' : 'Loan Repayment',
      note: note.trim().isEmpty
          ? '${l.isLent ? 'Repayment from' : 'Repayment to'} ${l.who}'
          : note.trim(),
      amount: capped,
      status: 'received',
      loanId: l.id,
    ));

    // Settled in full once this payment lands.
    if (capped >= outstandingOf(l) - 0.005) {
      await _service.updateLoan(l.id, {'status': 'repaid'});
    }
  }

  /// Settle whatever is left on [l] in one go.
  Future<void> markLoanRepaid(Loan l, {String? accountId, String? date}) =>
      recordLoanPayment(
        l,
        amount: outstandingOf(l),
        accountId: accountId ?? l.accountId,
        date: date ?? dateKeyOf(DateTime.now()),
      );

  // ── Recurring rule operations ──────────────────────────────────────────
  Future<void> addRecurring(RecurringRule r) => _service.addRecurring(r);
  Future<void> updateRecurring(RecurringRule r) =>
      _service.updateRecurring(r.id, r.toMap());
  Future<void> setRecurringActive(String id, bool active) =>
      _service.updateRecurring(id, {'active': active});
  Future<void> deleteRecurring(String id) => _service.deleteRecurring(id);

  // ── Budget plan operations ─────────────────────────────────────────────
  Future<void> setBudget(BudgetPlan b) => _service.setBudget(b);

  // ── Reminder operations ────────────────────────────────────────────────
  Future<void> addReminder(Reminder r) => _service.addReminder(r);
  Future<void> updateReminder(Reminder r) => _service.updateReminder(r);
  Future<void> deleteReminder(Reminder r) async {
    await ReminderScheduler.cancel(r); // clear its notifications first
    await _service.deleteReminder(r.id);
  }

  // ── Reset ──────────────────────────────────────────────────────────────
  /// Wipes every document in this user's tree. The live streams then emit
  /// empty, which also clears scheduled reminder notifications via syncAll.
  Future<void> resetAllData() => _service.resetAllData();

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
    _budgetSub?.cancel();
    _reminderSub?.cancel();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../models/app_transaction.dart';
import '../models/loan.dart';
import '../services/firestore_service.dart';

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

  bool _accountsReady = false;
  bool _transactionsReady = false;
  bool _loansReady = false;

  StreamSubscription? _accSub;
  StreamSubscription? _txSub;
  StreamSubscription? _loanSub;

  /// True once all three collections have produced their first snapshot.
  bool get isLoading =>
      !_accountsReady || !_transactionsReady || !_loansReady;

  void _listen() {
    _accSub = _service.accountsStream().listen((data) {
      accounts = data;
      _accountsReady = true;
      notifyListeners();
    });
    _txSub = _service.transactionsStream().listen((data) {
      transactions = data;
      _transactionsReady = true;
      notifyListeners();
    });
    _loanSub = _service.loansStream().listen((data) {
      loans = data;
      _loansReady = true;
      notifyListeners();
    });
  }

  // ── Derived data ───────────────────────────────────────────────────────

  /// Current balance = opening balance + effect of every transaction.
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
    return b;
  }

  double get totalBalance =>
      accounts.fold(0.0, (sum, a) => sum + balanceOf(a));

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

  @override
  void dispose() {
    _accSub?.cancel();
    _txSub?.cancel();
    _loanSub?.cancel();
    super.dispose();
  }
}

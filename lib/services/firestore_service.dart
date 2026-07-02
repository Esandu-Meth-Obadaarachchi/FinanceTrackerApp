import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/account.dart';
import '../models/app_transaction.dart';
import '../models/budget_plan.dart';
import '../models/loan.dart';
import '../models/recurring_rule.dart';
import '../models/reminder.dart';

/// Reads and writes a single user's data under `users/{uid}/...`.
class FirestoreService {
  FirestoreService(this.uid);

  final String uid;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      _db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> get _accounts =>
      _userDoc.collection('accounts');
  CollectionReference<Map<String, dynamic>> get _transactions =>
      _userDoc.collection('transactions');
  CollectionReference<Map<String, dynamic>> get _loans =>
      _userDoc.collection('loans');
  CollectionReference<Map<String, dynamic>> get _recurring =>
      _userDoc.collection('recurring');
  CollectionReference<Map<String, dynamic>> get _budgets =>
      _userDoc.collection('budgets');
  CollectionReference<Map<String, dynamic>> get _reminders =>
      _userDoc.collection('reminders');

  // ── Streams ────────────────────────────────────────────────────────────
  Stream<List<Account>> accountsStream() => _accounts
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs.map((d) => Account.fromMap(d.id, d.data())).toList());

  Stream<List<AppTransaction>> transactionsStream() => _transactions
      .orderBy('date', descending: true)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => AppTransaction.fromMap(d.id, d.data())).toList());

  Stream<List<Loan>> loansStream() => _loans
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Loan.fromMap(d.id, d.data())).toList());

  Stream<List<RecurringRule>> recurringStream() => _recurring
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => RecurringRule.fromMap(d.id, d.data())).toList());

  /// The single per-user budget plan (doc `budgets/current`), or null if none
  /// has been created yet. Its `month` field records which month it belongs to.
  Stream<BudgetPlan?> budgetStream() => _budgets.doc('current').snapshots().map(
      (d) => d.exists ? BudgetPlan.fromMap(d.id, d.data() ?? const {}) : null);

  Stream<List<Reminder>> remindersStream() => _reminders
      .orderBy('dueDate')
      .snapshots()
      .map((s) =>
          s.docs.map((d) => Reminder.fromMap(d.id, d.data())).toList());

  // ── Accounts ───────────────────────────────────────────────────────────
  Future<void> addAccount(Account a) =>
      _accounts.add({...a.toMap(), 'createdAt': FieldValue.serverTimestamp()});

  Future<void> updateAccount(Account a) => _accounts.doc(a.id).update(a.toMap());

  Future<void> deleteAccount(String id) => _accounts.doc(id).delete();

  // ── Transactions ───────────────────────────────────────────────────────
  Future<void> addTransaction(AppTransaction t) => _transactions
      .add({...t.toMap(), 'createdAt': FieldValue.serverTimestamp()});

  Future<void> updateTransaction(AppTransaction t) =>
      _transactions.doc(t.id).update(t.toMap());

  Future<void> deleteTransaction(String id) => _transactions.doc(id).delete();

  // ── Loans ──────────────────────────────────────────────────────────────
  Future<void> addLoan(Loan l) =>
      _loans.add({...l.toMap(), 'createdAt': FieldValue.serverTimestamp()});

  Future<void> updateLoan(String id, Map<String, dynamic> changes) =>
      _loans.doc(id).update(changes);

  Future<void> deleteLoan(String id) => _loans.doc(id).delete();

  // ── Recurring rules ──────────────────────────────────────────────────────
  Future<DocumentReference<Map<String, dynamic>>> addRecurring(
          RecurringRule r) =>
      _recurring.add({...r.toMap(), 'createdAt': FieldValue.serverTimestamp()});

  Future<void> updateRecurring(String id, Map<String, dynamic> changes) =>
      _recurring.doc(id).update(changes);

  Future<void> deleteRecurring(String id) => _recurring.doc(id).delete();

  // ── Budget plan ──────────────────────────────────────────────────────────
  // One plan per user at `budgets/current`. Full overwrite (no merge) so
  // removed allocations and line items are actually dropped. `createdAt`
  // doubles as last-updated.
  Future<void> setBudget(BudgetPlan b) => _budgets.doc('current').set(
        {...b.toMap(), 'createdAt': FieldValue.serverTimestamp()},
      );

  // ── Reminders ──────────────────────────────────────────────────────────
  Future<void> addReminder(Reminder r) =>
      _reminders.add({...r.toMap(), 'createdAt': FieldValue.serverTimestamp()});

  Future<void> updateReminder(Reminder r) =>
      _reminders.doc(r.id).update(r.toMap());

  Future<void> deleteReminder(String id) => _reminders.doc(id).delete();

  // ── Reset ──────────────────────────────────────────────────────────────
  /// Permanently deletes every document in the user's tree — accounts,
  /// transactions, loans, recurring rules, budgets and reminders. There is no
  /// undo. Batched in chunks to stay within Firestore's per-batch limit.
  Future<void> resetAllData() async {
    for (final c in [
      _accounts,
      _transactions,
      _loans,
      _recurring,
      _budgets,
      _reminders,
    ]) {
      await _deleteAllDocs(c);
    }
  }

  Future<void> _deleteAllDocs(
      CollectionReference<Map<String, dynamic>> c) async {
    final snap = await c.get();
    var batch = _db.batch();
    var n = 0;
    for (final d in snap.docs) {
      batch.delete(d.reference);
      if (++n == 400) {
        await batch.commit();
        batch = _db.batch();
        n = 0;
      }
    }
    if (n > 0) await batch.commit();
  }
}

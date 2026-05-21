import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/account.dart';
import '../models/app_transaction.dart';
import '../models/loan.dart';

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
}

// Money math for loans: partial settlement and its effect on balances.

import 'package:financialtracker/models/account.dart';
import 'package:financialtracker/models/app_transaction.dart';
import 'package:financialtracker/models/loan.dart';
import 'package:financialtracker/models/loan_math.dart';
import 'package:flutter_test/flutter_test.dart';

Account acc({double opening = 0}) => Account(
      id: 'a1',
      name: 'Bank',
      type: 'bank',
      colorHex: '#3DEBA8',
      openingBalance: opening,
      smsIds: const [],
    );

Loan loan({
  String id = 'l1',
  String type = 'lent',
  double amount = 10000,
  String status = 'pending',
}) =>
    Loan(
      id: id,
      loanType: type,
      who: 'Nimal',
      amount: amount,
      reason: '',
      date: '2026-08-01',
      accountId: 'a1',
      status: status,
    );

AppTransaction payment({
  required double amount,
  String loanId = 'l1',
  String type = 'income',
}) =>
    AppTransaction(
      id: 'p-$amount-$loanId',
      date: '2026-08-10',
      type: type,
      accountId: 'a1',
      category: type == 'income' ? 'Loan Received' : 'Loan Repayment',
      note: '',
      amount: amount,
      status: 'received',
      loanId: loanId,
    );

void main() {
  group('outstanding', () {
    test('starts at the full amount', () {
      expect(loanOutstanding(loan(), const []), 10000);
    });

    test('drops by each payment', () {
      final txs = [payment(amount: 4000)];
      expect(loanRepaid(loan(), txs), 4000);
      expect(loanOutstanding(loan(), txs), 6000);
    });

    test('sums multiple payments', () {
      final txs = [payment(amount: 4000), payment(amount: 2500)];
      expect(loanOutstanding(loan(), txs), 3500);
    });

    test('never goes negative on an overpayment', () {
      final txs = [payment(amount: 12000)];
      expect(loanOutstanding(loan(), txs), 0);
    });

    test('ignores payments belonging to another loan', () {
      final txs = [payment(amount: 4000, loanId: 'other')];
      expect(loanOutstanding(loan(), txs), 10000);
    });
  });

  group('settled', () {
    test('an untouched pending loan is not settled', () {
      expect(loanIsSettled(loan(), const []), isFalse);
    });

    test('a partly paid loan is not settled', () {
      expect(loanIsSettled(loan(), [payment(amount: 4000)]), isFalse);
    });

    test('a fully paid loan is settled', () {
      final txs = [payment(amount: 4000), payment(amount: 6000)];
      expect(loanIsSettled(loan(), txs), isTrue);
    });

    test('deleting a payment reopens a loan still marked repaid', () {
      // The stored status says repaid, but its payments are gone, so the
      // loan must come back as outstanding rather than strand itself.
      final stale = loan(status: 'repaid');
      expect(loanIsSettled(stale, [payment(amount: 4000)]), isFalse);
      expect(loanOutstanding(stale, [payment(amount: 4000)]), 6000);
    });

    test('legacy loans with no payments honour the stored status', () {
      expect(loanIsSettled(loan(status: 'repaid'), const []), isTrue);
    });
  });

  group('balance — lent loans', () {
    test('lending takes the money out of the account', () {
      final b = accountBalance(acc(opening: 50000), const [], [loan()]);
      expect(b, 40000);
    });

    test('a partial repayment returns only that much', () {
      final txs = [payment(amount: 4000)];
      // 50000 opening - 10000 lent + 4000 back = 44000, i.e. 6000 still out.
      expect(accountBalance(acc(opening: 50000), txs, [loan()]), 44000);
    });

    test('repaying in full nets back to where it started', () {
      final txs = [payment(amount: 4000), payment(amount: 6000)];
      final settled = loan(status: 'repaid');
      expect(accountBalance(acc(opening: 50000), txs, [settled]), 50000);
    });

    test('a payment is never counted twice', () {
      // The deduction stays at the original amount; only the transaction
      // moves the balance as repayments land.
      final txs = [payment(amount: 10000)];
      expect(accountBalance(acc(opening: 50000), txs, [loan()]), 50000);
    });

    test('legacy loans marked repaid with no payments deduct nothing', () {
      // Pre-existing data: settled before partial repayments existed, so
      // there is no income transaction to offset a deduction.
      final legacy = loan(status: 'repaid');
      expect(accountBalance(acc(opening: 50000), const [], [legacy]), 50000);
    });
  });

  group('balance — borrowed loans', () {
    test('borrowing does not touch the balance', () {
      final b = accountBalance(
          acc(opening: 50000), const [], [loan(type: 'borrowed')]);
      expect(b, 50000);
    });

    test('repaying a borrowing spends from the account', () {
      final txs = [payment(amount: 4000, type: 'expense')];
      final b =
          accountBalance(acc(opening: 50000), txs, [loan(type: 'borrowed')]);
      expect(b, 46000);
    });
  });
}

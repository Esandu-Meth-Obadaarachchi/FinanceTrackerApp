import 'account.dart';
import 'app_transaction.dart';
import 'loan.dart';

/// Pure money math shared by [AppState] and its tests.
///
/// Kept free of Firestore so the balance rules — the easiest thing in the app
/// to get subtly wrong — can be exercised directly.

/// Transactions recorded against [loanId], in whatever order [txs] arrives.
Iterable<AppTransaction> loanPayments(
        Iterable<AppTransaction> txs, String loanId) =>
    txs.where((t) => t.loanId == loanId);

/// How much of [l] has been settled, derived from its payment transactions
/// rather than stored on the loan, so deleting a payment undoes it cleanly.
double loanRepaid(Loan l, Iterable<AppTransaction> txs) =>
    loanPayments(txs, l.id).fold(0.0, (sum, t) => sum + t.amount);

/// What is still to be settled on [l]. Never negative.
double loanOutstanding(Loan l, Iterable<AppTransaction> txs) =>
    (l.amount - loanRepaid(l, txs)).clamp(0, double.infinity).toDouble();

/// Whether [l] is fully settled.
///
/// Derived from the payments where a loan has any, so deleting a payment
/// transaction reopens the loan instead of stranding it as `repaid`. Loans
/// with no payments fall back to the stored status, which covers both
/// untouched loans and ones settled before partial repayments existed.
bool loanIsSettled(Loan l, Iterable<AppTransaction> txs) =>
    loanPayments(txs, l.id).isEmpty
        ? !l.isPending
        : loanOutstanding(l, txs) <= 0.005;

/// Whether [l] still takes its original amount out of its account.
///
/// Money lent out physically left the account, and each repayment returns as
/// its own income transaction. So the deduction is the *original* amount and
/// holds for the life of the loan — shrinking it as repayments land would
/// credit the same money twice.
///
/// Loans marked repaid before partial repayments existed have no offsetting
/// income transaction, so they deduct nothing and their balances are left
/// exactly as they were.
bool loanDeductsFromBalance(Loan l, Iterable<AppTransaction> txs) =>
    l.isLent && (l.isPending || loanPayments(txs, l.id).isNotEmpty);

/// Current balance of [a]: opening balance, the effect of every transaction,
/// then any money lent out of it.
double accountBalance(
  Account a,
  Iterable<AppTransaction> txs,
  Iterable<Loan> loans,
) {
  double b = a.openingBalance;
  for (final t in txs) {
    if (t.isIncome && t.status == 'received' && t.accountId == a.id) {
      b += t.amount;
    } else if (t.isExpense && t.accountId == a.id) {
      b -= t.amount;
    } else if (t.isTransfer) {
      if (t.accountId == a.id) b -= t.amount;
      if (t.toAccountId == a.id) b += t.amount;
    }
  }
  for (final l in loans) {
    if (l.accountId == a.id && loanDeductsFromBalance(l, txs)) {
      b -= l.amount;
    }
  }
  return b;
}

/// Pure math for receiving part of a pending income.
///
/// Unlike a loan — a standing record whose principal never moves — a pending
/// income *is* a transaction, and its amount is exactly what is still owed to
/// you. So a part payment splits it: a received entry for the money that
/// arrived, and the pending entry shrunk by the same amount.
///
/// That keeps the ledger honest. Tagging receipts onto an untouched pending
/// entry instead would leave a 50,000 pending row and a 20,000 received row
/// on screen for what is only 50,000 of income, and every "pending income"
/// total would have to subtract the receipts to stay right.
library;

/// How a part payment of [requested] splits a pending income of [pending].
///
/// [receipt] is what gets recorded as received, clamped so you can never
/// receive more than is outstanding. When it clears the balance,
/// [settlesFully] is set and the pending entry is simply marked received
/// rather than left behind at zero.
({double receipt, double remaining, bool settlesFully}) splitPendingIncome(
  double pending,
  double requested,
) {
  final receipt = requested.clamp(0, pending).toDouble();
  // Tolerate float dust so a "receive it all" never leaves a stray cent.
  final settlesFully = receipt >= pending - 0.005;
  return (
    receipt: receipt,
    remaining: settlesFully ? 0 : pending - receipt,
    settlesFully: settlesFully,
  );
}

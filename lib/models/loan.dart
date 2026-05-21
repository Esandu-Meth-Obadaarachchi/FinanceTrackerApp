/// Money lent to, or borrowed from, another person.
class Loan {
  final String id;
  final String loanType; // lent | borrowed
  final String who;
  final double amount;
  final String reason;
  final String date; // YYYY-MM-DD
  final String accountId;
  final String status; // pending | repaid

  const Loan({
    required this.id,
    required this.loanType,
    required this.who,
    required this.amount,
    required this.reason,
    required this.date,
    required this.accountId,
    required this.status,
  });

  factory Loan.fromMap(String id, Map<String, dynamic> m) => Loan(
        id: id,
        loanType: (m['loanType'] ?? 'lent') as String,
        who: (m['who'] ?? '') as String,
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        reason: (m['reason'] ?? '') as String,
        date: (m['date'] ?? '') as String,
        accountId: (m['accountId'] ?? '') as String,
        status: (m['status'] ?? 'pending') as String,
      );

  Map<String, dynamic> toMap() => {
        'loanType': loanType,
        'who': who,
        'amount': amount,
        'reason': reason,
        'date': date,
        'accountId': accountId,
        'status': status,
      };

  bool get isLent => loanType == 'lent';
  bool get isPending => status == 'pending';
}

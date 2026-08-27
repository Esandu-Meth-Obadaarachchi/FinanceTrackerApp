/// A single financial transaction: income, expense or transfer.
class AppTransaction {
  final String id;
  final String date; // YYYY-MM-DD
  final String type; // income | expense | transfer
  final String accountId;
  final String? toAccountId; // transfer destination
  final String category;
  final String note;
  final double amount;
  final String status; // received | pending  (income only; else 'received')
  final String? recurringId; // set when auto-generated from a RecurringRule
  final String? loanId; // set when this entry settles part of a Loan
  final String? parentId; // set when this entry is part of a pending income

  const AppTransaction({
    required this.id,
    required this.date,
    required this.type,
    required this.accountId,
    this.toAccountId,
    required this.category,
    required this.note,
    required this.amount,
    required this.status,
    this.recurringId,
    this.loanId,
    this.parentId,
  });

  factory AppTransaction.fromMap(String id, Map<String, dynamic> m) =>
      AppTransaction(
        id: id,
        date: (m['date'] ?? '') as String,
        type: (m['type'] ?? 'expense') as String,
        accountId: (m['accountId'] ?? '') as String,
        toAccountId: m['toAccountId'] as String?,
        category: (m['category'] ?? '') as String,
        note: (m['note'] ?? '') as String,
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        status: (m['status'] ?? 'received') as String,
        recurringId: m['recurringId'] as String?,
        loanId: m['loanId'] as String?,
        parentId: m['parentId'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'date': date,
        'type': type,
        'accountId': accountId,
        'toAccountId': toAccountId,
        'category': category,
        'note': note,
        'amount': amount,
        'status': status,
        'recurringId': recurringId,
        'loanId': loanId,
        'parentId': parentId,
      };

  AppTransaction copyWith({
    String? accountId,
    double? amount,
    String? status,
    String? parentId,
  }) =>
      AppTransaction(
        id: id,
        date: date,
        type: type,
        accountId: accountId ?? this.accountId,
        toAccountId: toAccountId,
        category: category,
        note: note,
        amount: amount ?? this.amount,
        status: status ?? this.status,
        recurringId: recurringId,
        loanId: loanId,
        parentId: parentId ?? this.parentId,
      );

  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';
  bool get isTransfer => type == 'transfer';
  bool get isPending => status == 'pending';
  bool get isRecurring => recurringId != null && recurringId!.isNotEmpty;
  bool get isLoanPayment => loanId != null && loanId!.isNotEmpty;

  DateTime get dateTime => DateTime.tryParse(date) ?? DateTime(2000);
  String get monthKey => date.length >= 7 ? date.substring(0, 7) : date;
}

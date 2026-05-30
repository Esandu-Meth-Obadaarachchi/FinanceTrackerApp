/// A fixed monthly income or expense that auto-generates a transaction each
/// month. The generated entries are normal transactions (tagged with this
/// rule's id) the user can edit per month; editing the rule only affects
/// future months.
class RecurringRule {
  final String id;
  final String type; // income | expense
  final String accountId;
  final String category;
  final String note;
  final double amount;
  final int dayOfMonth; // 1–31, clamped to month length when generating
  final String status; // income only: received | pending (else 'received')
  final bool active;
  final String startMonth; // YYYY-MM — first month to generate
  final String? lastGeneratedMonth; // YYYY-MM high-water mark; null until first run

  const RecurringRule({
    required this.id,
    required this.type,
    required this.accountId,
    required this.category,
    required this.note,
    required this.amount,
    required this.dayOfMonth,
    required this.status,
    required this.active,
    required this.startMonth,
    this.lastGeneratedMonth,
  });

  factory RecurringRule.fromMap(String id, Map<String, dynamic> m) => RecurringRule(
        id: id,
        type: (m['type'] ?? 'expense') as String,
        accountId: (m['accountId'] ?? '') as String,
        category: (m['category'] ?? '') as String,
        note: (m['note'] ?? '') as String,
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        dayOfMonth: (m['dayOfMonth'] as num?)?.toInt() ?? 1,
        status: (m['status'] ?? 'received') as String,
        active: (m['active'] ?? true) as bool,
        startMonth: (m['startMonth'] ?? '') as String,
        lastGeneratedMonth: m['lastGeneratedMonth'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'type': type,
        'accountId': accountId,
        'category': category,
        'note': note,
        'amount': amount,
        'dayOfMonth': dayOfMonth,
        'status': status,
        'active': active,
        'startMonth': startMonth,
        'lastGeneratedMonth': lastGeneratedMonth,
      };

  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';

  RecurringRule copyWith({
    String? type,
    String? accountId,
    String? category,
    String? note,
    double? amount,
    int? dayOfMonth,
    String? status,
    bool? active,
    String? startMonth,
    String? lastGeneratedMonth,
  }) =>
      RecurringRule(
        id: id,
        type: type ?? this.type,
        accountId: accountId ?? this.accountId,
        category: category ?? this.category,
        note: note ?? this.note,
        amount: amount ?? this.amount,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
        status: status ?? this.status,
        active: active ?? this.active,
        startMonth: startMonth ?? this.startMonth,
        lastGeneratedMonth: lastGeneratedMonth ?? this.lastGeneratedMonth,
      );
}

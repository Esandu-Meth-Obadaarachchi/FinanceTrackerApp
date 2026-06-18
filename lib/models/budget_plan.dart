/// A zero-based / envelope plan for one calendar month: the income the user
/// expects and how they intend to allocate it across expense categories.
///
/// One Firestore document per month (id = "YYYY-MM"); allocations are stored as
/// a map of category label -> planned amount. The zero-based goal is to drive
/// [unallocated] to 0 (every expected rupee given a job).
class BudgetPlan {
  final String month; // YYYY-MM (also the doc id)
  final double plannedIncome;
  final Map<String, double> allocations; // category label -> planned amount

  const BudgetPlan({
    required this.month,
    required this.plannedIncome,
    required this.allocations,
  });

  /// A blank plan for a month that has no document yet.
  factory BudgetPlan.empty(String month) =>
      BudgetPlan(month: month, plannedIncome: 0, allocations: const {});

  factory BudgetPlan.fromMap(String id, Map<String, dynamic> m) {
    final raw = (m['allocations'] as Map?) ?? const {};
    final alloc = <String, double>{};
    raw.forEach((k, v) {
      final amt = (v as num?)?.toDouble() ?? 0;
      if (amt != 0) alloc[k.toString()] = amt;
    });
    return BudgetPlan(
      month: (m['month'] ?? id) as String,
      plannedIncome: (m['plannedIncome'] as num?)?.toDouble() ?? 0,
      allocations: alloc,
    );
  }

  Map<String, dynamic> toMap() => {
        'month': month,
        'plannedIncome': plannedIncome,
        'allocations': allocations,
      };

  /// Total of every category allocation.
  double get totalAllocated =>
      allocations.values.fold(0.0, (s, v) => s + v);

  /// Income still to be given a job. Zero-based target is 0; negative means
  /// the plan allocates more than the expected income.
  double get unallocated => plannedIncome - totalAllocated;

  bool get isEmpty => plannedIncome == 0 && allocations.isEmpty;

  BudgetPlan copyWith({
    double? plannedIncome,
    Map<String, double>? allocations,
  }) =>
      BudgetPlan(
        month: month,
        plannedIncome: plannedIncome ?? this.plannedIncome,
        allocations: allocations ?? this.allocations,
      );

  /// Returns a copy with [category] set to [amount] (or removed when <= 0).
  BudgetPlan withAllocation(String category, double amount) {
    final next = Map<String, double>.from(allocations);
    if (amount <= 0) {
      next.remove(category);
    } else {
      next[category] = amount;
    }
    return copyWith(allocations: next);
  }
}

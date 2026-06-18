/// A single named line item inside a category envelope, e.g. "Claude" under
/// "Software & Subscriptions".
class BudgetItem {
  final String name;
  final double amount;

  const BudgetItem({required this.name, required this.amount});

  factory BudgetItem.fromMap(Map<String, dynamic> m) => BudgetItem(
        name: (m['name'] ?? '') as String,
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {'name': name, 'amount': amount};
}

/// A zero-based / envelope plan for one calendar month: the income the user
/// expects and how they intend to allocate it across expense categories.
///
/// One Firestore document per month (id = "YYYY-MM"). [allocations] is the
/// per-category planned total (the source of truth for all planner math).
/// [items] optionally breaks a category into named line items that sum to that
/// total — when a category has items, `allocations[cat]` equals their sum.
class BudgetPlan {
  final String month; // YYYY-MM (also the doc id)
  final double plannedIncome;
  final Map<String, double> allocations; // category label -> planned total
  final Map<String, List<BudgetItem>> items; // category label -> line items

  const BudgetPlan({
    required this.month,
    required this.plannedIncome,
    required this.allocations,
    this.items = const {},
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

    final rawItems = (m['items'] as Map?) ?? const {};
    final items = <String, List<BudgetItem>>{};
    rawItems.forEach((cat, v) {
      if (v is List) {
        final list = v
            .whereType<Map>()
            .map((e) =>
                BudgetItem.fromMap(Map<String, dynamic>.from(e)))
            .where((b) => b.amount != 0)
            .toList();
        if (list.isNotEmpty) items[cat.toString()] = list;
      }
    });

    return BudgetPlan(
      month: (m['month'] ?? id) as String,
      plannedIncome: (m['plannedIncome'] as num?)?.toDouble() ?? 0,
      allocations: alloc,
      items: items,
    );
  }

  Map<String, dynamic> toMap() => {
        'month': month,
        'plannedIncome': plannedIncome,
        'allocations': allocations,
        'items': items.map(
            (k, v) => MapEntry(k, v.map((e) => e.toMap()).toList())),
      };

  /// Total of every category allocation.
  double get totalAllocated =>
      allocations.values.fold(0.0, (s, v) => s + v);

  /// Income still to be given a job. Zero-based target is 0; negative means
  /// the plan allocates more than the expected income.
  double get unallocated => plannedIncome - totalAllocated;

  bool get isEmpty => plannedIncome == 0 && allocations.isEmpty;

  /// The line items for [category], or an empty list when it's a single amount.
  List<BudgetItem> itemsFor(String category) => items[category] ?? const [];

  BudgetPlan copyWith({
    double? plannedIncome,
    Map<String, double>? allocations,
    Map<String, List<BudgetItem>>? items,
  }) =>
      BudgetPlan(
        month: month,
        plannedIncome: plannedIncome ?? this.plannedIncome,
        allocations: allocations ?? this.allocations,
        items: items ?? this.items,
      );

  /// Sets [category] to a single [amount], clearing any line items it had
  /// (or removes it entirely when amount <= 0).
  BudgetPlan withAllocation(String category, double amount) {
    final nextAlloc = Map<String, double>.from(allocations);
    final nextItems = Map<String, List<BudgetItem>>.from(items);
    nextItems.remove(category);
    if (amount <= 0) {
      nextAlloc.remove(category);
    } else {
      nextAlloc[category] = amount;
    }
    return copyWith(allocations: nextAlloc, items: nextItems);
  }

  /// Sets the line items for [category]; its allocation becomes their sum.
  /// Passing an empty list (or all-zero items) removes the category.
  BudgetPlan withItems(String category, List<BudgetItem> newItems) {
    final filtered = newItems.where((i) => i.amount > 0).toList();
    final nextAlloc = Map<String, double>.from(allocations);
    final nextItems = Map<String, List<BudgetItem>>.from(items);
    if (filtered.isEmpty) {
      nextAlloc.remove(category);
      nextItems.remove(category);
    } else {
      nextAlloc[category] = filtered.fold(0.0, (s, i) => s + i.amount);
      nextItems[category] = filtered;
    }
    return copyWith(allocations: nextAlloc, items: nextItems);
  }
}

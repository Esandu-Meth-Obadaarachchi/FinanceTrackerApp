import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../models/budget_plan.dart';
import '../state/app_state.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';
import '../widgets/sheet_scaffold.dart';

/// Opens the zero-based income/spending planner, re-providing [AppState] for the
/// pushed route (it lands on the root navigator, above the AuthGate provider).
void openBudgetPlanner(BuildContext context, {required String month}) {
  final app = context.read<AppState>();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: BudgetScreen(month: month),
      ),
    ),
  );
}

/// Shifts a "YYYY-MM" key by [n] months.
String _shiftMonth(String m, int n) {
  final p = m.split('-');
  final y = int.tryParse(p[0]) ?? 2000;
  final mo = int.tryParse(p.length > 1 ? p[1] : '1') ?? 1;
  return monthKeyOf(DateTime(y, mo + n, 1));
}

/// Re-provides [AppState] for a sheet opened from within this screen.
void _openSheet(BuildContext context, Widget sheet) {
  final app = context.read<AppState>();
  showAppSheet(
    context,
    builder: (_) =>
        ChangeNotifierProvider<AppState>.value(value: app, child: sheet),
  );
}

const _income = Color(0xFF3DEBA8);
const _expense = Color(0xFFFF5C7A);
const _warn = Color(0xFFFFB547);

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key, required this.month});
  final String month;

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  late String _month = widget.month;

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final app = context.watch<AppState>();
    final plan = app.budgetFor(_month);
    final spent = app.expenseByCategoryInMonth(_month);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: colors.text),
        title: Text('Planner',
            style: sans(size: 18, weight: FontWeight.w800, color: colors.text)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
        children: [
          _monthStepper(colors),
          const SizedBox(height: 14),
          _summaryCard(context, colors, plan),
          const SizedBox(height: 16),
          if (plan.isEmpty)
            _introCard(context, colors, app, plan)
          else ...[
            _sectionLabel(colors, 'ALLOCATIONS'),
            if (plan.allocations.isEmpty)
              EmptyState(
                icon: Icons.pie_chart_outline,
                title: 'Nothing allocated yet',
                subtitle: 'Give every rupee a job — add a category below.',
                colors: colors,
              )
            else
              for (final cat in _sortedCats(plan))
                _allocationRow(context, colors, plan, cat,
                    spent[cat] ?? 0),
            const SizedBox(height: 4),
            _addAllocationButton(context, colors),
            ..._unbudgeted(context, colors, plan, spent),
          ],
        ],
      ),
    );
  }

  List<String> _sortedCats(BudgetPlan plan) {
    final cats = plan.allocations.keys.toList()
      ..sort((a, b) =>
          (plan.allocations[b] ?? 0).compareTo(plan.allocations[a] ?? 0));
    return cats;
  }

  // ── Month stepper ──────────────────────────────────────────────────────
  Widget _monthStepper(Palette colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _stepBtn(colors, Icons.chevron_left,
            () => setState(() => _month = _shiftMonth(_month, -1))),
        Text(fmtMonthLong(_month),
            style: sans(size: 16, weight: FontWeight.w700, color: colors.text)),
        _stepBtn(colors, Icons.chevron_right,
            () => setState(() => _month = _shiftMonth(_month, 1))),
      ],
    );
  }

  Widget _stepBtn(Palette colors, IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: colors.card,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 22, color: colors.sub),
      ),
    );
  }

  // ── Summary ────────────────────────────────────────────────────────────
  Widget _summaryCard(BuildContext context, Palette colors, BudgetPlan plan) {
    final left = plan.unallocated;
    final (leftColor, leftLabel) = left > 0
        ? (_warn, 'Left to allocate')
        : left < 0
            ? (_expense, 'Over-allocated')
            : (_income, 'Every rupee assigned');

    return AppCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Planned Income',
                  style: sans(size: 13, color: colors.sub)),
              InkWell(
                onTap: () => _openSheet(
                    context, _IncomeEditorSheet(month: _month)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text('Edit',
                      style: sans(
                          size: 12.5,
                          weight: FontWeight.w600,
                          color: _income)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Rs ${fmtFull(plan.plannedIncome)}',
              style: mono(size: 30, weight: FontWeight.w800, color: colors.text)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: plan.plannedIncome > 0
                  ? (plan.totalAllocated / plan.plannedIncome).clamp(0, 1)
                  : 0,
              minHeight: 9,
              backgroundColor: colors.elevated,
              valueColor:
                  AlwaysStoppedAnimation(left < 0 ? _expense : _income),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stat(colors, 'Allocated', plan.totalAllocated, colors.text),
              _stat(colors, leftLabel, left.abs(), leftColor,
                  alignEnd: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(Palette colors, String label, double value, Color color,
      {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: sans(size: 11, color: colors.sub)),
        const SizedBox(height: 2),
        Text('Rs ${fmt(value)}',
            style: mono(size: 18, weight: FontWeight.w700, color: color)),
      ],
    );
  }

  // ── Intro (no plan yet) ─────────────────────────────────────────────────
  Widget _introCard(
      BuildContext context, Palette colors, AppState app, BudgetPlan plan) {
    final hasRecurring =
        app.recurringRules.any((r) => r.active);
    return AppCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Plan this month',
              style:
                  sans(size: 15, weight: FontWeight.w700, color: colors.text)),
          const SizedBox(height: 6),
          Text(
            'Set the income you expect, then give every rupee a job by '
            'allocating it to spending categories. Aim to get "left to '
            'allocate" down to zero.',
            style: sans(size: 13, color: colors.sub),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: 'Set planned income',
            icon: Icons.account_balance_wallet_outlined,
            onPressed: () =>
                _openSheet(context, _IncomeEditorSheet(month: _month)),
          ),
          if (hasRecurring) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _autoFill(app, plan),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.border, width: 1.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome, size: 17, color: colors.sub),
                    const SizedBox(width: 8),
                    Text('Auto-fill from recurring',
                        style: sans(
                            size: 14,
                            weight: FontWeight.w600,
                            color: colors.sub)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _autoFill(AppState app, BudgetPlan plan) {
    final income = app.recurringRules
        .where((r) => r.isIncome && r.active)
        .fold(0.0, (s, r) => s + r.amount);
    final alloc = Map<String, double>.from(plan.allocations);
    for (final r in app.recurringRules.where((r) => r.isExpense && r.active)) {
      alloc[r.category] = (alloc[r.category] ?? 0) + r.amount;
    }
    app.setBudget(plan.copyWith(
      plannedIncome: plan.plannedIncome > 0 ? plan.plannedIncome : income,
      allocations: alloc,
    ));
  }

  // ── Allocation rows ──────────────────────────────────────────────────────
  Widget _allocationRow(BuildContext context, Palette colors, BudgetPlan plan,
      String cat, double spent) {
    final planned = plan.allocations[cat] ?? 0;
    final over = spent > planned;
    final pct = planned > 0 ? (spent / planned).clamp(0.0, 1.0) : 0.0;

    return InkWell(
      onTap: () => _openSheet(
          context, _AllocationEditorSheet(month: _month, category: cat)),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: colors.card,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Row(
              children: [
                CategoryDot(category: cat, size: 9),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(cat,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(
                          size: 14,
                          weight: FontWeight.w600,
                          color: colors.text)),
                ),
                Text('Rs ${fmt(spent)} / ${fmt(planned)}',
                    style: mono(
                        size: 13,
                        weight: FontWeight.w700,
                        color: over ? _expense : colors.text)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 5,
                backgroundColor: colors.elevated,
                valueColor: AlwaysStoppedAnimation(
                    over ? _expense : categoryColor(cat)),
              ),
            ),
            for (final item in plan.itemsFor(cat)) ...[
              const SizedBox(height: 7),
              Row(
                children: [
                  Icon(Icons.subdirectory_arrow_right,
                      size: 13, color: colors.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        item.name.isNotEmpty ? item.name : 'Item',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(size: 12.5, color: colors.sub)),
                  ),
                  Text('Rs ${fmt(item.amount)}',
                      style: mono(size: 12, color: colors.sub)),
                ],
              ),
            ],
            if (over) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text('Over by Rs ${fmt(spent - planned)}',
                    style: sans(
                        size: 11, weight: FontWeight.w600, color: _expense)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _addAllocationButton(BuildContext context, Palette colors) {
    return GestureDetector(
      onTap: () =>
          _openSheet(context, _AllocationEditorSheet(month: _month)),
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: colors.border, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 18, color: colors.sub),
            const SizedBox(width: 8),
            Text('Add allocation',
                style: sans(
                    size: 14, weight: FontWeight.w600, color: colors.sub)),
          ],
        ),
      ),
    );
  }

  // ── Unbudgeted spending (spent without an allocation) ───────────────────
  List<Widget> _unbudgeted(BuildContext context, Palette colors,
      BudgetPlan plan, Map<String, double> spent) {
    final extras = spent.entries
        .where((e) => !plan.allocations.containsKey(e.key) && e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (extras.isEmpty) return const [];

    return [
      const SizedBox(height: 8),
      _sectionLabel(colors, 'UNBUDGETED SPENDING'),
      for (final e in extras)
        InkWell(
          onTap: () => _openSheet(context,
              _AllocationEditorSheet(month: _month, category: e.key)),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: colors.card,
              border: Border.all(color: _warn.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                CategoryDot(category: e.key, size: 9),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(size: 14, color: colors.text)),
                ),
                Text('Rs ${fmt(e.value)}',
                    style: mono(
                        size: 13, weight: FontWeight.w700, color: _warn)),
                const SizedBox(width: 6),
                Icon(Icons.add_circle_outline, size: 17, color: _warn),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _sectionLabel(Palette colors, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 0, 10),
        child: Text(text,
            style: sans(
                size: 12,
                weight: FontWeight.w700,
                color: colors.sub,
                letterSpacing: 0.6)),
      );
}

// ════════════════════════════════════════════════════════════════════════
// Planned income editor
// ════════════════════════════════════════════════════════════════════════
class _IncomeEditorSheet extends StatefulWidget {
  const _IncomeEditorSheet({required this.month});
  final String month;

  @override
  State<_IncomeEditorSheet> createState() => _IncomeEditorSheetState();
}

class _IncomeEditorSheetState extends State<_IncomeEditorSheet> {
  late final TextEditingController _amount;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final cur = app.budgetFor(widget.month).plannedIncome;
    _amount = TextEditingController(text: cur > 0 ? _trim(cur) : '');
  }

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.read<ThemeController>().colors;
    final app = context.read<AppState>();
    return SheetScaffold(
      title: 'Planned income · ${fmtMonthLong(widget.month)}',
      colors: colors,
      children: [
        AppTextField(
          colors: colors,
          controller: _amount,
          label: 'Expected income (LKR)',
          hint: 'e.g. 250000',
          prefix: 'Rs',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 18),
        PrimaryButton(
          label: 'Save',
          onPressed: () {
            final amt = double.tryParse(_amount.text.trim()) ?? 0;
            final plan = app.budgetFor(widget.month);
            app.setBudget(plan.copyWith(plannedIncome: amt));
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Allocation editor (add or edit a category envelope)
// ════════════════════════════════════════════════════════════════════════
class _AllocationEditorSheet extends StatefulWidget {
  const _AllocationEditorSheet({required this.month, this.category});
  final String month;
  final String? category; // null => add new

  @override
  State<_AllocationEditorSheet> createState() => _AllocationEditorSheetState();
}

/// One editable line item (name + amount) inside the allocation editor.
class _ItemRow {
  _ItemRow({String name = '', String amount = ''})
      : key = UniqueKey(),
        name = TextEditingController(text: name),
        amount = TextEditingController(text: amount);
  final Key key;
  final TextEditingController name;
  final TextEditingController amount;
  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

class _AllocationEditorSheetState extends State<_AllocationEditorSheet> {
  late String _category;
  final List<_ItemRow> _rows = [];

  @override
  void initState() {
    super.initState();
    final plan = context.read<AppState>().budgetFor(widget.month);
    _category = widget.category ?? _firstUnallocated(plan);
    _seedRows(plan);
  }

  void _seedRows(BudgetPlan plan) {
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();
    final existing = plan.itemsFor(_category);
    if (existing.isNotEmpty) {
      for (final item in existing) {
        _rows.add(_ItemRow(name: item.name, amount: _trim(item.amount)));
      }
    } else {
      final cur = plan.allocations[_category] ?? 0;
      _rows.add(_ItemRow(amount: cur > 0 ? _trim(cur) : ''));
    }
  }

  String _firstUnallocated(BudgetPlan plan) {
    for (final c in kExpenseCategories) {
      if (!plan.allocations.containsKey(c.label)) return c.label;
    }
    return kExpenseCategories.first.label;
  }

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  double get _total => _rows.fold(
      0.0, (s, r) => s + (double.tryParse(r.amount.text.trim()) ?? 0));

  List<BudgetItem> _buildItems() => _rows
      .map((r) => BudgetItem(
            name: r.name.text.trim(),
            amount: double.tryParse(r.amount.text.trim()) ?? 0,
          ))
      .toList();

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.read<ThemeController>().colors;
    final app = context.read<AppState>();
    final plan = app.budgetFor(widget.month);
    final isEdit = widget.category != null;
    final spent = app.expenseByCategoryInMonth(widget.month)[_category] ?? 0;
    final multi = _rows.length > 1;

    return SheetScaffold(
      title: isEdit ? 'Edit allocation' : 'Add allocation',
      colors: colors,
      children: [
        if (isEdit)
          Row(
            children: [
              CategoryDot(category: _category, size: 10),
              const SizedBox(width: 9),
              Text(_category,
                  style: sans(
                      size: 16, weight: FontWeight.w700, color: colors.text)),
            ],
          )
        else
          AppDropdown<String>(
            colors: colors,
            label: 'Category',
            value: _category,
            items: [
              for (final c in kExpenseCategories)
                DropdownMenuItem(value: c.label, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() {
              _category = v ?? _category;
              _seedRows(plan);
            }),
          ),
        const SizedBox(height: 14),
        FieldLabel('Items', colors: colors),
        for (final row in _rows) _itemRow(colors, row),
        const SizedBox(height: 2),
        GestureDetector(
          onTap: () => setState(() => _rows.add(_ItemRow())),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 16, color: colors.sub),
                const SizedBox(width: 6),
                Text('Add item',
                    style: sans(
                        size: 13, weight: FontWeight.w600, color: colors.sub)),
              ],
            ),
          ),
        ),
        if (multi) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFF3DEBA8).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Category total',
                    style: sans(
                        size: 13,
                        weight: FontWeight.w600,
                        color: colors.text)),
                Text('Rs ${fmtFull(_total)}',
                    style: mono(
                        size: 15,
                        weight: FontWeight.w800,
                        color: const Color(0xFF3DEBA8))),
              ],
            ),
          ),
        ],
        if (spent > 0) ...[
          const SizedBox(height: 10),
          Text('Already spent this month: Rs ${fmtFull(spent)}',
              style: sans(size: 12.5, color: colors.sub)),
        ],
        const SizedBox(height: 18),
        PrimaryButton(
          label: 'Save',
          onPressed: () {
            app.setBudget(plan.withItems(_category, _buildItems()));
            Navigator.of(context).pop();
          },
        ),
        if (isEdit) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              app.setBudget(plan.withItems(_category, const []));
              Navigator.of(context).pop();
            },
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('Remove allocation',
                    style: sans(
                        size: 13.5,
                        weight: FontWeight.w600,
                        color: _expense)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _itemRow(Palette colors, _ItemRow row) {
    return Padding(
      key: row.key,
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: AppTextField(
              colors: colors,
              controller: row.name,
              hint: 'e.g. Claude',
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 116,
            child: AppTextField(
              colors: colors,
              controller: row.amount,
              hint: '0',
              prefix: 'Rs',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            onPressed: _rows.length == 1
                ? null
                : () => setState(() {
                      _rows.remove(row);
                      row.dispose();
                    }),
            icon: Icon(Icons.close,
                size: 18,
                color: _rows.length == 1 ? colors.muted : _expense),
            splashRadius: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          ),
        ],
      ),
    );
  }
}

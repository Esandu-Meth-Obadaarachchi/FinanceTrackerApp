import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/recurring_rule.dart';
import '../state/app_state.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import 'modals/sheets.dart';

/// Opens the recurring-rules manager, re-providing [AppState] for the pushed
/// route (it lands on the root navigator, above the AuthGate provider).
void openRecurringManager(BuildContext context) {
  final app = context.read<AppState>();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const RecurringScreen(),
      ),
    ),
  );
}

/// Manage fixed monthly income/expense automations.
class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final app = context.watch<AppState>();

    final income = app.recurringRules.where((r) => r.isIncome).toList();
    final expense = app.recurringRules.where((r) => r.isExpense).toList();

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: colors.text),
        title: Text('Recurring',
            style: sans(size: 18, weight: FontWeight.w800, color: colors.text)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.border),
        ),
      ),
      body: app.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF3DEBA8)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              children: [
                Text(
                  'Fixed amounts auto-added each month. Edits apply to future '
                  'months only — past entries stay as they are.',
                  style: sans(size: 12.5, color: colors.sub),
                ),
                const SizedBox(height: 16),
                if (app.recurringRules.isEmpty)
                  EmptyState(
                    icon: Icons.repeat,
                    title: 'No automations yet',
                    subtitle: 'Add a fixed monthly income or expense to '
                        'have it added automatically every month.',
                    colors: colors,
                  )
                else ...[
                  if (income.isNotEmpty) ...[
                    _sectionLabel(colors, 'MONTHLY INCOME'),
                    for (final r in income) _ruleCard(context, colors, app, r),
                    const SizedBox(height: 8),
                  ],
                  if (expense.isNotEmpty) ...[
                    _sectionLabel(colors, 'MONTHLY EXPENSES'),
                    for (final r in expense) _ruleCard(context, colors, app, r),
                  ],
                ],
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => showAddRecurringSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.border, width: 1.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 18, color: colors.sub),
                        const SizedBox(width: 8),
                        Text('Add Recurring',
                            style: sans(
                                size: 15,
                                weight: FontWeight.w600,
                                color: colors.sub)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionLabel(Palette colors, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 0, 8),
        child: Text(text,
            style: sans(
                size: 12,
                weight: FontWeight.w700,
                color: colors.sub,
                letterSpacing: 0.6)),
      );

  Widget _ruleCard(
      BuildContext context, Palette colors, AppState app, RecurringRule r) {
    final color =
        r.isIncome ? const Color(0xFF3DEBA8) : const Color(0xFFFF5C7A);
    final acc = app.accountById(r.accountId);
    final dimmed = !r.active;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: colors.card,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => showAddRecurringSheet(context, edit: r),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                          child: CategoryDot(category: r.category, size: 12)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.note.isNotEmpty ? r.note : r.category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(
                                  size: 15,
                                  weight: FontWeight.w700,
                                  color: colors.text)),
                          const SizedBox(height: 2),
                          Text(
                              'Day ${r.dayOfMonth} · ${acc?.name ?? '—'}'
                              ' · from ${fmtMonthShort(r.startMonth)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(size: 12, color: colors.sub)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${r.isIncome ? '+' : '-'} Rs ${fmt(r.amount)}',
                        style: mono(
                            size: 16, weight: FontWeight.w700, color: color)),
                  ],
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Text(r.active ? 'Active' : 'Paused',
                      style: sans(size: 12.5, color: colors.sub)),
                  Switch(
                    value: r.active,
                    activeColor: const Color(0xFF3DEBA8),
                    activeTrackColor:
                        const Color(0xFF3DEBA8).withValues(alpha: 0.5),
                    onChanged: (v) => app.setRecurringActive(r.id, v),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _confirmDelete(context, app, r),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Text('Remove',
                          style: sans(
                              size: 12.5,
                              weight: FontWeight.w600,
                              color: const Color(0xFFFF5C7A))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppState app, RecurringRule r) {
    final colors = context.read<ThemeController>().colors;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('Remove automation?',
            style: sans(size: 16, weight: FontWeight.w700, color: colors.text)),
        content: Text(
            'This stops future months from being added. Entries already added '
            'stay in your transactions.',
            style: sans(size: 13.5, color: colors.sub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: sans(size: 14, color: colors.sub)),
          ),
          TextButton(
            onPressed: () {
              app.deleteRecurring(r.id);
              Navigator.of(ctx).pop();
            },
            child: Text('Remove',
                style: sans(
                    size: 14,
                    weight: FontWeight.w700,
                    color: const Color(0xFFFF5C7A))),
          ),
        ],
      ),
    );
  }
}

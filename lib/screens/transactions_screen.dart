import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../models/app_transaction.dart';
import '../state/app_state.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';
import 'modals/sheets.dart';

/// Lists transactions for the selected month, grouped by date.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key, required this.month});

  final String month;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String _tab = 'all';
  String _search = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final app = context.watch<AppState>();

    if (app.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF3DEBA8)),
      );
    }

    final monthTxs = app.transactionsInMonth(widget.month);
    final income = monthTxs
        .where((t) => t.isIncome && t.status == 'received')
        .fold(0.0, (s, t) => s + t.amount);
    final expenses =
        monthTxs.where((t) => t.isExpense).fold(0.0, (s, t) => s + t.amount);

    final q = _search.toLowerCase();
    final filtered = monthTxs
        .where((t) => _tab == 'all' || t.type == _tab)
        .where((t) =>
            q.isEmpty ||
            t.note.toLowerCase().contains(q) ||
            t.category.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    // Group by date.
    final groups = <String, List<AppTransaction>>{};
    for (final t in filtered) {
      groups.putIfAbsent(t.date, () => []).add(t);
    }
    final dates = groups.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      children: [
        SegmentedControl<String>(
          colors: colors,
          value: _tab,
          options: const [
            (value: 'all', label: 'All'),
            (value: 'income', label: 'Income'),
            (value: 'expense', label: 'Expenses'),
            (value: 'transfer', label: 'Transfers'),
          ],
          onChanged: (v) => setState(() => _tab = v),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _summaryTile(colors, 'Income', income,
                  const Color(0xFF3DEBA8)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _summaryTile(colors, 'Expenses', expenses,
                  const Color(0xFFFF5C7A)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SearchField(
          colors: colors,
          controller: _searchController,
          hint: 'Search transactions…',
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 14),
        if (dates.isEmpty)
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No transactions',
            subtitle: 'No entries match your filter',
            colors: colors,
          )
        else
          for (final date in dates) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 0, 8),
              child: Text(fmtDate(date).toUpperCase(),
                  style: sans(
                      size: 12,
                      weight: FontWeight.w700,
                      color: colors.sub,
                      letterSpacing: 0.6)),
            ),
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: colors.card,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < groups[date]!.length; i++) ...[
                    if (i > 0)
                      ThinDivider(colors: colors, indent: 16),
                    _txRow(colors, groups[date]![i], app),
                  ],
                ],
              ),
            ),
          ],
      ],
    );
  }

  Widget _summaryTile(Palette colors, String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: sans(
                  size: 11,
                  weight: FontWeight.w600,
                  color: color,
                  letterSpacing: 0.5)),
          const SizedBox(height: 3),
          Text('Rs ${fmt(value)}',
              style: mono(size: 18, weight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _txRow(Palette colors, AppTransaction tx, AppState app) {
    final acc = app.accountById(tx.accountId);
    final amtColor = tx.isIncome
        ? const Color(0xFF3DEBA8)
        : tx.isTransfer
            ? const Color(0xFF60A5FA)
            : const Color(0xFFFF5C7A);
    final sign = tx.isIncome ? '+' : (tx.isTransfer ? '⇄' : '-');

    return InkWell(
      onTap: () => showTransactionDetail(context, tx),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: categoryColor(tx.category).withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: CategoryDot(category: tx.category, size: 12)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.note.isNotEmpty ? tx.note : tx.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(
                          size: 14,
                          weight: FontWeight.w600,
                          color: colors.text)),
                  Text('${tx.category} · ${acc?.name ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(size: 12, color: colors.sub)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$sign Rs ${fmt(tx.amount)}',
                    style: mono(
                        size: 15,
                        weight: FontWeight.w700,
                        color: amtColor)),
                if (tx.isPending) const StatusChip(status: 'pending'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../models/app_transaction.dart';
import '../state/app_state.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/color_x.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import 'modals/sheets.dart';

/// Overview screen: net worth, accounts, budget, breakdown, recent activity.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.month});

  final String month;

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final app = context.watch<AppState>();

    if (app.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF3DEBA8)),
      );
    }

    final monthTxs = app.transactionsInMonth(month);
    final income = monthTxs
        .where((t) => t.isIncome && t.status == 'received')
        .fold(0.0, (s, t) => s + t.amount);
    final expenses =
        monthTxs.where((t) => t.isExpense).fold(0.0, (s, t) => s + t.amount);
    final net = income - expenses;
    final pending = app.transactions
        .where((t) => t.isIncome && t.isPending)
        .fold(0.0, (s, t) => s + t.amount);
    final lent = app.totalLent;
    final recent = [...app.transactions]
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      children: [
        _heroCard(colors, app.totalBalance, income, expenses, net),
        const SizedBox(height: 16),
        _accountsRow(context, colors, app),
        const SizedBox(height: 16),
        _budgetCard(colors, income, expenses, pending),
        if (lent > 0 || pending > 0) ...[
          const SizedBox(height: 16),
          _receivablesCard(colors, lent, pending),
        ],
        if (expenses > 0) ...[
          const SizedBox(height: 16),
          _breakdownCard(colors, monthTxs, expenses),
        ],
        const SizedBox(height: 16),
        _recentCard(context, colors, recent.take(5).toList(), app),
      ],
    );
  }

  // ── Net worth hero ───────────────────────────────────────────────────
  Widget _heroCard(
      Palette colors, double total, double income, double expenses, double net) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(gradient: Brand.hero),
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TOTAL BALANCE',
                    style: sans(
                        size: 12,
                        weight: FontWeight.w600,
                        color: const Color(0xFF7A9DC0),
                        letterSpacing: 0.7)),
                const SizedBox(height: 8),
                Text('Rs ${fmt(total)}',
                    style: mono(
                        size: 38,
                        weight: FontWeight.w800,
                        color: const Color(0xFFECF0FF))),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _heroStat('Income', '+Rs ${fmt(income)}',
                        const Color(0xFF3DEBA8)),
                    _heroDivider(),
                    _heroStat('Expenses', '-Rs ${fmt(expenses)}',
                        const Color(0xFFFF5C7A)),
                    _heroDivider(),
                    _heroStat(
                        'Net',
                        '${net >= 0 ? '+' : ''}Rs ${fmt(net)}',
                        net >= 0
                            ? const Color(0xFF3DEBA8)
                            : const Color(0xFFFF5C7A)),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            right: -20,
            top: -20,
            child: _glow(120, 0.12),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF3DEBA8).withValues(alpha: opacity),
        ),
      );

  Widget _heroStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: sans(size: 11, color: const Color(0xFF7A9DC0))),
        const SizedBox(height: 3),
        Text(value,
            style: mono(size: 15, weight: FontWeight.w700, color: color)),
      ],
    );
  }

  Widget _heroDivider() => Container(
        width: 1,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: const Color(0xFF1E3550),
      );

  // ── Accounts row ─────────────────────────────────────────────────────
  Widget _accountsRow(BuildContext context, Palette colors, AppState app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ACCOUNTS',
            style: sans(
                size: 13,
                weight: FontWeight.w700,
                color: colors.sub,
                letterSpacing: 0.6)),
        const SizedBox(height: 10),
        SizedBox(
          height: 116,
          child: app.accounts.isEmpty
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => showAddAccountSheet(context),
                    child: Text('+ Add your first account',
                        style: sans(size: 13, color: colors.sub)),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: app.accounts.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final acc = app.accounts[i];
                    final color = colorFromHex(acc.colorHex);
                    return Container(
                      width: 140,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.card,
                        border: Border.all(color: colors.border),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AccountIconBox(
                              type: acc.type, color: color, size: 30),
                          const SizedBox(height: 10),
                          Text(acc.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(size: 11, color: colors.sub)),
                          const SizedBox(height: 2),
                          Text('Rs ${fmt(app.balanceOf(acc))}',
                              style: mono(
                                  size: 16,
                                  weight: FontWeight.w700,
                                  color: colors.text)),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Monthly budget ───────────────────────────────────────────────────
  Widget _budgetCard(
      Palette colors, double income, double expenses, double pending) {
    final pct = income > 0 ? (expenses / income * 100) : 0.0;
    final remaining = (income - expenses).clamp(0, double.infinity).toDouble();

    return AppCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Monthly Budget',
                  style: sans(
                      size: 14,
                      weight: FontWeight.w700,
                      color: colors.text)),
              Text(fmtMonthLong(month),
                  style: sans(size: 12, color: colors.sub)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Spent vs Earned',
                  style: sans(size: 12, color: colors.sub)),
              Text('${pct.round()}%',
                  style: mono(
                      size: 12,
                      weight: FontWeight.w600,
                      color: colors.text)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: income > 0 ? (expenses / income).clamp(0, 1) : 0,
              minHeight: 8,
              backgroundColor: colors.elevated,
              valueColor: AlwaysStoppedAnimation(
                  expenses > income
                      ? const Color(0xFFFF5C7A)
                      : const Color(0xFF3DEBA8)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Remaining',
                      style: sans(size: 11, color: colors.sub)),
                  Text('Rs ${fmt(remaining)}',
                      style: mono(
                          size: 18,
                          weight: FontWeight.w700,
                          color: income - expenses >= 0
                              ? const Color(0xFF3DEBA8)
                              : const Color(0xFFFF5C7A))),
                ],
              ),
              if (pending > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Pending Income',
                        style: sans(size: 11, color: colors.sub)),
                    Text('Rs ${fmt(pending)}',
                        style: mono(
                            size: 18,
                            weight: FontWeight.w700,
                            color: const Color(0xFFFFB547))),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Money to receive (lent out + pending income) ─────────────────────
  Widget _receivablesCard(Palette colors, double lent, double pending) {
    return AppCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('To Receive',
              style: sans(
                  size: 14, weight: FontWeight.w700, color: colors.text)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _receivableTile(colors, 'Total Lent', lent,
                    const Color(0xFF3DEBA8)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _receivableTile(colors, 'Pending Income', pending,
                    const Color(0xFFFFB547)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _receivableTile(
      Palette colors, String label, double value, Color color) {
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

  // ── Expense breakdown ────────────────────────────────────────────────
  Widget _breakdownCard(
      Palette colors, List<AppTransaction> monthTxs, double expenses) {
    final byCat = <String, double>{};
    for (final t in monthTxs.where((t) => t.isExpense)) {
      byCat[t.category] = (byCat[t.category] ?? 0) + t.amount;
    }
    final sorted = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(4).toList();

    return AppCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Expense Breakdown',
              style: sans(
                  size: 14, weight: FontWeight.w700, color: colors.text)),
          const SizedBox(height: 14),
          for (final e in top) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CategoryDot(category: e.key, size: 9),
                    const SizedBox(width: 8),
                    Text(e.key, style: sans(size: 13, color: colors.text)),
                  ],
                ),
                Text('Rs ${fmt(e.value)}',
                    style: mono(
                        size: 13,
                        weight: FontWeight.w600,
                        color: colors.text)),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (e.value / expenses).clamp(0, 1),
                minHeight: 5,
                backgroundColor: colors.elevated,
                valueColor: AlwaysStoppedAnimation(categoryColor(e.key)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  // ── Recent transactions ──────────────────────────────────────────────
  Widget _recentCard(BuildContext context, Palette colors,
      List<AppTransaction> recent, AppState app) {
    return AppCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent Transactions',
              style: sans(
                  size: 14, weight: FontWeight.w700, color: colors.text)),
          if (recent.isEmpty)
            EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No transactions yet',
              subtitle: 'Tap + to add your first entry',
              colors: colors,
            )
          else
            for (int i = 0; i < recent.length; i++) ...[
              if (i > 0) ThinDivider(colors: colors),
              _txRow(context, colors, recent[i], app),
            ],
        ],
      ),
    );
  }

  Widget _txRow(BuildContext context, Palette colors, AppTransaction tx,
      AppState app) {
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
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: categoryColor(tx.category).withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(12),
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
                  Text('${fmtDateShort(tx.date)} · ${acc?.name ?? 'Unknown'}',
                      style: sans(size: 12, color: colors.sub)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$sign Rs ${fmt(tx.amount)}',
                    style: mono(
                        size: 14,
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

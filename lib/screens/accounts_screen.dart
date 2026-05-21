import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../state/app_state.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/color_x.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import 'modals/sheets.dart';

/// Lists all money accounts with their balances and in/out totals.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final app = context.watch<AppState>();

    if (app.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF3DEBA8)),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      children: [
        // Total card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          decoration: BoxDecoration(
            gradient: Brand.hero,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TOTAL ACROSS ALL ACCOUNTS',
                  style: sans(
                      size: 12,
                      weight: FontWeight.w600,
                      color: const Color(0xFF7A9DC0),
                      letterSpacing: 0.7)),
              const SizedBox(height: 6),
              Text('Rs ${fmt(app.totalBalance)}',
                  style: mono(
                      size: 32,
                      weight: FontWeight.w800,
                      color: const Color(0xFFECF0FF))),
              const SizedBox(height: 6),
              Text(
                  '${app.accounts.length} account${app.accounts.length == 1 ? '' : 's'}',
                  style: sans(size: 12, color: const Color(0xFF7A9DC0))),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final acc in app.accounts) ...[
          _accountCard(context, colors, app, acc),
          const SizedBox(height: 16),
        ],
        GestureDetector(
          onTap: () => showAddAccountSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              border: Border.all(
                  color: colors.border, width: 1.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 18, color: colors.sub),
                const SizedBox(width: 8),
                Text('Add Account',
                    style: sans(
                        size: 15,
                        weight: FontWeight.w600,
                        color: colors.sub)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _accountCard(
      BuildContext context, Palette colors, AppState app, Account acc) {
    final color = colorFromHex(acc.colorHex);
    final txs = app.transactions.where((t) =>
        t.accountId == acc.id || t.toAccountId == acc.id);
    final totalIn = txs
        .where((t) =>
            (t.isIncome && t.status == 'received' && t.accountId == acc.id) ||
            (t.isTransfer && t.toAccountId == acc.id))
        .fold(0.0, (s, t) => s + t.amount);
    final totalOut = txs
        .where((t) =>
            (t.isExpense && t.accountId == acc.id) ||
            (t.isTransfer && t.accountId == acc.id))
        .fold(0.0, (s, t) => s + t.amount);

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              border: Border(bottom: BorderSide(color: colors.border)),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                AccountIconBox(type: acc.type, color: color, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(acc.name,
                          style: sans(
                              size: 16,
                              weight: FontWeight.w700,
                              color: colors.text)),
                      Text(acc.typeLabel,
                          style: sans(size: 12, color: colors.sub)),
                    ],
                  ),
                ),
                Text('Rs ${fmt(app.balanceOf(acc))}',
                    style: mono(
                        size: 22,
                        weight: FontWeight.w800,
                        color: colors.text)),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
            child: Row(
              children: [
                Expanded(
                  child: _inOut(colors, 'Total In', totalIn,
                      const Color(0xFF3DEBA8), '+'),
                ),
                Container(width: 1, height: 34, color: colors.border),
                const SizedBox(width: 18),
                Expanded(
                  child: _inOut(colors, 'Total Out', totalOut,
                      const Color(0xFFFF5C7A), '-'),
                ),
                IconButton(
                  onPressed: () => _confirmDelete(context, app, acc),
                  icon: Icon(Icons.delete_outline,
                      size: 18,
                      color: const Color(0xFFFF5C7A).withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inOut(
      Palette colors, String label, double value, Color color, String sign) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: sans(size: 11, color: colors.sub)),
        const SizedBox(height: 2),
        Text('$sign Rs ${fmt(value)}',
            style: mono(size: 14, weight: FontWeight.w700, color: color)),
      ],
    );
  }

  void _confirmDelete(BuildContext context, AppState app, Account acc) {
    final colors = context.read<ThemeController>().colors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('Delete account?',
            style: sans(
                size: 17, weight: FontWeight.w700, color: colors.text)),
        content: Text(
            'Remove "${acc.name}"? Its transactions will remain but show as Unknown.',
            style: sans(size: 13.5, color: colors.sub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: sans(color: colors.sub)),
          ),
          TextButton(
            onPressed: () {
              app.deleteAccount(acc.id);
              Navigator.of(ctx).pop();
            },
            child: Text('Delete',
                style: sans(
                    weight: FontWeight.w700,
                    color: const Color(0xFFFF5C7A))),
          ),
        ],
      ),
    );
  }
}

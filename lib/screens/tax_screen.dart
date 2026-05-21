import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/app_transaction.dart';
import '../state/app_state.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

/// Tax report: period summary, category breakdowns and CSV export.
class TaxScreen extends StatefulWidget {
  const TaxScreen({super.key});

  @override
  State<TaxScreen> createState() => _TaxScreenState();
}

class _TaxScreenState extends State<TaxScreen> {
  late String _from;
  late String _to;
  bool _exported = false;

  @override
  void initState() {
    super.initState();
    final months = recentMonths(12);
    _from = months.first;
    _to = months.last;
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

    final filtered = app.transactions.where((t) {
      final m = t.monthKey;
      return m.compareTo(_from) >= 0 && m.compareTo(_to) <= 0;
    }).toList();

    final income = filtered
        .where((t) => t.isIncome && t.status == 'received')
        .fold(0.0, (s, t) => s + t.amount);
    final expenses =
        filtered.where((t) => t.isExpense).fold(0.0, (s, t) => s + t.amount);
    final pending = filtered
        .where((t) => t.isIncome && t.isPending)
        .fold(0.0, (s, t) => s + t.amount);

    final incomeByCat = <String, double>{};
    for (final t in filtered.where((t) => t.isIncome && t.status == 'received')) {
      incomeByCat[t.category] = (incomeByCat[t.category] ?? 0) + t.amount;
    }
    final expenseByCat = <String, double>{};
    for (final t in filtered.where((t) => t.isExpense)) {
      expenseByCat[t.category] = (expenseByCat[t.category] ?? 0) + t.amount;
    }

    final months = recentMonths(24);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      children: [
        // Report period
        AppCard(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report Period',
                  style: sans(
                      size: 14,
                      weight: FontWeight.w700,
                      color: colors.text)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: AppDropdown<String>(
                      colors: colors,
                      label: 'From',
                      value: months.contains(_from) ? _from : months.first,
                      items: [
                        for (final m in months)
                          DropdownMenuItem(
                              value: m, child: Text(fmtMonthLong(m))),
                      ],
                      onChanged: (v) => setState(() => _from = v ?? _from),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDropdown<String>(
                      colors: colors,
                      label: 'To',
                      value: months.contains(_to) ? _to : months.last,
                      items: [
                        for (final m in months)
                          DropdownMenuItem(
                              value: m, child: Text(fmtMonthLong(m))),
                      ],
                      onChanged: (v) => setState(() => _to = v ?? _to),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Financial summary
        AppCard(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Financial Summary',
                  style: sans(
                      size: 14,
                      weight: FontWeight.w700,
                      color: colors.text)),
              const SizedBox(height: 4),
              Text('${filtered.length} transactions in period',
                  style: sans(size: 12, color: colors.sub)),
              const SizedBox(height: 10),
              _summaryRow(colors, 'Total Income (Received)',
                  'Rs ${fmtFull(income)}', const Color(0xFF3DEBA8),
                  bold: true),
              _summaryRow(colors, 'Total Expenses',
                  'Rs ${fmtFull(expenses)}', const Color(0xFFFF5C7A),
                  bold: true),
              _summaryRow(
                  colors,
                  'Net Profit / Loss',
                  '${income - expenses >= 0 ? '+' : '-'}Rs ${fmtFull(income - expenses)}',
                  income - expenses >= 0
                      ? const Color(0xFF3DEBA8)
                      : const Color(0xFFFF5C7A),
                  bold: true),
              if (pending > 0)
                _summaryRow(colors, 'Pending Income',
                    'Rs ${fmtFull(pending)}', const Color(0xFFFFB547)),
              _summaryRow(colors, 'Tax Year Transactions',
                  '${filtered.length}', colors.text,
                  last: true),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (incomeByCat.isNotEmpty) ...[
          _breakdownCard(colors, 'Income Breakdown', '(Tax-Ready)',
              const Color(0xFF3DEBA8), incomeByCat, income, 'income'),
          const SizedBox(height: 16),
        ],
        if (expenseByCat.isNotEmpty) ...[
          _breakdownCard(colors, 'Expense Breakdown', '',
              const Color(0xFFFF5C7A), expenseByCat, expenses, 'expenses'),
          const SizedBox(height: 16),
        ],

        PrimaryButton(
          label: _exported ? 'Exported!' : 'Export to CSV (Excel)',
          icon: _exported ? Icons.check : Icons.download,
          gradient: _exported
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF3DEBA8), Color(0xFF60A5FA)]),
          color: const Color(0xFF3DEBA8),
          onPressed: () => _exportCsv(app, filtered),
        ),
        const SizedBox(height: 8),
        Text(
          'Export includes all transaction details for tax filing purposes',
          textAlign: TextAlign.center,
          style: sans(size: 12, color: colors.sub),
        ),
      ],
    );
  }

  Widget _summaryRow(Palette colors, String label, String value, Color color,
      {bool bold = false, bool last = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                style: sans(
                    size: 14,
                    weight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: bold ? colors.text : colors.sub)),
          ),
          Text(value,
              style: mono(size: 14, weight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _breakdownCard(Palette colors, String title, String subtitle,
      Color color, Map<String, double> byCat, double total, String denom) {
    final sorted = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return AppCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: sans(
                      size: 14,
                      weight: FontWeight.w700,
                      color: colors.text)),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(subtitle,
                    style: sans(size: 12, color: const Color(0xFF3DEBA8))),
              ],
            ],
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < sorted.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: i == sorted.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  CategoryDot(category: sorted[i].key, size: 9),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(sorted[i].key,
                        style: sans(size: 13, color: colors.text)),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Rs ${fmt(sorted[i].value)}',
                          style: mono(
                              size: 14,
                              weight: FontWeight.w700,
                              color: color)),
                      Text(
                          '${total > 0 ? (sorted[i].value / total * 100).round() : 0}% of $denom',
                          style: sans(size: 11, color: colors.sub)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(
      AppState app, List<AppTransaction> filtered) async {
    String esc(Object? v) => '"${v.toString().replaceAll('"', '""')}"';
    final rows = <String>[
      [
        'Date',
        'Type',
        'Category',
        'Note',
        'Amount (LKR)',
        'Account',
        'Status',
      ].map(esc).join(','),
    ];
    for (final t in filtered) {
      rows.add([
        t.date,
        t.type,
        t.category,
        t.note,
        t.amount,
        app.accountById(t.accountId)?.name ?? '',
        t.status,
      ].map(esc).join(','));
    }
    final csv = rows.join('\r\n');
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final fileName = 'financial_report_${_from}_to_$_to.csv';

    try {
      await Share.shareXFiles(
        [
          XFile.fromData(bytes, mimeType: 'text/csv', name: fileName),
        ],
        fileNameOverrides: [fileName],
        subject: 'FinTrack Financial Report',
      );
      if (mounted) {
        setState(() => _exported = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _exported = false);
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not export the report')));
      }
    }
  }
}

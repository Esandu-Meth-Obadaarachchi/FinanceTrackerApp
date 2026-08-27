import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/loan.dart';
import '../state/app_state.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';
import 'modals/sheets.dart';

/// Tracks money lent to and borrowed from other people.
class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  String _tab = 'lent';

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final app = context.watch<AppState>();

    if (app.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF3DEBA8)),
      );
    }

    // Outstanding, not lifetime totals — what is actually still owed.
    final lentTotal = app.totalLent;
    final borrowedTotal = app.totalBorrowed;
    final filtered = app.loans.where((l) => l.loanType == _tab).toList();

    final wide = context.isWide;

    final addCard = GestureDetector(
      onTap: () => showAddLoanSheet(context),
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
            Text('Record Loan',
                style: sans(
                    size: 15, weight: FontWeight.w600, color: colors.sub)),
          ],
        ),
      ),
    );

    return ListView(
      padding: context.pagePadding,
      children: [
        ContentWidth(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _summaryTile(
                        colors, 'To Receive', lentTotal, const Color(0xFF3DEBA8)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _summaryTile(colors, 'To Pay Back', borrowedTotal,
                        const Color(0xFFFF5C7A)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SegmentedControl<String>(
                colors: colors,
                value: _tab,
                options: const [
                  (value: 'lent', label: 'I Lent'),
                  (value: 'borrowed', label: 'I Borrowed'),
                ],
                onChanged: (v) => setState(() => _tab = v),
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty) ...[
                EmptyState(
                  icon: Icons.people_outline,
                  title:
                      _tab == 'lent' ? 'No money lent' : 'No loans borrowed',
                  subtitle: 'Tap + to record a loan',
                  colors: colors,
                ),
                const SizedBox(height: 14),
                addCard,
              ] else if (wide)
                LayoutBuilder(
                  builder: (_, c) {
                    final cardWidth = (c.maxWidth - 16) / 2;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final loan in filtered)
                          SizedBox(
                            width: cardWidth,
                            child: _loanCard(colors, app, loan),
                          ),
                        SizedBox(width: cardWidth, child: addCard),
                      ],
                    );
                  },
                )
              else ...[
                for (final loan in filtered) ...[
                  _loanCard(colors, app, loan),
                  const SizedBox(height: 12),
                ],
                addCard,
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Settlement progress, shown once a loan has been partly paid off.
  Widget _progress(Palette colors, Loan loan, double repaid, double outstanding,
      Color tone) {
    final pct = loan.amount > 0 ? (repaid / loan.amount).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: colors.elevated,
              valueColor: AlwaysStoppedAnimation(tone),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text('Rs ${fmt(repaid)} settled',
                    style: sans(size: 11.5, color: colors.sub)),
              ),
              Text(
                  outstanding > 0
                      ? 'Rs ${fmt(outstanding)} left'
                      : 'Fully settled',
                  style: sans(
                      size: 11.5, weight: FontWeight.w600, color: tone)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryTile(
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

  Widget _loanCard(Palette colors, AppState app, Loan loan) {
    final loanColor =
        loan.isLent ? const Color(0xFF3DEBA8) : const Color(0xFFFF5C7A);
    final acc = app.accountById(loan.accountId);
    final repaid = app.repaidOf(loan);
    final outstanding = app.outstandingOf(loan);
    final settled = app.isSettled(loan);

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: loanColor.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      loan.who.isNotEmpty
                          ? loan.who[0].toUpperCase()
                          : '?',
                      style: sans(
                          size: 18,
                          weight: FontWeight.w700,
                          color: loanColor),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loan.who,
                          style: sans(
                              size: 15,
                              weight: FontWeight.w700,
                              color: colors.text)),
                      const SizedBox(height: 2),
                      Text(
                          '${loan.reason.isNotEmpty ? loan.reason : 'Loan'} · ${fmtDateShort(loan.date)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(size: 12, color: colors.sub)),
                      if (acc != null)
                        Text(acc.name,
                            style: sans(size: 11, color: colors.sub)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Rs ${fmt(loan.amount)}',
                        style: mono(
                            size: 16,
                            weight: FontWeight.w700,
                            color: loanColor)),
                    const SizedBox(height: 2),
                    StatusChip(status: settled ? 'repaid' : 'pending'),
                  ],
                ),
              ],
            ),
          ),
          if (repaid > 0) _progress(colors, loan, repaid, outstanding, loanColor),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                if (!settled)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => showLoanPaymentSheet(context, loan),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: loanColor.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                              loan.isLent ? 'Record Receipt' : 'Make Payment',
                              style: sans(
                                  size: 12,
                                  weight: FontWeight.w600,
                                  color: loanColor)),
                        ),
                      ),
                    ),
                  ),
                if (!settled) const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => app.deleteLoan(loan.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5C7A).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Remove',
                        style: sans(
                            size: 12,
                            weight: FontWeight.w600,
                            color: const Color(0xFFFF5C7A))),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

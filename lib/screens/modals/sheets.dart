import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/categories.dart';
import '../../models/account.dart';
import '../../models/app_transaction.dart';
import '../../models/loan.dart';
import '../../models/recurring_rule.dart';
import '../../state/app_state.dart';
import '../../theme/app_text.dart';
import '../../theme/palette.dart';
import '../../theme/theme_controller.dart';
import '../../utils/color_x.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/sheet_scaffold.dart';

const _typeColors = {
  'income': Color(0xFF3DEBA8),
  'expense': Color(0xFFFF5C7A),
  'transfer': Color(0xFF60A5FA),
};

/// Opens [sheet] as a bottom sheet, re-providing [AppState].
///
/// Bottom sheets are inserted under the root navigator — above the
/// `ChangeNotifierProvider<AppState>` from AuthGate — so without this they
/// cannot find AppState. `.value` re-exposes the existing instance without
/// taking ownership of its lifecycle.
void _showWithState(BuildContext context, Widget sheet) {
  final app = context.read<AppState>();
  showAppSheet(
    context,
    builder: (_) =>
        ChangeNotifierProvider<AppState>.value(value: app, child: sheet),
  );
}

// ════════════════════════════════════════════════════════════════════════
// Type picker
// ════════════════════════════════════════════════════════════════════════
void showTypePicker(BuildContext context) {
  _showWithState(context, const _TypePickerSheet());
}

class _TypePickerSheet extends StatelessWidget {
  const _TypePickerSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.read<ThemeController>().colors;
    final types = [
      ('income', 'Income', 'Salary, freelance, rent…', const Color(0xFF3DEBA8),
          Icons.arrow_downward),
      ('expense', 'Expense', 'Food, fuel, bills…', const Color(0xFFFF5C7A),
          Icons.arrow_upward),
      ('transfer', 'Transfer', 'Move between accounts', const Color(0xFF60A5FA),
          Icons.swap_horiz),
    ];

    return SheetScaffold(
      title: 'What are you recording?',
      colors: colors,
      children: [
        for (final t in types) ...[
          GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
              showAddTransactionSheet(context, initialType: t.$1);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: t.$4.withValues(alpha: 0.06),
                border: Border.all(color: t.$4.withValues(alpha: 0.2), width: 1.5),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: t.$4.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(t.$5, color: t.$4, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.$2,
                            style: sans(
                                size: 17,
                                weight: FontWeight.w700,
                                color: t.$4)),
                        const SizedBox(height: 2),
                        Text(t.$3,
                            style: sans(size: 13, color: colors.sub)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: t.$4.withValues(alpha: 0.5)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Add / edit transaction
// ════════════════════════════════════════════════════════════════════════
void showAddTransactionSheet(
  BuildContext context, {
  AppTransaction? edit,
  String? initialType,
}) {
  _showWithState(
      context, _AddTransactionSheet(edit: edit, initialType: initialType));
}

class _AddTransactionSheet extends StatefulWidget {
  const _AddTransactionSheet({this.edit, this.initialType});
  final AppTransaction? edit;
  final String? initialType;

  @override
  State<_AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<_AddTransactionSheet> {
  late String _type;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  String _accountId = '';
  String _toAccountId = '';
  String _category = '';
  late DateTime _date;
  String _status = 'received';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _type = e?.type ?? widget.initialType ?? 'expense';
    _amount = TextEditingController(text: e != null ? _trimAmt(e.amount) : '');
    _note = TextEditingController(text: e?.note ?? '');
    _category = e?.category ?? '';
    _date = e != null ? e.dateTime : DateTime.now();
    _status = e?.status ?? 'received';
    _accountId = e?.accountId ?? '';
    _toAccountId = e?.toAccountId ?? '';
  }

  String _trimAmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String _defaultCategory(String t) {
    if (t == 'income') return kIncomeCategories.first.label;
    if (t == 'expense') return kExpenseCategories.first.label;
    return 'Transfer';
  }

  Future<void> _save(AppState app) async {
    final amt = double.tryParse(_amount.text.trim());
    if (amt == null || amt <= 0) {
      _toast('Enter a valid amount');
      return;
    }
    if (_accountId.isEmpty) {
      _toast('Select an account');
      return;
    }
    if (_type == 'transfer' && _toAccountId.isEmpty) {
      _toast('Select a destination account');
      return;
    }

    setState(() => _saving = true);
    final tx = AppTransaction(
      id: widget.edit?.id ?? '',
      type: _type,
      amount: amt,
      accountId: _accountId,
      toAccountId: _type == 'transfer' ? _toAccountId : null,
      category: _category.isNotEmpty ? _category : _defaultCategory(_type),
      note: _note.text.trim(),
      date: dateKeyOf(_date),
      status: _type == 'income' ? _status : 'received',
    );
    try {
      if (widget.edit != null) {
        await app.updateTransaction(tx);
      } else {
        await app.addTransaction(tx);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('Could not save — check your connection');
      }
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.read<ThemeController>().colors;
    final app = context.watch<AppState>();
    final accounts = app.accounts;
    final typeColor = _typeColors[_type]!;

    // Default the selected account once accounts load.
    if (_accountId.isEmpty && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }
    if (_toAccountId.isEmpty && accounts.length > 1) {
      _toAccountId = accounts.where((a) => a.id != _accountId).first.id;
    }

    return SheetScaffold(
      title: widget.edit != null ? 'Edit Transaction' : 'Add Transaction',
      colors: colors,
      children: [
        // Type selector
        Row(
          children: [
            for (final t in ['income', 'expense', 'transfer']) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _type = t;
                    _category = '';
                  }),
                  child: Container(
                    margin: EdgeInsets.only(right: t != 'transfer' ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _type == t
                          ? _typeColors[t]!.withValues(alpha: 0.10)
                          : Colors.transparent,
                      border: Border.all(
                        color: _type == t
                            ? _typeColors[t]!
                            : colors.inputBorder,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        t[0].toUpperCase() + t.substring(1),
                        style: sans(
                          size: 13,
                          weight: FontWeight.w600,
                          color: _type == t ? _typeColors[t]! : colors.sub,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // Amount
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: colors.inputBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text('AMOUNT (LKR)',
                  style: sans(
                      size: 12,
                      weight: FontWeight.w600,
                      color: colors.sub,
                      letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('Rs ',
                      style: mono(size: 22, color: colors.sub)),
                  IntrinsicWidth(
                    child: TextField(
                      controller: _amount,
                      autofocus: widget.edit == null,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [amountFormatter],
                      style: mono(
                          size: 36,
                          weight: FontWeight.w700,
                          color: typeColor),
                      cursorColor: typeColor,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: '0',
                        hintStyle:
                            mono(size: 36, weight: FontWeight.w700, color: colors.muted),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (accounts.isEmpty)
          _infoBox(colors, 'Add an account first from the Accounts screen.')
        else ...[
          AppDropdown<String>(
            colors: colors,
            label: 'Account',
            value: _accountId,
            items: [
              for (final a in accounts)
                DropdownMenuItem(
                  value: a.id,
                  child: Text(
                      '${a.name}  (Rs ${fmt(app.balanceOf(a))})',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _accountId = v ?? ''),
          ),
          if (_type == 'transfer') ...[
            const SizedBox(height: 14),
            AppDropdown<String>(
              colors: colors,
              label: 'To Account',
              value: accounts.any((a) => a.id == _toAccountId && a.id != _accountId)
                  ? _toAccountId
                  : (accounts.where((a) => a.id != _accountId).isNotEmpty
                      ? accounts.where((a) => a.id != _accountId).first.id
                      : _accountId),
              items: [
                for (final a in accounts.where((a) => a.id != _accountId))
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => _toAccountId = v ?? ''),
            ),
          ],
        ],

        // Category
        if (_type != 'transfer') ...[
          const SizedBox(height: 16),
          FieldLabel(
            'Category',
            colors: colors,
            trailing: Text('— tap to select',
                style: sans(size: 11, color: const Color(0xFFFFB547))),
          ),
          _categoryPicker(colors),
        ],

        const SizedBox(height: 16),
        AppTextField(
          colors: colors,
          controller: _note,
          label: 'Note / Description',
          hint: 'e.g. Monthly salary from XYZ',
        ),
        const SizedBox(height: 14),
        _dateField(colors),

        if (_type == 'income') ...[
          const SizedBox(height: 14),
          FieldLabel('Status', colors: colors),
          Row(
            children: [
              for (final s in ['received', 'pending']) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _status = s),
                    child: Container(
                      margin: EdgeInsets.only(right: s == 'received' ? 8 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _status == s
                            ? (s == 'received'
                                    ? const Color(0xFF3DEBA8)
                                    : const Color(0xFFFFB547))
                                .withValues(alpha: 0.10)
                            : Colors.transparent,
                        border: Border.all(
                          color: _status == s
                              ? (s == 'received'
                                  ? const Color(0xFF3DEBA8)
                                  : const Color(0xFFFFB547))
                              : colors.inputBorder,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          s[0].toUpperCase() + s.substring(1),
                          style: sans(
                            size: 13,
                            weight: FontWeight.w600,
                            color: _status == s
                                ? (s == 'received'
                                    ? const Color(0xFF3DEBA8)
                                    : const Color(0xFFFFB547))
                                : colors.sub,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],

        const SizedBox(height: 22),
        PrimaryButton(
          label: widget.edit != null
              ? 'Update Transaction'
              : 'Add ${_type[0].toUpperCase()}${_type.substring(1)}',
          color: typeColor,
          busy: _saving,
          onPressed: accounts.isEmpty ? null : () => _save(app),
        ),
      ],
    );
  }

  Widget _infoBox(Palette colors, String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFB547).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline,
                size: 16, color: Color(0xFFFFB547)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: sans(size: 12.5, color: colors.text))),
          ],
        ),
      );

  Widget _categoryPicker(Palette colors) {
    if (_type == 'income') {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: SingleChildScrollView(
          child: Column(
            children: [
              for (final c in kIncomeCategories) _incomeCatTile(c, colors),
            ],
          ),
        ),
      );
    }
    // Expense — grouped chips.
    final groups = <String, List<CategoryDef>>{};
    for (final c in kExpenseCategories) {
      groups.putIfAbsent(c.group, () => []).add(c);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 0, 6),
                child: Text(entry.key.toUpperCase(),
                    style: sans(
                        size: 10,
                        weight: FontWeight.w700,
                        color: colors.sub,
                        letterSpacing: 0.7)),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in entry.value) _expenseChip(c, colors),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _incomeCatTile(CategoryDef c, Palette colors) {
    final selected = _category == c.label;
    final col = categoryColor(c.label);
    return GestureDetector(
      onTap: () => setState(() => _category = c.label),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? col.withValues(alpha: 0.13) : Colors.transparent,
          border: Border.all(
              color: selected ? col : colors.inputBorder, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.label,
                      style: sans(
                          size: 13,
                          weight: FontWeight.w600,
                          color: selected ? col : colors.text)),
                  const SizedBox(height: 1),
                  Text(c.note,
                      style: sans(size: 11, color: colors.sub)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TagPill(
              text: c.taxable ? 'TAXABLE' : 'EXEMPT',
              color: c.taxable
                  ? const Color(0xFFFFB547)
                  : const Color(0xFF3DEBA8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expenseChip(CategoryDef c, Palette colors) {
    final selected = _category == c.label;
    final col = categoryColor(c.label);
    return GestureDetector(
      onTap: () => setState(() => _category = c.label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? col.withValues(alpha: 0.13) : Colors.transparent,
          border: Border.all(
              color: selected ? col : colors.inputBorder, width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(c.label,
                style: sans(
                    size: 12,
                    weight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? col : colors.sub)),
            if (c.deductible) ...[
              const SizedBox(width: 4),
              Text('✓ TAX',
                  style: sans(
                      size: 9,
                      weight: FontWeight.w700,
                      color: const Color(0xFF3DEBA8))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dateField(Palette colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel('Date', colors: colors),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2015),
              lastDate: DateTime(2100),
            );
            if (picked != null) setState(() => _date = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: colors.inputBg,
              border: Border.all(color: colors.inputBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(fmtDate(dateKeyOf(_date)),
                    style: sans(size: 14, color: colors.text)),
                const Spacer(),
                Icon(Icons.calendar_today_outlined,
                    size: 16, color: colors.sub),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Add account
// ════════════════════════════════════════════════════════════════════════
void showAddAccountSheet(BuildContext context) {
  _showWithState(context, const _AddAccountSheet());
}

class _AddAccountSheet extends StatefulWidget {
  const _AddAccountSheet();
  @override
  State<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<_AddAccountSheet> {
  final _name = TextEditingController();
  final _balance = TextEditingController();
  String _type = 'bank';
  Color _color = kAccountColors.first;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save(AppState app) async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter an account name')));
      return;
    }
    setState(() => _saving = true);
    try {
      await app.addAccount(Account(
        id: '',
        name: _name.text.trim(),
        type: _type,
        colorHex: _color.toHex(),
        openingBalance: double.tryParse(_balance.text.trim()) ?? 0,
      ));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save account')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.read<ThemeController>().colors;
    final app = context.read<AppState>();

    return SheetScaffold(
      title: 'Add Account',
      colors: colors,
      children: [
        AppTextField(
          colors: colors,
          controller: _name,
          label: 'Account Name',
          hint: 'e.g. Seylan Savings',
        ),
        const SizedBox(height: 14),
        FieldLabel('Account Type', colors: colors),
        Row(
          children: [
            for (final t in const [
              ('bank', 'Bank'),
              ('cash', 'Cash'),
              ('fd', 'Fixed Deposit'),
            ]) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _type = t.$1),
                  child: Container(
                    margin: EdgeInsets.only(right: t.$1 != 'fd' ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _type == t.$1
                          ? _color.withValues(alpha: 0.10)
                          : Colors.transparent,
                      border: Border.all(
                        color: _type == t.$1 ? _color : colors.inputBorder,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(t.$2,
                          textAlign: TextAlign.center,
                          style: sans(
                              size: 13,
                              weight: FontWeight.w600,
                              color: _type == t.$1 ? _color : colors.sub)),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        AppTextField(
          colors: colors,
          controller: _balance,
          label: 'Opening Balance (LKR)',
          hint: '0',
          prefix: 'Rs',
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 14),
        FieldLabel('Colour', colors: colors),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in kAccountColors)
              GestureDetector(
                onTap: () => setState(() => _color = c),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _color == c ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        PrimaryButton(
          label: 'Add Account',
          color: _color,
          busy: _saving,
          onPressed: () => _save(app),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Add loan
// ════════════════════════════════════════════════════════════════════════
void showAddLoanSheet(BuildContext context) {
  _showWithState(context, const _AddLoanSheet());
}

class _AddLoanSheet extends StatefulWidget {
  const _AddLoanSheet();
  @override
  State<_AddLoanSheet> createState() => _AddLoanSheetState();
}

class _AddLoanSheetState extends State<_AddLoanSheet> {
  final _who = TextEditingController();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String _loanType = 'lent';
  DateTime _date = DateTime.now();
  String _accountId = '';
  bool _saving = false;

  @override
  void dispose() {
    _who.dispose();
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save(AppState app) async {
    final amt = double.tryParse(_amount.text.trim());
    if (_who.text.trim().isEmpty || amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a name and amount')));
      return;
    }
    setState(() => _saving = true);
    try {
      await app.addLoan(Loan(
        id: '',
        loanType: _loanType,
        who: _who.text.trim(),
        amount: amt,
        reason: _reason.text.trim(),
        date: dateKeyOf(_date),
        accountId: _accountId,
        status: 'pending',
      ));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save loan')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.read<ThemeController>().colors;
    final app = context.watch<AppState>();
    final accounts = app.accounts;
    final loanColor = _loanType == 'lent'
        ? const Color(0xFF3DEBA8)
        : const Color(0xFFFF5C7A);
    if (_accountId.isEmpty && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }

    return SheetScaffold(
      title: 'Add Loan',
      colors: colors,
      children: [
        Row(
          children: [
            for (final t in const [('lent', 'I Lent'), ('borrowed', 'I Borrowed')]) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _loanType = t.$1),
                  child: Container(
                    margin: EdgeInsets.only(right: t.$1 == 'lent' ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: _loanType == t.$1
                          ? loanColor.withValues(alpha: 0.10)
                          : Colors.transparent,
                      border: Border.all(
                        color: _loanType == t.$1
                            ? loanColor
                            : colors.inputBorder,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(t.$2,
                          style: sans(
                              size: 13,
                              weight: FontWeight.w600,
                              color: _loanType == t.$1
                                  ? loanColor
                                  : colors.sub)),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        AppTextField(
          colors: colors,
          controller: _who,
          label: _loanType == 'lent' ? 'Lent To' : 'Borrowed From',
          hint: 'Person or company name',
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: colors.inputBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text('AMOUNT (LKR)',
                  style: sans(
                      size: 12,
                      weight: FontWeight.w600,
                      color: colors.sub,
                      letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Rs ', style: mono(size: 22, color: colors.sub)),
                  IntrinsicWidth(
                    child: TextField(
                      controller: _amount,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [amountFormatter],
                      style: mono(
                          size: 36,
                          weight: FontWeight.w700,
                          color: loanColor),
                      cursorColor: loanColor,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: '0',
                        hintStyle: mono(
                            size: 36,
                            weight: FontWeight.w700,
                            color: colors.muted),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppTextField(
          colors: colors,
          controller: _reason,
          label: 'Reason / Note',
          hint: 'e.g. Emergency loan',
        ),
        const SizedBox(height: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FieldLabel('Date', colors: colors),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2015),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                decoration: BoxDecoration(
                  color: colors.inputBg,
                  border: Border.all(color: colors.inputBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text(fmtDate(dateKeyOf(_date)),
                        style: sans(size: 14, color: colors.text)),
                    const Spacer(),
                    Icon(Icons.calendar_today_outlined,
                        size: 16, color: colors.sub),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (accounts.isNotEmpty) ...[
          const SizedBox(height: 14),
          AppDropdown<String>(
            colors: colors,
            label: 'Account',
            value: accounts.any((a) => a.id == _accountId)
                ? _accountId
                : accounts.first.id,
            items: [
              for (final a in accounts)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _accountId = v ?? ''),
          ),
        ],
        const SizedBox(height: 22),
        PrimaryButton(
          label: 'Add Loan',
          color: loanColor,
          busy: _saving,
          onPressed: () => _save(app),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Add / edit recurring rule
// ════════════════════════════════════════════════════════════════════════
void showAddRecurringSheet(BuildContext context, {RecurringRule? edit}) {
  _showWithState(context, _AddRecurringSheet(edit: edit));
}

class _AddRecurringSheet extends StatefulWidget {
  const _AddRecurringSheet({this.edit});
  final RecurringRule? edit;

  @override
  State<_AddRecurringSheet> createState() => _AddRecurringSheetState();
}

class _AddRecurringSheetState extends State<_AddRecurringSheet> {
  late String _type;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  String _accountId = '';
  String _category = '';
  late int _dayOfMonth;
  late String _startMonth;
  String _status = 'received';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _type = e?.type ?? 'expense';
    _amount = TextEditingController(text: e != null ? _trimAmt(e.amount) : '');
    _note = TextEditingController(text: e?.note ?? '');
    _category = e?.category ?? '';
    _dayOfMonth = e?.dayOfMonth ?? 1;
    _startMonth = e?.startMonth ?? monthKeyOf(DateTime.now());
    _status = e?.status ?? 'received';
    _accountId = e?.accountId ?? '';
  }

  String _trimAmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String _defaultCategory(String t) =>
      t == 'income' ? kIncomeCategories.first.label : kExpenseCategories.first.label;

  Future<void> _save(AppState app) async {
    final amt = double.tryParse(_amount.text.trim());
    if (amt == null || amt <= 0) {
      _toast('Enter a valid amount');
      return;
    }
    if (_accountId.isEmpty) {
      _toast('Select an account');
      return;
    }

    setState(() => _saving = true);
    final rule = RecurringRule(
      id: widget.edit?.id ?? '',
      type: _type,
      accountId: _accountId,
      category: _category.isNotEmpty ? _category : _defaultCategory(_type),
      note: _note.text.trim(),
      amount: amt,
      dayOfMonth: _dayOfMonth,
      status: _type == 'income' ? _status : 'received',
      active: widget.edit?.active ?? true,
      startMonth: _startMonth,
      lastGeneratedMonth: widget.edit?.lastGeneratedMonth,
    );
    try {
      if (widget.edit != null) {
        await app.updateRecurring(rule);
      } else {
        await app.addRecurring(rule);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('Could not save — check your connection');
      }
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.read<ThemeController>().colors;
    final app = context.watch<AppState>();
    final accounts = app.accounts;
    final typeColor = _typeColors[_type]!;

    if (_accountId.isEmpty && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }
    // Start month options: the rolling recent window plus a few months ahead.
    final startOptions = <String>[
      ...recentMonths(12),
      for (int i = 1; i <= 3; i++)
        monthKeyOf(DateTime(DateTime.now().year, DateTime.now().month + i, 1)),
    ];
    if (!startOptions.contains(_startMonth)) startOptions.insert(0, _startMonth);

    return SheetScaffold(
      title: widget.edit != null ? 'Edit Recurring' : 'Add Recurring',
      colors: colors,
      children: [
        // Type selector — income / expense only.
        Row(
          children: [
            for (final t in ['income', 'expense']) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _type = t;
                    _category = '';
                  }),
                  child: Container(
                    margin: EdgeInsets.only(right: t == 'income' ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _type == t
                          ? _typeColors[t]!.withValues(alpha: 0.10)
                          : Colors.transparent,
                      border: Border.all(
                        color: _type == t ? _typeColors[t]! : colors.inputBorder,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        t[0].toUpperCase() + t.substring(1),
                        style: sans(
                          size: 13,
                          weight: FontWeight.w600,
                          color: _type == t ? _typeColors[t]! : colors.sub,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // Amount
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: colors.inputBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text('AMOUNT (LKR) / MONTH',
                  style: sans(
                      size: 12,
                      weight: FontWeight.w600,
                      color: colors.sub,
                      letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Rs ', style: mono(size: 22, color: colors.sub)),
                  IntrinsicWidth(
                    child: TextField(
                      controller: _amount,
                      autofocus: widget.edit == null,
                      textAlign: TextAlign.center,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [amountFormatter],
                      style: mono(
                          size: 36, weight: FontWeight.w700, color: typeColor),
                      cursorColor: typeColor,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: '0',
                        hintStyle: mono(
                            size: 36,
                            weight: FontWeight.w700,
                            color: colors.muted),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (accounts.isEmpty)
          _infoBox(colors, 'Add an account first from the Accounts screen.')
        else
          AppDropdown<String>(
            colors: colors,
            label: 'Account',
            value: accounts.any((a) => a.id == _accountId)
                ? _accountId
                : accounts.first.id,
            items: [
              for (final a in accounts)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _accountId = v ?? ''),
          ),

        const SizedBox(height: 16),
        FieldLabel(
          'Category',
          colors: colors,
          trailing: Text('— tap to select',
              style: sans(size: 11, color: const Color(0xFFFFB547))),
        ),
        _categoryPicker(colors),

        const SizedBox(height: 16),
        AppTextField(
          colors: colors,
          controller: _note,
          label: 'Note / Description',
          hint: 'e.g. Monthly rent, Netflix…',
        ),

        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppDropdown<int>(
                colors: colors,
                label: 'Day of month',
                value: _dayOfMonth,
                items: [
                  for (int d = 1; d <= 31; d++)
                    DropdownMenuItem(value: d, child: Text('Day $d')),
                ],
                onChanged: (v) => setState(() => _dayOfMonth = v ?? 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppDropdown<String>(
                colors: colors,
                label: 'Starts',
                value: _startMonth,
                items: [
                  for (final m in startOptions)
                    DropdownMenuItem(value: m, child: Text(fmtMonthLong(m))),
                ],
                onChanged: (v) => setState(
                    () => _startMonth = v ?? monthKeyOf(DateTime.now())),
              ),
            ),
          ],
        ),

        if (_type == 'income') ...[
          const SizedBox(height: 14),
          FieldLabel('Status when added', colors: colors),
          Row(
            children: [
              for (final s in ['received', 'pending']) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _status = s),
                    child: Container(
                      margin: EdgeInsets.only(right: s == 'received' ? 8 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _status == s
                            ? (s == 'received'
                                    ? const Color(0xFF3DEBA8)
                                    : const Color(0xFFFFB547))
                                .withValues(alpha: 0.10)
                            : Colors.transparent,
                        border: Border.all(
                          color: _status == s
                              ? (s == 'received'
                                  ? const Color(0xFF3DEBA8)
                                  : const Color(0xFFFFB547))
                              : colors.inputBorder,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          s[0].toUpperCase() + s.substring(1),
                          style: sans(
                            size: 13,
                            weight: FontWeight.w600,
                            color: _status == s
                                ? (s == 'received'
                                    ? const Color(0xFF3DEBA8)
                                    : const Color(0xFFFFB547))
                                : colors.sub,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],

        const SizedBox(height: 22),
        PrimaryButton(
          label: widget.edit != null ? 'Update Automation' : 'Save Automation',
          color: typeColor,
          busy: _saving,
          onPressed: accounts.isEmpty ? null : () => _save(app),
        ),
      ],
    );
  }

  Widget _infoBox(Palette colors, String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFB547).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 16, color: Color(0xFFFFB547)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text, style: sans(size: 12.5, color: colors.text))),
          ],
        ),
      );

  Widget _categoryPicker(Palette colors) {
    if (_type == 'income') {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: SingleChildScrollView(
          child: Column(
            children: [
              for (final c in kIncomeCategories) _catChip(c, colors, wide: true),
            ],
          ),
        ),
      );
    }
    final groups = <String, List<CategoryDef>>{};
    for (final c in kExpenseCategories) {
      groups.putIfAbsent(c.group, () => []).add(c);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 0, 6),
                child: Text(entry.key.toUpperCase(),
                    style: sans(
                        size: 10,
                        weight: FontWeight.w700,
                        color: colors.sub,
                        letterSpacing: 0.7)),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in entry.value) _catChip(c, colors),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _catChip(CategoryDef c, Palette colors, {bool wide = false}) {
    final selected = _category == c.label;
    final col = categoryColor(c.label);
    return GestureDetector(
      onTap: () => setState(() => _category = c.label),
      child: Container(
        width: wide ? double.infinity : null,
        margin: EdgeInsets.only(bottom: wide ? 4 : 0),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? col.withValues(alpha: 0.13) : Colors.transparent,
          border:
              Border.all(color: selected ? col : colors.inputBorder, width: 1.5),
          borderRadius: BorderRadius.circular(wide ? 12 : 20),
        ),
        child: Text(c.label,
            style: sans(
                size: wide ? 13 : 12,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? col : colors.sub)),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Transaction detail
// ════════════════════════════════════════════════════════════════════════
void showTransactionDetail(BuildContext context, AppTransaction tx) {
  _showWithState(context, _TransactionDetailSheet(tx: tx));
}

class _TransactionDetailSheet extends StatelessWidget {
  const _TransactionDetailSheet({required this.tx});
  final AppTransaction tx;

  @override
  Widget build(BuildContext context) {
    final colors = context.read<ThemeController>().colors;
    final app = context.read<AppState>();
    final account = app.accountById(tx.accountId);
    final amtColor = _typeColors[tx.type] ?? const Color(0xFF94A3B8);
    final sign = tx.isIncome ? '+' : (tx.isTransfer ? '⇄ ' : '-');

    Widget row(String label, Widget value) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: colors.inputBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Text(label, style: sans(size: 13, color: colors.sub)),
              const Spacer(),
              value,
            ],
          ),
        );

    Widget txt(String s) => Text(s,
        style: sans(size: 13, weight: FontWeight.w600, color: colors.text));

    return SheetScaffold(
      title: 'Transaction Details',
      colors: colors,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 14),
          child: Column(
            children: [
              Text('$sign Rs ${fmtFull(tx.amount)}',
                  style: mono(
                      size: 38, weight: FontWeight.w700, color: amtColor)),
              const SizedBox(height: 4),
              Text(tx.note.isNotEmpty ? tx.note : tx.category,
                  style: sans(size: 14, color: colors.sub)),
            ],
          ),
        ),
        row('Date', txt(fmtDate(tx.date))),
        row('Type', txt(tx.type[0].toUpperCase() + tx.type.substring(1))),
        row('Category', txt(tx.category)),
        row('Account', txt(account?.name ?? 'Unknown')),
        if (tx.toAccountId != null)
          row('To Account',
              txt(app.accountById(tx.toAccountId!)?.name ?? 'Unknown')),
        if (tx.isIncome) row('Status', StatusChip(status: tx.status)),
        if (tx.isRecurring)
          row('Source', const TagPill(text: 'RECURRING', color: Color(0xFF3DEBA8))),
        if (tx.note.isNotEmpty) row('Note', txt(tx.note)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  showAddTransactionSheet(context, edit: tx);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.inputBorder, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit_outlined, size: 15, color: colors.text),
                      const SizedBox(width: 6),
                      Text('Edit',
                          style: sans(
                              size: 14,
                              weight: FontWeight.w600,
                              color: colors.text)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  await app.deleteTransaction(tx.id);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5C7A).withValues(alpha: 0.10),
                    border: Border.all(
                        color: const Color(0xFFFF5C7A).withValues(alpha: 0.2),
                        width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.delete_outline,
                          size: 15, color: Color(0xFFFF5C7A)),
                      const SizedBox(width: 6),
                      Text('Delete',
                          style: sans(
                              size: 14,
                              weight: FontWeight.w600,
                              color: const Color(0xFFFF5C7A))),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

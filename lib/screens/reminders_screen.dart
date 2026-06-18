import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/reminder.dart';
import '../state/app_state.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';
import '../widgets/sheet_scaffold.dart';

/// Opens the reminders manager, re-providing [AppState] for the pushed route.
void openReminders(BuildContext context) {
  final app = context.read<AppState>();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const RemindersScreen(),
      ),
    ),
  );
}

void _openSheet(BuildContext context, Widget sheet) {
  final app = context.read<AppState>();
  showAppSheet(
    context,
    builder: (_) =>
        ChangeNotifierProvider<AppState>.value(value: app, child: sheet),
  );
}

const _due = Color(0xFFFF5C7A);
const _soon = Color(0xFFFFB547);

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final app = context.watch<AppState>();
    final reminders = [...app.reminders]
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: colors.text),
        title: Text('Reminders',
            style: sans(size: 18, weight: FontWeight.w800, color: colors.text)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          Text(
            'Get notified before something is due — a bill, a card payment, '
            'rent, anything. Choose how many times and how often to be nudged.',
            style: sans(size: 12.5, color: colors.sub),
          ),
          const SizedBox(height: 16),
          if (reminders.isEmpty)
            EmptyState(
              icon: Icons.notifications_active_outlined,
              title: 'No reminders yet',
              subtitle: 'Add one to be reminded before it is due.',
              colors: colors,
            )
          else
            for (final r in reminders) _reminderCard(context, colors, app, r),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _openSheet(context, const _ReminderEditorSheet()),
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
                  Text('Add Reminder',
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

  Widget _reminderCard(
      BuildContext context, Palette colors, AppState app, Reminder r) {
    final dueText = _dueText(r);
    final dueColor = _dueColor(r, colors);

    return Opacity(
      opacity: r.active ? 1 : 0.55,
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
              onTap: () => _openSheet(context, _ReminderEditorSheet(edit: r)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: dueColor.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.notifications_outlined,
                          size: 20, color: dueColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.title.isNotEmpty ? r.title : 'Reminder',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(
                                  size: 15,
                                  weight: FontWeight.w700,
                                  color: colors.text)),
                          const SizedBox(height: 2),
                          Text('$dueText · ${_scheduleText(context, r)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(size: 12, color: colors.sub)),
                        ],
                      ),
                    ),
                    if (r.amount > 0) ...[
                      const SizedBox(width: 8),
                      Text('Rs ${fmt(r.amount)}',
                          style: mono(
                              size: 15,
                              weight: FontWeight.w700,
                              color: colors.text)),
                    ],
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
                    onChanged: (v) =>
                        app.updateReminder(r.copyWith(active: v)),
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
                              color: _due)),
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

  String _dueText(Reminder r) {
    final due = r.dueDateTime;
    if (due == null) return r.dueDate;
    final now = DateTime.now();
    final d0 = DateTime(now.year, now.month, now.day);
    final d1 = DateTime(due.year, due.month, due.day);
    final diff = d1.difference(d0).inDays;
    if (diff == 0) return 'Due today';
    if (diff == 1) return 'Due tomorrow';
    if (diff > 1) return 'Due in $diff days';
    if (diff == -1) return 'Overdue 1 day';
    return 'Overdue ${-diff} days';
  }

  Color _dueColor(Reminder r, Palette colors) {
    final due = r.dueDateTime;
    if (due == null) return colors.sub;
    final now = DateTime.now();
    final d0 = DateTime(now.year, now.month, now.day);
    final diff = DateTime(due.year, due.month, due.day).difference(d0).inDays;
    if (diff < 0) return _due;
    if (diff <= 3) return _soon;
    return const Color(0xFF3DEBA8);
  }

  String _scheduleText(BuildContext context, Reminder r) {
    final t = _parse(r.time);
    final each = r.times == 1 ? 'once' : '${r.times}×';
    final gap = r.times == 1 ? '' : ' every ${r.intervalDays}d';
    return '$each$gap at ${t.format(context)}';
  }

  TimeOfDay _parse(String s) {
    final p = s.split(':');
    return TimeOfDay(
        hour: int.tryParse(p.first) ?? 9,
        minute: p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0);
  }

  void _confirmDelete(BuildContext context, AppState app, Reminder r) {
    final colors = context.read<ThemeController>().colors;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('Remove reminder?',
            style: sans(size: 16, weight: FontWeight.w700, color: colors.text)),
        content: Text('Its scheduled notifications will be cancelled.',
            style: sans(size: 13.5, color: colors.sub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: sans(size: 14, color: colors.sub)),
          ),
          TextButton(
            onPressed: () {
              app.deleteReminder(r);
              Navigator.of(ctx).pop();
            },
            child: Text('Remove',
                style: sans(
                    size: 14, weight: FontWeight.w700, color: _due)),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Add / edit reminder
// ════════════════════════════════════════════════════════════════════════
class _ReminderEditorSheet extends StatefulWidget {
  const _ReminderEditorSheet({this.edit});
  final Reminder? edit;

  @override
  State<_ReminderEditorSheet> createState() => _ReminderEditorSheetState();
}

class _ReminderEditorSheetState extends State<_ReminderEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late DateTime _due;
  late int _times;
  late int _interval;
  late TimeOfDay _time;
  bool _saving = false;

  static const _intervals = [1, 2, 3, 7, 14, 30];

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _title = TextEditingController(text: e?.title ?? '');
    _amount =
        TextEditingController(text: (e != null && e.amount > 0) ? _trim(e.amount) : '');
    _due = e?.dueDateTime ?? DateTime.now().add(const Duration(days: 7));
    _times = e?.times ?? 3;
    _interval = e?.intervalDays ?? 1;
    _time = e != null
        ? TimeOfDay(hour: _h(e.time), minute: _m(e.time))
        : const TimeOfDay(hour: 9, minute: 0);
  }

  int _h(String s) => int.tryParse(s.split(':').first) ?? 9;
  int _m(String s) {
    final p = s.split(':');
    return p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
  }

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save(AppState app) async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add a reason')));
      return;
    }
    setState(() => _saving = true);
    final r = Reminder(
      id: widget.edit?.id ?? '',
      title: _title.text.trim(),
      amount: double.tryParse(_amount.text.trim()) ?? 0,
      dueDate: dateKeyOf(_due),
      times: _times,
      intervalDays: _interval,
      time:
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
      active: widget.edit?.active ?? true,
    );
    try {
      if (widget.edit != null) {
        await app.updateReminder(r);
      } else {
        await app.addReminder(r);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save — check connection')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.read<ThemeController>().colors;
    final app = context.read<AppState>();

    return SheetScaffold(
      title: widget.edit != null ? 'Edit Reminder' : 'Add Reminder',
      colors: colors,
      children: [
        AppTextField(
          colors: colors,
          controller: _title,
          label: 'Reason',
          hint: 'e.g. Credit card minimum payment',
        ),
        const SizedBox(height: 14),
        AppTextField(
          colors: colors,
          controller: _amount,
          label: 'Amount (optional)',
          hint: 'e.g. 5000',
          prefix: 'Rs',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 14),
        FieldLabel('Due date', colors: colors),
        _pickerField(colors, fmtDate(dateKeyOf(_due)), Icons.calendar_today,
            _pickDate),
        const SizedBox(height: 14),
        FieldLabel('Remind me at', colors: colors),
        _pickerField(colors, _time.format(context), Icons.schedule, _pickTime),
        const SizedBox(height: 16),
        FieldLabel('How many times', colors: colors),
        _stepper(colors),
        if (_times > 1) ...[
          const SizedBox(height: 16),
          FieldLabel('Every', colors: colors),
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            children: [
              for (final d in _intervals)
                GestureDetector(
                  onTap: () => setState(() => _interval = d),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: _interval == d
                          ? const Color(0xFF3DEBA8).withValues(alpha: 0.13)
                          : colors.inputBg,
                      border: Border.all(
                          color: _interval == d
                              ? const Color(0xFF3DEBA8)
                              : colors.inputBorder),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(d == 1 ? '1 day' : '$d days',
                        style: sans(
                            size: 13,
                            weight: FontWeight.w600,
                            color: _interval == d
                                ? const Color(0xFF3DEBA8)
                                : colors.sub)),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _summaryHint(colors),
        const SizedBox(height: 16),
        PrimaryButton(
          label: widget.edit != null ? 'Save' : 'Add Reminder',
          busy: _saving,
          onPressed: () => _save(app),
        ),
      ],
    );
  }

  Widget _pickerField(
      Palette colors, String value, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: colors.inputBg,
          border: Border.all(color: colors.inputBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: colors.sub),
            const SizedBox(width: 10),
            Text(value, style: sans(size: 14, color: colors.text)),
          ],
        ),
      ),
    );
  }

  Widget _stepper(Palette colors) {
    return Row(
      children: [
        _stepBtn(colors, Icons.remove,
            () => setState(() => _times = (_times - 1).clamp(1, 10))),
        Expanded(
          child: Center(
            child: Text('$_times',
                style: mono(
                    size: 18, weight: FontWeight.w700, color: colors.text)),
          ),
        ),
        _stepBtn(colors, Icons.add,
            () => setState(() => _times = (_times + 1).clamp(1, 10))),
      ],
    );
  }

  Widget _stepBtn(Palette colors, IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.inputBg,
          border: Border.all(color: colors.inputBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: colors.sub),
      ),
    );
  }

  Widget _summaryHint(Palette colors) {
    final first = _firstReminderText();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF3DEBA8).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFF3DEBA8)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(first,
                style: sans(size: 12.5, color: colors.sub)),
          ),
        ],
      ),
    );
  }

  String _firstReminderText() {
    if (_times == 1) {
      return 'You will be reminded once on ${fmtDate(dateKeyOf(_due))}.';
    }
    final firstDay =
        _due.subtract(Duration(days: (_times - 1) * _interval));
    return 'First nudge on ${fmtDate(dateKeyOf(firstDay))}, then every '
        '$_interval day(s) up to the due date — $_times in total.';
  }
}

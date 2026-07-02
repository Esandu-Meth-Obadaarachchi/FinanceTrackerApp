import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../services/notification_service.dart';
import '../services/sms_service.dart';
import '../state/app_state.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import 'reminders_screen.dart';

/// Opens the settings screen. [ThemeController] lives above MaterialApp so it
/// is reachable on the pushed route; [AppState] is re-provided because the
/// reminders + SMS controls below need it.
void openSettings(BuildContext context) {
  final app = context.read<AppState>();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const SettingsScreen(),
      ),
    ),
  );
}

/// Local app preferences: display options, appearance and version.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final colors = theme.colors;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: colors.text),
        title: Text('Settings',
            style: sans(size: 18, weight: FontWeight.w800, color: colors.text)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _sectionLabel(colors, 'DISPLAY'),
          AppCard(
            colors: colors,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: _toggleRow(
              colors: colors,
              icon: Icons.tag,
              title: 'Exact values',
              subtitle:
                  'Show full amounts to 2 decimals (e.g. ${_sample(true)}) '
                  'instead of rounding (${_sample(false)}).',
              value: theme.exactValues,
              onChanged: theme.setExactValues,
            ),
          ),
          const SizedBox(height: 18),
          _sectionLabel(colors, 'APPEARANCE'),
          AppCard(
            colors: colors,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: _toggleRow(
              colors: colors,
              icon: theme.isDark ? Icons.dark_mode : Icons.light_mode,
              title: 'Dark mode',
              subtitle: 'Use the dark colour theme.',
              value: theme.isDark,
              onChanged: (_) => theme.toggle(),
            ),
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 18),
            _sectionLabel(colors, 'DAILY REMINDERS'),
            _DailyRemindersCard(colors: colors),
          ],
          const SizedBox(height: 18),
          _sectionLabel(colors, 'PAYMENT REMINDERS'),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => openReminders(context),
            child: AppCard(
              colors: colors,
              child: Row(
                children: [
                  Icon(Icons.notifications_active_outlined,
                      size: 20, color: colors.sub),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Due payment reminders',
                            style: sans(
                                size: 14.5,
                                weight: FontWeight.w600,
                                color: colors.text)),
                        const SizedBox(height: 2),
                        Text('Bills, card payments, rent — set custom nudges.',
                            style: sans(size: 12, color: colors.sub)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: colors.sub),
                ],
              ),
            ),
          ),
          if (SmsService.instance.isSupported) ...[
            const SizedBox(height: 18),
            _sectionLabel(colors, 'BANK SMS'),
            _SmsImportCard(colors: colors),
          ],
          const SizedBox(height: 18),
          _sectionLabel(colors, 'ABOUT'),
          AppCard(
            colors: colors,
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: colors.sub),
                const SizedBox(width: 12),
                Text('Version',
                    style: sans(
                        size: 14,
                        weight: FontWeight.w600,
                        color: colors.text)),
                const Spacer(),
                Text(kAppVersion,
                    style: mono(
                        size: 14, weight: FontWeight.w700, color: colors.sub)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _sectionLabel(colors, 'DANGER ZONE'),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _confirmReset(context),
            child: AppCard(
              colors: colors,
              child: Row(
                children: [
                  const Icon(Icons.delete_forever_outlined,
                      size: 20, color: Color(0xFFFF5C7A)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Reset all data',
                            style: sans(
                                size: 14.5,
                                weight: FontWeight.w600,
                                color: const Color(0xFFFF5C7A))),
                        const SizedBox(height: 2),
                        Text(
                            'Delete every account, transaction, loan, budget '
                            'and reminder. Cannot be undone.',
                            style: sans(size: 12, color: colors.sub)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Confirms then wipes all of the signed-in user's data.
  Future<void> _confirmReset(BuildContext context) async {
    final colors = context.read<ThemeController>().colors;
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('Reset all data?',
            style: sans(size: 17, weight: FontWeight.w700, color: colors.text)),
        content: Text(
            'This permanently deletes every account, transaction, loan, '
            'recurring rule, budget and reminder. You will start completely '
            'fresh. This cannot be undone.',
            style: sans(size: 13.5, color: colors.sub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: sans(size: 14, color: colors.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete everything',
                style: sans(
                    size: 14,
                    weight: FontWeight.w700,
                    color: const Color(0xFFFF5C7A))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await app.resetAllData();
      messenger.showSnackBar(
          const SnackBar(content: Text('All data cleared. Starting fresh.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not reset — check your connection')));
    }
  }

  /// A representative figure so the user sees exactly what each mode looks like.
  String _sample(bool exact) {
    final previous = gExactValues;
    gExactValues = exact;
    final out = 'Rs ${fmt(1234.5)}';
    gExactValues = previous;
    return out;
  }

  Widget _sectionLabel(Palette colors, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 0, 8),
        child: Text(text,
            style: sans(
                size: 12,
                weight: FontWeight.w700,
                color: colors.sub,
                letterSpacing: 0.6)),
      );

  Widget _toggleRow({
    required Palette colors,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.sub),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: sans(
                        size: 14.5,
                        weight: FontWeight.w600,
                        color: colors.text)),
                const SizedBox(height: 2),
                Text(subtitle, style: sans(size: 12, color: colors.sub)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            activeColor: const Color(0xFF3DEBA8),
            activeTrackColor: const Color(0xFF3DEBA8).withValues(alpha: 0.5),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Morning + night "log your transactions" reminders. Loads saved times,
/// persists + reschedules on every change. Android/iOS only (hidden on web).
class _DailyRemindersCard extends StatefulWidget {
  const _DailyRemindersCard({required this.colors});
  final Palette colors;

  @override
  State<_DailyRemindersCard> createState() => _DailyRemindersCardState();
}

class _DailyRemindersCardState extends State<_DailyRemindersCard> {
  DailyReminderPrefs? _prefs;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.loadDailyPrefs().then((p) {
      if (mounted) setState(() => _prefs = p);
    });
  }

  Future<void> _update(DailyReminderPrefs next) async {
    setState(() => _prefs = next);
    await NotificationService.instance.requestPermissions();
    await NotificationService.instance.saveDailyPrefs(next);
  }

  Future<void> _pickTime(bool morning) async {
    final p = _prefs!;
    final picked = await showTimePicker(
      context: context,
      initialTime: morning ? p.morningTime : p.nightTime,
    );
    if (picked == null) return;
    _update(morning
        ? p.copyWith(morningTime: picked)
        : p.copyWith(nightTime: picked));
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final p = _prefs;
    if (p == null) {
      return AppCard(
        colors: colors,
        child: Text('Loading…', style: sans(size: 13, color: colors.sub)),
      );
    }
    return AppCard(
      colors: colors,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          _reminderRow(
            colors,
            Icons.wb_sunny_outlined,
            'Morning nudge',
            'Start the day by logging anything outstanding.',
            p.morningOn,
            p.morningTime,
            (v) => _update(p.copyWith(morningOn: v)),
            () => _pickTime(true),
          ),
          ThinDivider(colors: colors, indent: 8),
          _reminderRow(
            colors,
            Icons.nightlight_outlined,
            'Night nudge',
            "Record today's spending before bed.",
            p.nightOn,
            p.nightTime,
            (v) => _update(p.copyWith(nightOn: v)),
            () => _pickTime(false),
          ),
        ],
      ),
    );
  }

  Widget _reminderRow(
    Palette colors,
    IconData icon,
    String title,
    String subtitle,
    bool value,
    TimeOfDay time,
    ValueChanged<bool> onToggle,
    VoidCallback onPickTime,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.sub),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: sans(
                        size: 14.5,
                        weight: FontWeight.w600,
                        color: colors.text)),
                const SizedBox(height: 2),
                Text(subtitle, style: sans(size: 12, color: colors.sub)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Opacity(
            opacity: value ? 1 : 0.4,
            child: GestureDetector(
              onTap: value ? onPickTime : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.inputBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(time.format(context),
                    style: mono(
                        size: 13,
                        weight: FontWeight.w700,
                        color: colors.text)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Switch(
            value: value,
            activeColor: const Color(0xFF3DEBA8),
            activeTrackColor: const Color(0xFF3DEBA8).withValues(alpha: 0.5),
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}

/// Opt-in toggle for auto-importing bank debit/credit SMS (Android only).
class _SmsImportCard extends StatefulWidget {
  const _SmsImportCard({required this.colors});
  final Palette colors;

  @override
  State<_SmsImportCard> createState() => _SmsImportCardState();
}

class _SmsImportCardState extends State<_SmsImportCard> {
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SmsService.instance.isEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  Future<void> _toggle(bool v) async {
    setState(() => _busy = true);
    final app = context.read<AppState>();
    final effective = await SmsService.instance.setEnabled(v, app);
    if (!mounted) return;
    setState(() {
      _enabled = effective;
      _busy = false;
    });
    if (v && !effective) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('SMS permission denied — auto-import stays off')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return AppCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sms_outlined, size: 20, color: colors.sub),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Auto-import bank SMS',
                    style: sans(
                        size: 14.5,
                        weight: FontWeight.w600,
                        color: colors.text)),
              ),
              const SizedBox(width: 8),
              if (_busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: Color(0xFF3DEBA8)),
                )
              else
                Switch(
                  value: _enabled,
                  activeColor: const Color(0xFF3DEBA8),
                  activeTrackColor:
                      const Color(0xFF3DEBA8).withValues(alpha: 0.5),
                  onChanged: _toggle,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Reads incoming bank messages and posts matching debit/credit '
            'texts to the account whose card/account tail they mention. Set '
            'those tails on each account (tap an account to edit). Messages '
            'that don\'t clearly match are ignored.',
            style: sans(size: 12, color: colors.sub),
          ),
        ],
      ),
    );
  }
}

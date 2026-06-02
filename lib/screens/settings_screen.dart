import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';

/// Opens the settings screen. [ThemeController] lives above MaterialApp so it
/// is reachable on the pushed route without re-providing.
void openSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const SettingsScreen()),
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
        ],
      ),
    );
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

import 'package:flutter/material.dart';

/// Brand colours that stay constant across light/dark themes.
class Brand {
  static const Color accent = Color(0xFF3DEBA8); // primary green
  static const Color income = Color(0xFF3DEBA8);
  static const Color expense = Color(0xFFFF5C7A);
  static const Color transfer = Color(0xFF60A5FA);
  static const Color warning = Color(0xFFFFB547); // pending
  static const Color repaid = Color(0xFF60A5FA);
  static const Color partial = Color(0xFFA78BFA);

  /// Outer "device" backdrop, behind the 480px app frame.
  static const Color backdrop = Color(0xFF06080F);

  static const LinearGradient hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A2F4A), Color(0xFF0D1F35)],
  );

  static const LinearGradient addButton = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3DEBA8), Color(0xFF60A5FA)],
  );
}

/// Theme-dependent surface colours, mirroring the standalone HTML design.
class Palette {
  final bool isDark;

  const Palette._(this.isDark);

  factory Palette.of(bool isDark) => Palette._(isDark);

  Color get bg => isDark ? const Color(0xFF0B0D14) : const Color(0xFFF8FAFF);
  Color get card => isDark ? const Color(0xFF131825) : const Color(0xFFFFFFFF);
  Color get border => isDark ? const Color(0xFF1E2535) : const Color(0xFFE8EDF5);
  Color get elevated => isDark ? const Color(0xFF1A2030) : const Color(0xFFF5F8FF);
  Color get text => isDark ? const Color(0xFFECF0FF) : const Color(0xFF1A2030);
  Color get sub => isDark ? const Color(0xFF7A85A3) : const Color(0xFF9BA8C0);
  Color get muted => isDark ? const Color(0xFF4A5270) : const Color(0xFFB0BAD0);
  Color get inputBg => isDark ? const Color(0xFF1A2030) : const Color(0xFFF0F4FA);
  Color get inputBorder => isDark ? const Color(0xFF1E2535) : const Color(0xFFDDE3F0);
}

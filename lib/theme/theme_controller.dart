import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/formatters.dart';
import 'palette.dart';

/// Holds local UI preferences (theme + number display) and persists them.
class ThemeController extends ChangeNotifier {
  static const _key = 'ft_theme';
  static const _exactKey = 'ft_exact_values';
  bool _isDark = true;
  bool _exactValues = false;

  bool get isDark => _isDark;
  Palette get colors => Palette.of(_isDark);

  /// When true, amounts are shown in full (2 dp) instead of rounded/compact.
  bool get exactValues => _exactValues;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved != null) _isDark = saved == 'dark';
      _exactValues = prefs.getBool(_exactKey) ?? false;
    } catch (_) {
      // Keep defaults on any failure.
    }
    gExactValues = _exactValues;
    notifyListeners();
  }

  Future<void> toggle() async {
    _isDark = !_isDark;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _isDark ? 'dark' : 'light');
    } catch (_) {}
  }

  Future<void> setExactValues(bool value) async {
    _exactValues = value;
    gExactValues = value; // keep fmt() in sync
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_exactKey, value);
    } catch (_) {}
  }
}

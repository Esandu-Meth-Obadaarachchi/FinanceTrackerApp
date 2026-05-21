import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'palette.dart';

/// Holds the light/dark choice and persists it locally.
class ThemeController extends ChangeNotifier {
  static const _key = 'ft_theme';
  bool _isDark = true;

  bool get isDark => _isDark;
  Palette get colors => Palette.of(_isDark);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved != null) _isDark = saved == 'dark';
    } catch (_) {
      // Keep default on any failure.
    }
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
}

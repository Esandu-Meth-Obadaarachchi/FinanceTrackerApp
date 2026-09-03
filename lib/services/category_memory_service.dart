import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/category_memory.dart';

/// Persists [CategoryMemory] to SharedPreferences.
///
/// Deliberately local rather than in Firestore: it is a per-device
/// convenience cache, it is written on every saved transaction, and losing
/// it costs nothing beyond a few AI calls while it fills up again.
class CategoryMemoryService {
  CategoryMemoryService._();
  static final instance = CategoryMemoryService._();

  static const _key = 'category_memory_v1';

  CategoryMemory _memory = CategoryMemory();
  bool _loaded = false;

  CategoryMemory get memory => _memory;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        _memory = CategoryMemory.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Corrupt or unreadable memory is not worth failing a launch over;
      // it simply starts learning again.
      _memory = CategoryMemory();
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_memory.toJson()));
    } catch (_) {/* best effort */}
  }

  /// Record what a piece of text turned out to be. Call this whenever the
  /// user saves a transaction, whoever suggested the category.
  Future<void> learn(String text, String category, {String? merchant}) async {
    if (text.trim().isEmpty && (merchant == null || merchant.isEmpty)) return;
    await load();
    _memory.learn(text, category, merchant: merchant);
    await _save();
  }

  Future<void> unlearn(String text, String category) async {
    await load();
    _memory.unlearn(text, category);
    await _save();
  }

  /// The local answer, or null when the memory has nothing confident to say.
  CategorySuggestion? suggest(String text, {String? merchant}) =>
      _memory.suggest(text, merchant: merchant);

  Future<void> clear() async {
    _memory = CategoryMemory();
    await _save();
  }
}

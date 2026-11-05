import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/app_transaction.dart';
import '../models/sms_suggestion.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import 'ai_service.dart';
import 'category_memory_service.dart';
import 'sms_parser.dart';

/// Holds bank-SMS suggestions until the user approves or dismisses them.
///
/// Kept in SharedPreferences rather than Firestore: a queue of unreviewed
/// guesses is per-device working state, not user data. Approving one writes
/// a real transaction, and that is the only thing worth syncing.
class SmsInbox extends ChangeNotifier {
  SmsInbox._();
  static final SmsInbox instance = SmsInbox._();

  static const _key = 'sms_inbox_v1';
  static const _maxKept = 100;

  final List<SmsSuggestion> _items = [];
  bool _loaded = false;

  List<SmsSuggestion> get pending =>
      [..._items.where((s) => s.isPending)]
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

  int get pendingCount => _items.where((s) => s.isPending).length;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as List;
      _items
        ..clear()
        ..addAll(decoded
            .map((e) => SmsSuggestion.fromJson(e as Map<String, dynamic>)));
      notifyListeners();
    } catch (_) {
      _items.clear();
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Approved and dismissed entries are kept only so the same message is
      // not re-queued; trimming the oldest keeps the store bounded.
      final keep = _items.length > _maxKept
          ? _items.sublist(_items.length - _maxKept)
          : _items;
      await prefs.setString(
          _key, jsonEncode([for (final s in keep) s.toJson()]));
    } catch (_) {/* best effort */}
  }

  bool _alreadyQueued(String id) => _items.any((s) => s.id == id);

  /// Turn one message into a suggestion and queue it.
  ///
  /// Layered cheapest-first: regex reads the amount and direction, local
  /// memory answers the category when the merchant is familiar, and the
  /// model is asked only when neither could.
  Future<void> ingest(
    String body,
    DateTime when,
    AppState app, {
    String sender = '',
  }) async {
    await load();
    final id = SmsSuggestion.signatureOf(body);
    if (_alreadyQueued(id)) return;

    final parsed = SmsParser.parse(body);

    // Layer 1: local memory, when regex found a merchant we have seen.
    if (parsed != null && parsed.merchant.isNotEmpty) {
      final remembered = CategoryMemoryService.instance
          .suggest(parsed.merchant, merchant: parsed.merchant);
      if (remembered != null && remembered.exact) {
        await _queue(SmsSuggestion(
          id: id,
          body: body,
          sender: sender,
          receivedAt: when,
          amount: parsed.amount,
          type: parsed.isDebit ? 'expense' : 'income',
          category: remembered.category,
          note: parsed.merchant,
          merchant: parsed.merchant,
          cardTail: parsed.tail,
          accountId: _accountFor(parsed.tail, app),
          confidence: 1,
          source: SuggestionSource.memory,
        ));
        return;
      }
    }

    // Layer 2: the model, for anything not already known.
    if (AiService.instance.enabled) {
      try {
        final entry = await AiService.instance.parseSms(body, sender: sender);
        if (!entry.understood) {
          // The model judged this not a transaction (an OTP, a promotion).
          // Recording it as dismissed stops it being reconsidered.
          await _queue(SmsSuggestion(
            id: id,
            body: body,
            sender: sender,
            receivedAt: when,
            amount: 0,
            type: 'expense',
            status: SuggestionStatus.dismissed,
          ));
          return;
        }
        final tail = entry.cardTail.isNotEmpty ? entry.cardTail : parsed?.tail ?? '';
        await _queue(SmsSuggestion(
          id: id,
          body: body,
          sender: sender,
          receivedAt: when,
          amount: entry.amount > 0 ? entry.amount : (parsed?.amount ?? 0),
          type: entry.type,
          category: entry.category,
          note: entry.note,
          merchant: entry.merchant,
          cardTail: tail,
          accountId: _accountFor(tail, app),
          confidence: entry.confidence,
          source: SuggestionSource.ai,
        ));
        return;
      } catch (_) {
        // Backend down or switched off: fall through to rules rather than
        // losing the message.
      }
    }

    // Layer 3: regex plus keyword guessing.
    if (parsed == null) return;
    await _queue(SmsSuggestion(
      id: id,
      body: body,
      sender: sender,
      receivedAt: when,
      amount: parsed.amount,
      type: parsed.isDebit ? 'expense' : 'income',
      category: SmsParser.guessCategory(parsed.merchant, parsed.isDebit),
      note: parsed.merchant.isNotEmpty ? parsed.merchant : 'Bank SMS',
      merchant: parsed.merchant,
      cardTail: parsed.tail,
      accountId: _accountFor(parsed.tail, app),
      confidence: 0.5,
      source: SuggestionSource.rules,
    ));
  }

  /// The account whose `smsIds` claim this tail, if exactly one does.
  static String _accountFor(String tail, AppState app) {
    if (tail.isEmpty) return '';
    final matches =
        app.accounts.where((Account a) => a.smsIds.contains(tail)).toList();
    return matches.length == 1 ? matches.first.id : '';
  }

  Future<void> _queue(SmsSuggestion suggestion) async {
    _items.add(suggestion);
    await _save();
    notifyListeners();
  }

  /// Write the transaction and remember the category for next time.
  Future<void> approve(SmsSuggestion suggestion, AppState app) async {
    if (suggestion.accountId.isEmpty || suggestion.amount <= 0) return;

    await app.addTransaction(AppTransaction(
      id: '',
      date: dateKeyOf(suggestion.receivedAt),
      type: suggestion.type,
      accountId: suggestion.accountId,
      category: suggestion.category,
      note: suggestion.note.isNotEmpty ? suggestion.note : 'Bank SMS',
      amount: suggestion.amount,
      status: 'received',
    ));

    // The confirmed answer is what teaches the memory, whoever proposed it.
    await CategoryMemoryService.instance.learn(
      suggestion.note,
      suggestion.category,
      merchant: suggestion.merchant.isNotEmpty ? suggestion.merchant : null,
    );

    _replace(suggestion.copyWith(status: SuggestionStatus.approved));
  }

  Future<void> dismiss(SmsSuggestion suggestion) async {
    _replace(suggestion.copyWith(status: SuggestionStatus.dismissed));
  }

  /// Persist an edit made on the review card.
  Future<void> update(SmsSuggestion suggestion) async {
    _replace(suggestion);
  }

  void _replace(SmsSuggestion updated) {
    final index = _items.indexWhere((s) => s.id == updated.id);
    if (index >= 0) {
      _items[index] = updated;
    } else {
      _items.add(updated);
    }
    _save();
    notifyListeners();
  }

  Future<void> clearReviewed() async {
    _items.removeWhere((s) => !s.isPending);
    await _save();
    notifyListeners();
  }
}

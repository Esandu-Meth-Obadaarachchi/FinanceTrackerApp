import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_transaction.dart';
import '../models/category_memory.dart';
import '../state/app_state.dart';
import 'category_memory_service.dart';

/// Talks to the FastAPI backend in `backend/`.
///
/// Every call is layered cheapest-first: the local [CategoryMemory] answers
/// what it already knows instantly and offline, and the model is asked only
/// about text nothing local recognises. That keeps the common case free and
/// fast, and it keeps working when the backend is down.
class AiService {
  AiService._();
  static final instance = AiService._();

  static const _urlKey = 'ai_backend_url';
  static const _appKeyKey = 'ai_app_key';
  static const _enabledKey = 'ai_enabled';

  /// Default for local development. Settings overrides it once hosted.
  static const defaultBaseUrl = 'http://127.0.0.1:8099';

  String _baseUrl = defaultBaseUrl;
  String _appKey = '';
  bool _enabled = false;
  bool _loaded = false;

  String get baseUrl => _baseUrl;
  String get appKey => _appKey;
  bool get enabled => _enabled && _baseUrl.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _baseUrl = prefs.getString(_urlKey) ?? defaultBaseUrl;
      _appKey = prefs.getString(_appKeyKey) ?? '';
      _enabled = prefs.getBool(_enabledKey) ?? false;
    } catch (_) {/* defaults are fine */}
  }

  Future<void> configure({String? baseUrl, String? appKey, bool? enabled}) async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    if (baseUrl != null) {
      _baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      await prefs.setString(_urlKey, _baseUrl);
    }
    if (appKey != null) {
      _appKey = appKey.trim();
      await prefs.setString(_appKeyKey, _appKey);
    }
    if (enabled != null) {
      _enabled = enabled;
      await prefs.setBool(_enabledKey, enabled);
    }
  }

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (_appKey.isNotEmpty) 'X-App-Key': _appKey,
      };

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final resp = await http
        .post(Uri.parse('$_baseUrl$path'), headers: _headers,
            body: jsonEncode(body))
        .timeout(timeout);
    if (resp.statusCode >= 400) {
      throw AiFailure('Backend returned ${resp.statusCode}: ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// True when the backend answers and has at least one provider configured.
  Future<bool> ping() async {
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return false;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final providers = (body['providers'] as Map?) ?? {};
      return providers.values.any((v) => v == true);
    } catch (_) {
      return false;
    }
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }

  /// One line of text to a draft transaction the user confirms.
  Future<ParsedEntry> parseText(String text, {List<String> accounts = const []}) async {
    if (!enabled) throw AiFailure('AI entry is switched off in Settings.');
    final json = await _post('/parse/text', {
      'text': text,
      'today': _todayKey(),
      'accounts': accounts,
    });
    return ParsedEntry.fromJson(json);
  }

  /// A bank SMS to a draft transaction for the review inbox.
  ///
  /// The local memory is consulted first: a merchant seen before needs no
  /// model call at all.
  Future<ParsedEntry> parseSms(
    String body, {
    String sender = '',
    String? merchantHint,
  }) async {
    final local = merchantHint == null
        ? null
        : CategoryMemoryService.instance.suggest('', merchant: merchantHint);
    if (local != null && local.exact) {
      return ParsedEntry(
        understood: true,
        category: local.category,
        note: merchantHint!,
        merchant: merchantHint,
        confidence: 1,
        source: 'memory',
        amount: 0,
      );
    }

    if (!enabled) throw AiFailure('AI import is switched off in Settings.');
    final json = await _post('/parse/sms', {
      'body': body,
      'sender': sender,
      'today': _todayKey(),
    });
    return ParsedEntry.fromJson(json);
  }

  /// Ask a question about your own money.
  ///
  /// The snapshot travels with the question and the backend keeps none of
  /// it, so nothing about the user's finances is stored off-device.
  Future<AgentAnswer> ask(
    String question,
    AppState app, {
    List<({String role, String content})> history = const [],
  }) async {
    if (!enabled) throw AiFailure('The assistant is switched off in Settings.');
    final json = await _post(
      '/agent/ask',
      {
        'question': question,
        'today': _todayKey(),
        'snapshot': buildSnapshot(app),
        'history': [
          for (final m in history) {'role': m.role, 'content': m.content},
        ],
      },
      timeout: const Duration(seconds: 120),
    );
    return AgentAnswer(
      answer: json['answer'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      toolCalls: [
        for (final c in (json['tool_calls'] as List? ?? []))
          (c as Map)['tool'] as String? ?? '',
      ],
    );
  }

  /// The financial picture the agent reasons over.
  ///
  /// Balances and loan outstandings are computed here rather than sent raw,
  /// so the model never has to re-derive money rules the app already owns.
  static Map<String, dynamic> buildSnapshot(AppState app) => {
        'accounts': [
          for (final a in app.accounts)
            {
              'id': a.id,
              'name': a.name,
              'type': a.type,
              'balance': app.balanceOf(a),
            },
        ],
        'transactions': [
          for (final t in app.transactions)
            {
              'date': t.date,
              'type': t.type,
              'category': t.category,
              'note': t.note,
              'amount': t.amount,
              'status': t.status,
              'accountId': t.accountId,
            },
        ],
        'loans': [
          for (final l in app.loans)
            {
              'who': l.who,
              'loanType': l.loanType,
              'amount': l.amount,
              'outstanding': app.outstandingOf(l),
              'reason': l.reason,
              'date': l.date,
            },
        ],
        'budget': app.budget.isEmpty
            ? null
            : {
                'month': app.budget.month,
                'plannedIncome': app.budget.plannedIncome,
                'allocations': app.budget.allocations,
              },
      };
}

class AiFailure implements Exception {
  AiFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A draft transaction from the model, always shown before it is saved.
@immutable
class ParsedEntry {
  const ParsedEntry({
    required this.understood,
    required this.amount,
    this.type = 'expense',
    this.category = '',
    this.note = '',
    this.date = '',
    this.accountHint = '',
    this.status = 'received',
    this.confidence = 0,
    this.merchant = '',
    this.cardTail = '',
    this.source = '',
  });

  final bool understood;
  final String type;
  final double amount;
  final String category;
  final String note;
  final String date;
  final String accountHint;
  final String status;
  final double confidence;
  final String merchant;
  final String cardTail;

  /// Which layer answered: "memory", "gemini" or "anthropic".
  final String source;

  /// Below this the model was guessing, so the sheet opens for editing
  /// instead of offering a one-tap approve.
  bool get isConfident => confidence >= 0.6;

  factory ParsedEntry.fromJson(Map<String, dynamic> json) => ParsedEntry(
        understood: json['understood'] == true,
        type: json['type'] as String? ?? 'expense',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        category: json['category'] as String? ?? '',
        note: json['note'] as String? ?? '',
        date: json['date'] as String? ?? '',
        accountHint: json['account_hint'] as String? ?? '',
        status: json['status'] as String? ?? 'received',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        merchant: json['merchant'] as String? ?? '',
        cardTail: json['card_tail'] as String? ?? '',
        source: json['provider'] as String? ?? '',
      );

  AppTransaction toTransaction({required String accountId}) => AppTransaction(
        id: '',
        date: date,
        type: type,
        accountId: accountId,
        category: category,
        note: note,
        amount: amount,
        status: status,
      );
}

class AgentAnswer {
  const AgentAnswer({
    required this.answer,
    required this.provider,
    this.toolCalls = const [],
  });

  final String answer;
  final String provider;
  final List<String> toolCalls;
}

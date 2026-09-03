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

  /// Ask about your money, or tell it to record something.
  ///
  /// The snapshot travels with the question and the backend keeps none of
  /// it, so nothing about the user's finances is stored off-device.
  ///
  /// [state] is echoed straight back from the previous reply. It carries the
  /// agent's unfinished intent across a clarification, which chat history
  /// alone cannot — without it the model has to re-infer from prose what it
  /// was halfway through doing.
  Future<AgentAnswer> ask(
    String question,
    AppState app, {
    List<({String role, String content})> history = const [],
    Map<String, dynamic> state = const {},
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
        'state': state,
      },
      timeout: const Duration(seconds: 120),
    );
    return AgentAnswer.fromJson(json);
  }

  /// Carry out a proposal the user approved.
  ///
  /// Everything goes through [AppState], which owns the money rules, so an
  /// AI-originated write behaves exactly like one typed by hand. There is no
  /// separate path it could take to bypass them.
  static Future<void> applyProposal(AgentProposal p, AppState app) async {
    switch (p.kind) {
      case 'add_transaction':
        await app.addTransaction(AppTransaction(
          id: '',
          date: p.fields['date'] as String? ?? _todayKey(),
          type: p.fields['type'] as String? ?? 'expense',
          accountId: p.fields['accountId'] as String? ?? '',
          category: p.fields['category'] as String? ?? '',
          note: p.fields['note'] as String? ?? '',
          amount: (p.fields['amount'] as num?)?.toDouble() ?? 0,
          status: p.fields['status'] as String? ?? 'received',
        ));
      case 'edit_transaction':
        final existing = app.transactions.firstWhere(
          (t) => t.id == p.targetId,
          orElse: () => throw AiFailure('That entry no longer exists.'),
        );
        await app.updateTransaction(AppTransaction(
          id: existing.id,
          date: p.fields['date'] as String? ?? existing.date,
          type: existing.type,
          accountId: p.fields['accountId'] as String? ?? existing.accountId,
          toAccountId: existing.toAccountId,
          category: p.fields['category'] as String? ?? existing.category,
          note: p.fields['note'] as String? ?? existing.note,
          amount: (p.fields['amount'] as num?)?.toDouble() ?? existing.amount,
          status: p.fields['status'] as String? ?? existing.status,
          recurringId: existing.recurringId,
          loanId: existing.loanId,
          parentId: existing.parentId,
        ));
      case 'delete_transaction':
        await app.deleteTransaction(p.targetId);
      default:
        throw AiFailure('Unknown action: ${p.kind}');
    }
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
              // Ids travel so the agent can propose edits and deletions
              // against a specific row rather than describing one.
              'id': t.id,
              'date': t.date,
              'type': t.type,
              'category': t.category,
              'note': t.note,
              'amount': t.amount,
              'status': t.status,
              'accountId': t.accountId,
              // Deleting one of these unwinds a derived rule elsewhere, so
              // the backend warns about it on the confirmation card.
              if (t.loanId != null) 'loanId': t.loanId,
              if (t.parentId != null) 'parentId': t.parentId,
              if (t.recurringId != null) 'recurringId': t.recurringId,
            },
        ],
        'loans': [
          for (final l in app.loans)
            {
              'id': l.id,
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

/// One turn from the agent: an answer, a question back, or a write to confirm.
class AgentAnswer {
  const AgentAnswer({
    required this.kind,
    required this.answer,
    required this.provider,
    this.toolCalls = const [],
    this.question,
    this.proposal,
    this.state = const {},
  });

  /// "answer", "question" or "proposal".
  final String kind;
  final String answer;
  final String provider;
  final List<String> toolCalls;

  final AgentQuestion? question;
  final AgentProposal? proposal;

  /// Opaque. The client stores it and sends it back untouched next turn.
  final Map<String, dynamic> state;

  bool get isQuestion => kind == 'question' && question != null;
  bool get isProposal => kind == 'proposal' && proposal != null;

  factory AgentAnswer.fromJson(Map<String, dynamic> json) {
    final q = json['question'] as Map<String, dynamic>?;
    final p = json['proposal'] as Map<String, dynamic>?;
    return AgentAnswer(
      kind: json['kind'] as String? ?? 'answer',
      answer: json['answer'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      toolCalls: [
        for (final c in (json['tool_calls'] as List? ?? []))
          (c as Map)['tool'] as String? ?? '',
      ],
      question: q == null ? null : AgentQuestion.fromJson(q),
      proposal: p == null ? null : AgentProposal.fromJson(p),
      state: (json['state'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

/// A clarification, with tappable answers.
///
/// Options are the whole point: asking is only acceptable when it costs one
/// tap rather than typing, so the agent is told never to ask without them.
class AgentQuestion {
  const AgentQuestion({required this.text, this.options = const [], this.field = ''});

  final String text;
  final List<String> options;
  final String field;

  factory AgentQuestion.fromJson(Map<String, dynamic> json) => AgentQuestion(
        text: json['text'] as String? ?? '',
        options: [for (final o in (json['options'] as List? ?? [])) o.toString()],
        field: json['field'] as String? ?? '',
      );
}

/// A write waiting on approval. Nothing has happened yet.
class AgentProposal {
  const AgentProposal({
    required this.id,
    required this.kind,
    this.targetId = '',
    this.fields = const {},
    this.before = const {},
    this.summary = '',
    this.changes = const [],
    this.warnings = const [],
    this.reason = '',
  });

  /// Unique per proposal, so a double tap cannot write twice.
  final String id;

  /// "add_transaction", "edit_transaction" or "delete_transaction".
  final String kind;

  /// Which record an edit or delete acts on.
  final String targetId;

  final Map<String, dynamic> fields;

  /// Current values, so the card shows what is being replaced or removed.
  final Map<String, dynamic> before;

  final String summary;
  final List<String> changes;
  final List<String> warnings;
  final String reason;

  bool get isDelete => kind == 'delete_transaction';
  bool get isEdit => kind == 'edit_transaction';

  String get actionLabel => switch (kind) {
        'delete_transaction' => 'Delete',
        'edit_transaction' => 'Save change',
        _ => 'Add',
      };

  factory AgentProposal.fromJson(Map<String, dynamic> json) => AgentProposal(
        id: json['id'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        targetId: json['target_id'] as String? ?? '',
        fields: (json['fields'] as Map?)?.cast<String, dynamic>() ?? const {},
        before: (json['before'] as Map?)?.cast<String, dynamic>() ?? const {},
        summary: json['summary'] as String? ?? '',
        changes: [for (final c in (json['changes'] as List? ?? [])) c.toString()],
        warnings: [for (final w in (json['warnings'] as List? ?? [])) w.toString()],
        reason: json['reason'] as String? ?? '',
      );
}

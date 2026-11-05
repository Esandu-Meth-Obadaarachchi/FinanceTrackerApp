/// A transaction the app believes a bank SMS describes, waiting to be
/// approved.
///
/// The old pipeline posted a transaction the moment regex matched and the
/// card tail mapped to exactly one account, and silently dropped everything
/// else. That guard was doing two jobs at once: keeping wrong data out, and
/// deciding what was worth showing. It did the first well and the second
/// badly — every message with an unrecognised merchant or an ambiguous tail
/// vanished, which is most of them.
///
/// Turning them into suggestions splits those jobs. Nothing is written
/// without a tap, so the bar for showing something drops to "probably
/// useful", and the day's spending becomes a few swipes instead of a form.
library;

enum SuggestionStatus { pending, approved, dismissed }

/// Where the category came from, in order of how much it should be trusted.
enum SuggestionSource {
  /// An exact merchant match from local memory. Seen before, no doubt.
  memory,

  /// The model read the message.
  ai,

  /// Regex plus keyword guessing. Cheap, and often only roughly right.
  rules,
}

class SmsSuggestion {
  const SmsSuggestion({
    required this.id,
    required this.body,
    required this.receivedAt,
    required this.amount,
    required this.type,
    this.sender = '',
    this.category = '',
    this.note = '',
    this.merchant = '',
    this.cardTail = '',
    this.accountId = '',
    this.confidence = 0,
    this.source = SuggestionSource.rules,
    this.status = SuggestionStatus.pending,
  });

  final String id;
  final String body;
  final String sender;
  final DateTime receivedAt;

  final double amount;
  final String type; // income | expense
  final String category;
  final String note;
  final String merchant;
  final String cardTail;

  /// Empty when the tail matched no account, or more than one.
  final String accountId;

  final double confidence;
  final SuggestionSource source;
  final SuggestionStatus status;

  bool get isPending => status == SuggestionStatus.pending;

  /// Ready to approve in one tap: the app knows the amount, the category and
  /// which account it came out of, and is not guessing about any of them.
  bool get isOneTap =>
      amount > 0 &&
      category.isNotEmpty &&
      accountId.isNotEmpty &&
      (source == SuggestionSource.memory || confidence >= 0.6);

  /// What the card should ask the user to resolve, or null when nothing is
  /// missing.
  String? get blocker {
    if (amount <= 0) return 'Amount not readable';
    if (accountId.isEmpty) return 'Pick an account';
    if (category.isEmpty) return 'Pick a category';
    if (confidence < 0.6 && source != SuggestionSource.memory) {
      return 'Check the category';
    }
    return null;
  }

  SmsSuggestion copyWith({
    String? category,
    String? note,
    String? accountId,
    double? amount,
    String? type,
    double? confidence,
    SuggestionSource? source,
    SuggestionStatus? status,
  }) =>
      SmsSuggestion(
        id: id,
        body: body,
        sender: sender,
        receivedAt: receivedAt,
        amount: amount ?? this.amount,
        type: type ?? this.type,
        category: category ?? this.category,
        note: note ?? this.note,
        merchant: merchant,
        cardTail: cardTail,
        accountId: accountId ?? this.accountId,
        confidence: confidence ?? this.confidence,
        source: source ?? this.source,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'body': body,
        'sender': sender,
        'receivedAt': receivedAt.millisecondsSinceEpoch,
        'amount': amount,
        'type': type,
        'category': category,
        'note': note,
        'merchant': merchant,
        'cardTail': cardTail,
        'accountId': accountId,
        'confidence': confidence,
        'source': source.name,
        'status': status.name,
      };

  factory SmsSuggestion.fromJson(Map<String, dynamic> json) => SmsSuggestion(
        id: json['id'] as String? ?? '',
        body: json['body'] as String? ?? '',
        sender: json['sender'] as String? ?? '',
        receivedAt: DateTime.fromMillisecondsSinceEpoch(
            (json['receivedAt'] as num?)?.toInt() ?? 0),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        type: json['type'] as String? ?? 'expense',
        category: json['category'] as String? ?? '',
        note: json['note'] as String? ?? '',
        merchant: json['merchant'] as String? ?? '',
        cardTail: json['cardTail'] as String? ?? '',
        accountId: json['accountId'] as String? ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        source: SuggestionSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => SuggestionSource.rules,
        ),
        status: SuggestionStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => SuggestionStatus.pending,
        ),
      );

  /// A stable id for one message, so the same SMS is never queued twice.
  ///
  /// Derived from the text rather than a timestamp: the live listener and
  /// the startup inbox scan both see the same message and must agree on it.
  static String signatureOf(String body) =>
      (body.trim().hashCode & 0x7fffffff).toString();
}

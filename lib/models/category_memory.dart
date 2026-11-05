/// Remembers which category a piece of text turned out to belong to.
///
/// The point is to stop asking the same question twice. The second time you
/// type "lunch", or the second time KEELLS SUPER shows up in a bank SMS, the
/// answer is already known — no model call, no network, no waiting.
///
/// It sits in front of the AI rather than beside it: a confident local answer
/// short-circuits the request entirely, which makes the common case instant
/// and free, and leaves the model for genuinely new text.
///
/// Pure Dart with no storage or Firestore, so the matching rules stay
/// testable ([test/category_memory_test.dart]).
library;

/// Words carrying no signal about which category something belongs to.
const _stopWords = {
  'a', 'an', 'and', 'at', 'for', 'from', 'in', 'my', 'of', 'on', 'or',
  'the', 'to', 'with', 'rs', 'lkr', 'paid', 'pay', 'bought', 'buy', 'got',
};

/// A learned association between text and a category.
class CategoryMemory {
  CategoryMemory({
    Map<String, Map<String, int>>? tokenCounts,
    Map<String, String>? merchants,
  })  : _tokenCounts = tokenCounts ?? {},
        _merchants = merchants ?? {};

  /// token -> category -> how many times they appeared together.
  final Map<String, Map<String, int>> _tokenCounts;

  /// Exact merchant string -> category. Bank SMS repeats merchants verbatim,
  /// so an exact hit here is worth more than any amount of token scoring.
  final Map<String, String> _merchants;

  bool get isEmpty => _tokenCounts.isEmpty && _merchants.isEmpty;
  int get learnedTokens => _tokenCounts.length;
  int get learnedMerchants => _merchants.length;

  /// Split text into meaningful lowercase words.
  ///
  /// Digits go: amounts, card tails and reference numbers differ every time
  /// and would only ever dilute the counts.
  static List<String> tokenise(String text) {
    final cleaned = text.toLowerCase().replaceAll(RegExp(r'[^a-z\s]'), ' ');
    return [
      for (final word in cleaned.split(RegExp(r'\s+')))
        if (word.length > 2 && !_stopWords.contains(word)) word,
    ];
  }

  static String normaliseMerchant(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').trim()
          .replaceAll(RegExp(r'\s+'), ' ');

  /// Record that [text] was filed under [category].
  void learn(String text, String category, {String? merchant}) {
    if (category.trim().isEmpty) return;

    if (merchant != null && merchant.trim().isNotEmpty) {
      _merchants[normaliseMerchant(merchant)] = category;
    }
    for (final token in tokenise(text)) {
      final byCategory = _tokenCounts.putIfAbsent(token, () => {});
      byCategory[category] = (byCategory[category] ?? 0) + 1;
    }
  }

  /// Forget one association, for when a suggestion was wrong.
  void unlearn(String text, String category) {
    for (final token in tokenise(text)) {
      final byCategory = _tokenCounts[token];
      if (byCategory == null) continue;
      final left = (byCategory[category] ?? 0) - 1;
      if (left > 0) {
        byCategory[category] = left;
      } else {
        byCategory.remove(category);
        if (byCategory.isEmpty) _tokenCounts.remove(token);
      }
    }
  }

  /// The best category for [text], or null when nothing is known.
  ///
  /// An exact merchant match wins outright. Otherwise every token votes with
  /// its observed counts, and the winner is returned only if it clears
  /// [minScore] and is genuinely ahead of the runner-up — a near-tie means
  /// the memory does not know, and guessing would be worse than asking.
  CategorySuggestion? suggest(
    String text, {
    String? merchant,
    int minScore = 2,
    double minLead = 1.5,
  }) {
    if (merchant != null) {
      final hit = _merchants[normaliseMerchant(merchant)];
      if (hit != null) {
        return CategorySuggestion(category: hit, score: 999, exact: true);
      }
    }

    final scores = <String, int>{};
    for (final token in tokenise(text)) {
      final byCategory = _tokenCounts[token];
      if (byCategory == null) continue;
      byCategory.forEach((category, count) {
        scores[category] = (scores[category] ?? 0) + count;
      });
    }
    if (scores.isEmpty) return null;

    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;
    if (best.value < minScore) return null;
    if (ranked.length > 1) {
      final runnerUp = ranked[1].value;
      if (runnerUp > 0 && best.value / runnerUp < minLead) return null;
    }
    return CategorySuggestion(category: best.key, score: best.value);
  }

  Map<String, dynamic> toJson() => {
        'tokens': _tokenCounts,
        'merchants': _merchants,
      };

  factory CategoryMemory.fromJson(Map<String, dynamic> json) {
    final rawTokens = (json['tokens'] as Map?) ?? {};
    final tokens = <String, Map<String, int>>{};
    rawTokens.forEach((token, byCategory) {
      if (byCategory is Map) {
        tokens[token as String] = {
          for (final e in byCategory.entries)
            e.key as String: (e.value as num).toInt(),
        };
      }
    });
    final rawMerchants = (json['merchants'] as Map?) ?? {};
    return CategoryMemory(
      tokenCounts: tokens,
      merchants: {
        for (final e in rawMerchants.entries)
          e.key as String: e.value as String,
      },
    );
  }
}

/// A category the memory believes in, and how strongly.
class CategorySuggestion {
  const CategorySuggestion({
    required this.category,
    required this.score,
    this.exact = false,
  });

  final String category;
  final int score;

  /// True when a merchant matched verbatim, which needs no confirmation.
  final bool exact;

  /// Confident enough to fill in without asking.
  bool get isStrong => exact || score >= 4;
}

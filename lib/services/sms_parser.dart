/// The result of parsing a bank SMS into a candidate transaction.
class ParsedSms {
  final double amount;
  final bool isDebit; // true => expense, false => income
  final String tail; // last digits identifying the account/card
  final String merchant; // cleaned merchant text, used as the note

  const ParsedSms({
    required this.amount,
    required this.isDebit,
    required this.tail,
    required this.merchant,
  });
}

/// Pure-Dart parser for Sri Lankan bank debit/credit SMS. Returns null unless a
/// message clearly contains an amount, a direction and an account/card tail —
/// the confidence guard that stops OTP and balance-only noise from posting.
class SmsParser {
  SmsParser._();

  static final _amount = RegExp(
      r'(?:LKR|Rs\.?)\s*([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false);

  // Tail patterns, tried in order; first match wins.
  static final _tailPatterns = <RegExp>[
    RegExp(r'A/?C\s*\*+\s*(\d{3,6})', caseSensitive: false),
    RegExp(r'card\s*(?:ending|no\.?|number)?\s*#?\s*\.*\s*(\d{3,6})',
        caseSensitive: false),
    RegExp(r'ending\s*#?\s*(\d{3,6})', caseSensitive: false),
    RegExp(r'\.{2,}\s*(\d{3,6})'),
    RegExp(r'\*{2,}\s*(\d{3,6})'),
  ];

  // Merchant patterns, tried in order.
  static final _merchantPatterns = <RegExp>[
    RegExp(r'Purchase at (.+?) for ', caseSensitive: false),
    RegExp(r'via POS at (.+?)(?:\s+\d{5,}|\s{2,}|$)', caseSensitive: false),
    RegExp(r'\bat (.+?)(?:\.\s*Avl|\s{2,}|\s+on\b|$)', caseSensitive: false),
    RegExp(r'\bfor (?:eCom\s+)?(.+?)(?:\s+T\d{4,}|\s{2,}|$)',
        caseSensitive: false),
  ];

  static ParsedSms? parse(String body) {
    if (body.isEmpty) return null;
    final lower = body.toLowerCase();

    // Direction — check debit signals first so a purchase on a "credit card"
    // isn't misread as income.
    bool? isDebit;
    if (lower.contains('debited') ||
        RegExp(r'\bdebit\b').hasMatch(lower) ||
        lower.contains('purchase') ||
        lower.contains('withdrawn') ||
        lower.contains('spent') ||
        lower.contains('payment of')) {
      isDebit = true;
    } else if (lower.contains('credited') ||
        lower.contains('deposited') ||
        RegExp(r'\bcredit(ed)?\s+(of|with|to|by)\b').hasMatch(lower) ||
        lower.contains('salary')) {
      isDebit = false;
    }
    if (isDebit == null) return null;

    final amtMatch = _amount.firstMatch(body);
    if (amtMatch == null) return null;
    final amount = double.tryParse(amtMatch.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;

    String? tail;
    for (final p in _tailPatterns) {
      final m = p.firstMatch(body);
      if (m != null) {
        tail = m.group(1);
        break;
      }
    }
    if (tail == null) return null;

    String merchant = '';
    for (final p in _merchantPatterns) {
      final m = p.firstMatch(body);
      if (m != null) {
        merchant = _clean(m.group(1) ?? '');
        if (merchant.isNotEmpty) break;
      }
    }

    return ParsedSms(
      amount: amount,
      isDebit: isDebit,
      tail: tail,
      merchant: merchant,
    );
  }

  static String _clean(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Best-effort category guess from the merchant text. Labels must match
  /// entries in data/categories.dart.
  static String guessCategory(String merchant, bool isDebit) {
    if (!isDebit) return 'Other Assessable Income';
    final m = merchant.toLowerCase();
    if (m.contains('keells') ||
        m.contains('cargills') ||
        m.contains('food city') ||
        m.contains('arpico') ||
        m.contains('glomark') ||
        m.contains('super')) {
      return 'Food & Groceries';
    }
    if (m.contains('pizza') ||
        m.contains('kfc') ||
        m.contains('mcdonald') ||
        m.contains('burger') ||
        m.contains('restaurant') ||
        m.contains('cafe') ||
        m.contains('ice cream') ||
        m.contains('carnival') ||
        m.contains('bakery')) {
      return 'Entertainment & Dining';
    }
    if (m.contains('fuel') ||
        m.contains('petrol') ||
        m.contains('ceypetco') ||
        m.contains('ioc') ||
        m.contains('filling')) {
      return 'Fuel';
    }
    if (m.contains('dialog') ||
        m.contains('mobitel') ||
        m.contains('slt') ||
        m.contains('hutch') ||
        m.contains('airtel') ||
        m.contains('ceb') ||
        m.contains('water board')) {
      return 'Utilities & Bills';
    }
    if (m.contains('uber') || m.contains('pickme') || m.contains('taxi')) {
      return 'Vehicle / Transport';
    }
    if (m.contains('pharma') ||
        m.contains('hospital') ||
        m.contains('medical') ||
        m.contains('osu sala') ||
        m.contains('lanka hospital')) {
      return 'Healthcare / Medical';
    }
    return 'Other';
  }
}

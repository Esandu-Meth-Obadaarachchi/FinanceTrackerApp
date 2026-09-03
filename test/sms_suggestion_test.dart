// When a bank-SMS suggestion is safe to approve in one tap, and when it has
// to stop and ask. Getting this wrong either buries the user in prompts or
// files wrong numbers silently.

import 'package:financialtracker/models/sms_suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

SmsSuggestion make({
  double amount = 4250,
  String category = 'Food & Groceries',
  String accountId = 'a1',
  double confidence = 0.9,
  SuggestionSource source = SuggestionSource.ai,
}) =>
    SmsSuggestion(
      id: 'x',
      body: 'Purchase at KEELLS SUPER for LKR 4,250.00',
      receivedAt: DateTime(2026, 9, 3),
      amount: amount,
      type: 'expense',
      category: category,
      accountId: accountId,
      confidence: confidence,
      source: source,
    );

void main() {
  group('one-tap approval', () {
    test('a complete, confident suggestion needs no editing', () {
      final s = make();
      expect(s.isOneTap, isTrue);
      expect(s.blocker, isNull);
    });

    test('a remembered merchant is trusted even at low confidence', () {
      // Local memory only ever holds answers the user confirmed before.
      final s = make(confidence: 0, source: SuggestionSource.memory);
      expect(s.isOneTap, isTrue);
      expect(s.blocker, isNull);
    });

    test('a rules guess is held back for a look', () {
      final s = make(confidence: 0.5, source: SuggestionSource.rules);
      expect(s.isOneTap, isFalse);
      expect(s.blocker, 'Check the category');
    });
  });

  group('what is missing', () {
    test('an unreadable amount blocks first', () {
      expect(make(amount: 0).blocker, 'Amount not readable');
    });

    test('an unmatched card tail asks for the account', () {
      // Reported when smsIds match no account, or more than one.
      expect(make(accountId: '').blocker, 'Pick an account');
    });

    test('a missing category asks for one', () {
      expect(make(category: '').blocker, 'Pick a category');
    });

    test('the amount is reported before anything else', () {
      final broken = make(amount: 0, accountId: '', category: '');
      expect(broken.blocker, 'Amount not readable');
    });
  });

  group('identity', () {
    test('the same message always yields the same id', () {
      const body = 'Purchase at KEELLS SUPER for LKR 4,250.00';
      expect(SmsSuggestion.signatureOf(body),
          SmsSuggestion.signatureOf(body));
    });

    test('surrounding whitespace does not create a new message', () {
      // The live listener and the startup inbox scan see the same SMS and
      // must agree, or it gets queued twice.
      expect(SmsSuggestion.signatureOf('  hello  '),
          SmsSuggestion.signatureOf('hello'));
    });

    test('different messages get different ids', () {
      expect(SmsSuggestion.signatureOf('one'),
          isNot(SmsSuggestion.signatureOf('two')));
    });
  });

  test('survives a JSON round trip', () {
    final original = make();
    final restored = SmsSuggestion.fromJson(original.toJson());

    expect(restored.amount, original.amount);
    expect(restored.category, original.category);
    expect(restored.source, original.source);
    expect(restored.status, SuggestionStatus.pending);
    expect(restored.receivedAt, original.receivedAt);
  });

  test('copyWith keeps the identity and the raw message', () {
    final edited = make().copyWith(category: 'Fuel', confidence: 1);
    expect(edited.id, 'x');
    expect(edited.body, contains('KEELLS'));
    expect(edited.category, 'Fuel');
  });
}

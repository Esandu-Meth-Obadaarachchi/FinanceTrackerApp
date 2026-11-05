// The local learning layer: what it remembers, and when it admits it does
// not know. Getting the second part wrong is worse than not learning at all.

import 'package:financialtracker/models/category_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tokenise', () {
    test('drops digits, punctuation and filler words', () {
      expect(
        CategoryMemory.tokenise('Rs 3,500 for Lunch at Odel!'),
        ['lunch', 'odel'],
      );
    });

    test('drops words too short to mean anything', () {
      expect(CategoryMemory.tokenise('a b to go car'), ['car']);
    });
  });

  group('learning from notes', () {
    test('knows nothing to begin with', () {
      expect(CategoryMemory().suggest('lunch'), isNull);
    });

    test('one sighting is not enough to act on', () {
      final memory = CategoryMemory()..learn('lunch', 'Entertainment & Dining');
      expect(memory.suggest('lunch'), isNull);
    });

    test('repeated sightings become a suggestion', () {
      final memory = CategoryMemory();
      for (var i = 0; i < 3; i++) {
        memory.learn('lunch at odel', 'Entertainment & Dining');
      }
      expect(memory.suggest('lunch')?.category, 'Entertainment & Dining');
    });

    test('matches on any overlapping word, not the whole phrase', () {
      final memory = CategoryMemory();
      for (var i = 0; i < 3; i++) {
        memory.learn('fuel at IOC', 'Fuel');
      }
      // Never seen this exact wording, but "fuel" carries the signal.
      expect(memory.suggest('fuel top up')?.category, 'Fuel');
    });

    test('stays quiet when two categories are neck and neck', () {
      // Ambiguous history must not produce a confident wrong answer.
      final memory = CategoryMemory();
      for (var i = 0; i < 3; i++) {
        memory.learn('coffee', 'Entertainment & Dining');
        memory.learn('coffee', 'Food & Groceries');
      }
      expect(memory.suggest('coffee'), isNull);
    });

    test('follows the evidence once one side pulls clear', () {
      final memory = CategoryMemory();
      for (var i = 0; i < 10; i++) {
        memory.learn('coffee', 'Entertainment & Dining');
      }
      memory.learn('coffee', 'Food & Groceries');
      expect(memory.suggest('coffee')?.category, 'Entertainment & Dining');
    });
  });

  group('merchants from SMS', () {
    test('an exact merchant match wins outright', () {
      final memory = CategoryMemory()
        ..learn('Keells', 'Food & Groceries', merchant: 'KEELLS SUPER COL 03');

      final hit = memory.suggest('', merchant: 'KEELLS SUPER COL 03');
      expect(hit?.category, 'Food & Groceries');
      expect(hit?.exact, isTrue);
      // One sighting is enough here: banks print merchants verbatim.
      expect(hit?.isStrong, isTrue);
    });

    test('merchant matching ignores case and punctuation noise', () {
      final memory = CategoryMemory()
        ..learn('Keells', 'Food & Groceries', merchant: 'KEELLS SUPER COL 03');
      expect(
        memory.suggest('', merchant: 'keells  super, col 03')?.category,
        'Food & Groceries',
      );
    });

    test('an unknown merchant falls through to token scoring', () {
      final memory = CategoryMemory();
      for (var i = 0; i < 3; i++) {
        memory.learn('fuel', 'Fuel');
      }
      expect(
        memory.suggest('fuel purchase', merchant: 'SOME NEW STATION')?.category,
        'Fuel',
      );
    });
  });

  group('correcting a mistake', () {
    test('unlearn removes what was wrongly recorded', () {
      final memory = CategoryMemory();
      for (var i = 0; i < 3; i++) {
        memory.learn('lunch', 'Fuel');
      }
      expect(memory.suggest('lunch')?.category, 'Fuel');

      for (var i = 0; i < 3; i++) {
        memory.unlearn('lunch', 'Fuel');
      }
      expect(memory.suggest('lunch'), isNull);
    });

    test('unlearning something never learned is harmless', () {
      final memory = CategoryMemory()..unlearn('nothing here', 'Fuel');
      expect(memory.isEmpty, isTrue);
    });
  });

  group('persistence', () {
    test('survives a JSON round trip intact', () {
      final memory = CategoryMemory();
      for (var i = 0; i < 3; i++) {
        memory.learn('lunch at odel', 'Entertainment & Dining');
      }
      memory.learn('Keells', 'Food & Groceries', merchant: 'KEELLS SUPER');

      final restored = CategoryMemory.fromJson(memory.toJson());

      expect(restored.suggest('lunch')?.category, 'Entertainment & Dining');
      expect(
        restored.suggest('', merchant: 'KEELLS SUPER')?.category,
        'Food & Groceries',
      );
      expect(restored.learnedTokens, memory.learnedTokens);
    });

    test('reads an empty payload without complaint', () {
      expect(CategoryMemory.fromJson({}).isEmpty, isTrue);
    });
  });
}

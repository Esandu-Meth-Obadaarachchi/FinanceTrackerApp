// Splitting a pending income as part of it is received.

import 'package:financialtracker/models/income_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a part payment banks what arrived and leaves the rest', () {
    final s = splitPendingIncome(50000, 20000);
    expect(s.receipt, 20000);
    expect(s.remaining, 30000);
    expect(s.settlesFully, isFalse);
  });

  test('receiving the whole amount settles it outright', () {
    final s = splitPendingIncome(50000, 50000);
    expect(s.receipt, 50000);
    expect(s.remaining, 0);
    expect(s.settlesFully, isTrue);
  });

  test('you cannot receive more than is outstanding', () {
    final s = splitPendingIncome(50000, 80000);
    expect(s.receipt, 50000);
    expect(s.remaining, 0);
    expect(s.settlesFully, isTrue);
  });

  test('float dust still counts as settled in full', () {
    // 0.001 short of the balance should not strand a pending entry.
    final s = splitPendingIncome(50000, 49999.999);
    expect(s.settlesFully, isTrue);
    expect(s.remaining, 0);
  });

  test('a payment just under the tolerance leaves a remainder', () {
    final s = splitPendingIncome(50000, 49990);
    expect(s.settlesFully, isFalse);
    expect(s.remaining, 10);
  });

  test('a zero or negative request does nothing', () {
    expect(splitPendingIncome(50000, 0).receipt, 0);
    expect(splitPendingIncome(50000, -100).receipt, 0);
  });

  test('the split always conserves the original total', () {
    for (final requested in [1.0, 12345.67, 49999.0]) {
      final s = splitPendingIncome(50000, requested);
      expect(s.receipt + s.remaining, closeTo(50000, 0.0001));
    }
  });
}

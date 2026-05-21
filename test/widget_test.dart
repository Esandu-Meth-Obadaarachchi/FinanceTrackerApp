// Basic smoke tests for FinTrack helper logic.

import 'package:financialtracker/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fmt produces compact figures', () {
    expect(fmt(500), '500');
    expect(fmt(6800), '6.8k');
    expect(fmt(45200), '45k');
    expect(fmt(1500000), '1.5M');
  });

  test('fmtFull keeps two decimals with grouping', () {
    expect(fmtFull(270500), '270,500.00');
    expect(fmtFull(1234.5), '1,234.50');
  });

  test('recentMonths returns the requested count ending this month', () {
    final months = recentMonths(12);
    expect(months.length, 12);
    expect(months.last, monthKeyOf(DateTime.now()));
  });
}

// Quick notes: what the add form's dropdown offers.

import 'package:financialtracker/models/note_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('income and expense lists are kept apart', () {
    final p = const NotePresets()
        .add('income', 'Tehan class')
        .add('expense', 'Fuel');
    expect(p.forType('income'), ['Tehan class']);
    expect(p.forType('expense'), ['Fuel']);
  });

  test('transfers have no presets and adding one does nothing', () {
    final p = const NotePresets().add('transfer', 'Anything');
    expect(p.forType('transfer'), isEmpty);
    expect(p.isEmpty, isTrue);
  });

  test('blanks and duplicates (any case) are ignored', () {
    var p = const NotePresets().add('income', 'Tehan class');
    p = p.add('income', '   ').add('income', 'tehan CLASS');
    expect(p.income, ['Tehan class']);
  });

  test('whitespace is tidied before saving', () {
    final p = const NotePresets().add('income', '  Tehan    class ');
    expect(p.income, ['Tehan class']);
  });

  test('the list stops growing at the cap', () {
    var p = const NotePresets();
    for (var i = 0; i < kMaxNotePresets + 5; i++) {
      p = p.add('expense', 'note $i');
    }
    expect(p.expense.length, kMaxNotePresets);
  });

  test('removing leaves the other type untouched', () {
    final p = const NotePresets()
        .add('income', 'Tehan class')
        .add('expense', 'Tehan class')
        .remove('income', 'Tehan class');
    expect(p.income, isEmpty);
    expect(p.expense, ['Tehan class']);
  });

  test('match finds a preset ignoring case, and misses otherwise', () {
    final p = const NotePresets().add('income', 'Tehan class');
    expect(p.match('income', ' tehan CLASS '), 'Tehan class');
    expect(p.match('income', 'Tehan'), isNull);
    expect(p.match('expense', 'Tehan class'), isNull);
    expect(p.match('income', ''), isNull);
  });

  test('round trips, and a missing document is just empty', () {
    final p = const NotePresets().add('income', 'A').add('expense', 'B');
    final back = NotePresets.fromMap(p.toMap());
    expect(back.income, ['A']);
    expect(back.expense, ['B']);
    expect(NotePresets.fromMap(null).isEmpty, isTrue);
  });
}

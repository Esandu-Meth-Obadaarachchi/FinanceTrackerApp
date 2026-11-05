/// Most presets kept per type. A dropdown stops being quicker than typing
/// well before this; it also keeps the settings document small.
const kMaxNotePresets = 30;

/// The user's quick notes: short headings such as "Tehan class" that the add
/// form offers in a dropdown, so a regular entry takes a tap rather than typing.
///
/// Income and expense are kept apart because a heading that makes sense for one
/// is noise for the other. Stored as one document, `users/{uid}/settings/notes`.
class NotePresets {
  const NotePresets({this.income = const [], this.expense = const []});

  final List<String> income;
  final List<String> expense;

  /// The presets for a transaction type. Transfers have none.
  List<String> forType(String type) => switch (type) {
        'income' => income,
        'expense' => expense,
        _ => const [],
      };

  bool get isEmpty => income.isEmpty && expense.isEmpty;

  /// Adds [name], trimmed and with inner whitespace collapsed. A blank, a
  /// duplicate (ignoring case) or a full list returns this unchanged.
  NotePresets add(String type, String name) {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final list = forType(type);
    if (clean.isEmpty || list.length >= kMaxNotePresets) return this;
    if (list.any((p) => p.toLowerCase() == clean.toLowerCase())) return this;
    return _with(type, [...list, clean]);
  }

  NotePresets remove(String type, String name) =>
      _with(type, [...forType(type).where((p) => p != name)]);

  /// The preset equal to [note] ignoring case and surrounding space, or null.
  /// Lets an entry saved by typing reopen with its dropdown already selected.
  String? match(String type, String note) {
    final n = note.trim().toLowerCase();
    if (n.isEmpty) return null;
    for (final p in forType(type)) {
      if (p.toLowerCase() == n) return p;
    }
    return null;
  }

  NotePresets _with(String type, List<String> list) => switch (type) {
        'income' => NotePresets(income: list, expense: expense),
        'expense' => NotePresets(income: income, expense: list),
        _ => this,
      };

  Map<String, dynamic> toMap() => {'income': income, 'expense': expense};

  factory NotePresets.fromMap(Map<String, dynamic>? m) => NotePresets(
        income: [for (final x in (m?['income'] as List? ?? [])) x.toString()],
        expense: [for (final x in (m?['expense'] as List? ?? [])) x.toString()],
      );
}

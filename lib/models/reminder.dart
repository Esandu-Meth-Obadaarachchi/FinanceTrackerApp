/// A user-defined reminder for something due — a bill, a credit-card payment,
/// a rent date, anything. It fires [times] local notifications spaced
/// [intervalDays] apart, ending on [dueDate], at [time] each day.
class Reminder {
  final String id;
  final String title; // the reason, e.g. "Credit card minimum payment"
  final double amount; // optional; 0 means none shown
  final String dueDate; // YYYY-MM-DD
  final int times; // how many reminders (>= 1)
  final int intervalDays; // gap between reminders in days (>= 1)
  final String time; // "HH:mm" time of day to fire
  final bool active;

  const Reminder({
    required this.id,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.times,
    required this.intervalDays,
    required this.time,
    required this.active,
  });

  factory Reminder.fromMap(String id, Map<String, dynamic> m) => Reminder(
        id: id,
        title: (m['title'] ?? '') as String,
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        dueDate: (m['dueDate'] ?? '') as String,
        times: (m['times'] as num?)?.toInt() ?? 1,
        intervalDays: (m['intervalDays'] as num?)?.toInt() ?? 1,
        time: (m['time'] ?? '09:00') as String,
        active: (m['active'] ?? true) as bool,
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'amount': amount,
        'dueDate': dueDate,
        'times': times,
        'intervalDays': intervalDays,
        'time': time,
        'active': active,
      };

  DateTime? get dueDateTime => DateTime.tryParse(dueDate);

  int get _hour => int.tryParse(time.split(':').first) ?? 9;
  int get _minute {
    final parts = time.split(':');
    return parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  }

  /// The reminder datetimes, earliest first: [dueDate] and the preceding
  /// `times - 1` slots stepping back by [intervalDays], each at [time].
  List<DateTime> occurrences() {
    final due = dueDateTime;
    if (due == null) return const [];
    final n = times < 1 ? 1 : times;
    final step = intervalDays < 1 ? 1 : intervalDays;
    final out = <DateTime>[];
    for (int i = 0; i < n; i++) {
      final d = due.subtract(Duration(days: i * step));
      out.add(DateTime(d.year, d.month, d.day, _hour, _minute));
    }
    return out.reversed.toList();
  }

  /// The next occurrence still in the future, or null if all are past.
  DateTime? get nextOccurrence {
    final now = DateTime.now();
    for (final o in occurrences()) {
      if (o.isAfter(now)) return o;
    }
    return null;
  }

  Reminder copyWith({
    String? title,
    double? amount,
    String? dueDate,
    int? times,
    int? intervalDays,
    String? time,
    bool? active,
  }) =>
      Reminder(
        id: id,
        title: title ?? this.title,
        amount: amount ?? this.amount,
        dueDate: dueDate ?? this.dueDate,
        times: times ?? this.times,
        intervalDays: intervalDays ?? this.intervalDays,
        time: time ?? this.time,
        active: active ?? this.active,
      );
}

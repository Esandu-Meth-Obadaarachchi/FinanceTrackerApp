import '../models/reminder.dart';
import '../utils/formatters.dart';
import 'notification_service.dart';

/// Turns [Reminder] documents into scheduled local notifications.
///
/// Notification ids are derived deterministically from the reminder id so an
/// edit cancels then re-schedules the same slots. [syncAll] is the single entry
/// point — call it whenever the reminders list changes; it cancels reminders
/// that disappeared and (re)schedules the rest.
class ReminderScheduler {
  ReminderScheduler._();

  /// Upper bound on occurrences per reminder — also how many ids we clear when
  /// cancelling, so reducing `times` on an edit can't leave orphans behind.
  static const int _maxSlots = 24;

  /// Reminder ids seen on the previous sync, used to cancel deletions.
  static final Set<String> _known = {};

  static int notifId(String reminderId, int index) {
    final h = reminderId.hashCode & 0x7fffffff;
    return NotificationService.reminderBase + (h % 100000) * _maxSlots + index;
  }

  /// Reconciles scheduled notifications with [reminders].
  static Future<void> syncAll(List<Reminder> reminders) async {
    if (!NotificationService.instance.isSupported) return;
    final currentIds = reminders.map((r) => r.id).toSet();
    for (final goneId in _known.difference(currentIds)) {
      await _cancelById(goneId);
    }
    _known
      ..clear()
      ..addAll(currentIds);
    for (final r in reminders) {
      await schedule(r);
    }
  }

  /// Cancels any prior slots for [r], then schedules its future occurrences.
  static Future<void> schedule(Reminder r) async {
    await _cancelById(r.id);
    if (!r.active) return;
    final occ = r.occurrences();
    final now = DateTime.now();
    for (int i = 0; i < occ.length && i < _maxSlots; i++) {
      final when = occ[i];
      if (!when.isAfter(now)) continue;
      await NotificationService.instance.scheduleOneOff(
        id: notifId(r.id, i),
        when: when,
        title: r.title.isNotEmpty ? r.title : 'Payment due',
        body: _body(r),
      );
    }
  }

  static Future<void> cancel(Reminder r) => _cancelById(r.id);

  static Future<void> _cancelById(String reminderId) async {
    for (int i = 0; i < _maxSlots; i++) {
      await NotificationService.instance.cancel(notifId(reminderId, i));
    }
    _known.remove(reminderId);
  }

  static String _body(Reminder r) {
    final due = fmtDate(r.dueDate);
    if (r.amount > 0) return 'Rs ${fmtFull(r.amount)} due on $due';
    return 'Due on $due';
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// User-tunable settings for the two daily "log your transactions" nudges.
class DailyReminderPrefs {
  final bool morningOn;
  final TimeOfDay morningTime;
  final bool nightOn;
  final TimeOfDay nightTime;

  const DailyReminderPrefs({
    required this.morningOn,
    required this.morningTime,
    required this.nightOn,
    required this.nightTime,
  });

  DailyReminderPrefs copyWith({
    bool? morningOn,
    TimeOfDay? morningTime,
    bool? nightOn,
    TimeOfDay? nightTime,
  }) =>
      DailyReminderPrefs(
        morningOn: morningOn ?? this.morningOn,
        morningTime: morningTime ?? this.morningTime,
        nightOn: nightOn ?? this.nightOn,
        nightTime: nightTime ?? this.nightTime,
      );
}

/// Local (on-device) notifications: daily reminders, custom due-payment
/// reminders, and showing foreground push messages. No server required — these
/// fire even when the app is closed (Android boot receiver re-arms them).
///
/// Everything is a no-op on web (the plugin can't deliver while the tab is
/// closed) and is wrapped in try/catch so notification failures never crash the
/// app.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get isSupported => !kIsWeb;

  // Reserved notification ids.
  static const int idMorning = 1001;
  static const int idNight = 1002;

  /// Custom reminders (Phase 4) derive their ids from this base so they never
  /// collide with the daily reminders above.
  static const int reminderBase = 1000000;

  // Channels.
  static const String _dailyChannel = 'daily_reminders';
  static const String _dueChannel = 'due_reminders';
  static const String _generalChannel = 'general';

  // Pref keys for the daily reminders.
  static const _kMorningOn = 'ft_notif_morning_on';
  static const _kMorningTime = 'ft_notif_morning_time'; // "HH:mm"
  static const _kNightOn = 'ft_notif_night_on';
  static const _kNightTime = 'ft_notif_night_time';

  // ── Lifecycle ────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        // Fall back to Sri Lanka if the device timezone can't be resolved.
        try {
          tz.setLocalLocation(tz.getLocation('Asia/Colombo'));
        } catch (_) {}
      }

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings =
          InitializationSettings(android: android, iOS: darwin, macOS: darwin);
      await _plugin.initialize(settings: settings);
      await _createChannels();
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> _createChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(const AndroidNotificationChannel(
      _dailyChannel,
      'Daily reminders',
      description: 'Morning and night nudges to log your transactions.',
      importance: Importance.defaultImportance,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      _dueChannel,
      'Due payment reminders',
      description: 'Reminders for bills and payments you set.',
      importance: Importance.high,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      _generalChannel,
      'Announcements',
      description: 'Updates and announcements from FinTrack.',
      importance: Importance.high,
    ));
  }

  /// Asks the OS for notification (and exact-alarm) permission. Safe to call
  /// repeatedly — the OS only prompts once.
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    bool granted = true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        granted = await android.requestNotificationsPermission() ?? false;
        await android.requestExactAlarmsPermission();
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        granted = await ios.requestPermissions(
                alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (_) {}
    return granted;
  }

  // ── Daily reminders ──────────────────────────────────────────────────────
  Future<DailyReminderPrefs> loadDailyPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      return DailyReminderPrefs(
        morningOn: p.getBool(_kMorningOn) ?? true,
        morningTime: _parseTime(p.getString(_kMorningTime), 8, 0),
        nightOn: p.getBool(_kNightOn) ?? true,
        nightTime: _parseTime(p.getString(_kNightTime), 21, 0),
      );
    } catch (_) {
      return const DailyReminderPrefs(
        morningOn: true,
        morningTime: TimeOfDay(hour: 8, minute: 0),
        nightOn: true,
        nightTime: TimeOfDay(hour: 21, minute: 0),
      );
    }
  }

  /// Persists [prefs] and (re)schedules the daily reminders to match.
  Future<void> saveDailyPrefs(DailyReminderPrefs prefs) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kMorningOn, prefs.morningOn);
      await p.setString(_kMorningTime, _fmtTime(prefs.morningTime));
      await p.setBool(_kNightOn, prefs.nightOn);
      await p.setString(_kNightTime, _fmtTime(prefs.nightTime));
    } catch (_) {}
    await applyDailyReminders(prefs);
  }

  Future<void> applyDailyReminders(DailyReminderPrefs prefs) async {
    if (kIsWeb || !_ready) return;
    await cancel(idMorning);
    await cancel(idNight);
    if (prefs.morningOn) {
      await _zonedSchedule(
        id: idMorning,
        when: _nextInstanceOfTime(prefs.morningTime),
        title: 'Log your day',
        body: "Add today's income and expenses so your balances stay accurate.",
        channelId: _dailyChannel,
        channelName: 'Daily reminders',
        channelDesc: 'Morning and night nudges to log your transactions.',
        importance: Importance.defaultImportance,
        match: DateTimeComponents.time,
      );
    }
    if (prefs.nightOn) {
      await _zonedSchedule(
        id: idNight,
        when: _nextInstanceOfTime(prefs.nightTime),
        title: 'Before you sleep',
        body: "Did you record today's spending? Tap to add anything you missed.",
        channelId: _dailyChannel,
        channelName: 'Daily reminders',
        channelDesc: 'Morning and night nudges to log your transactions.',
        importance: Importance.defaultImportance,
        match: DateTimeComponents.time,
      );
    }
  }

  /// Re-arms daily reminders from saved prefs (called once on app launch).
  Future<void> rearmDailyReminders() async {
    if (kIsWeb || !_ready) return;
    await applyDailyReminders(await loadDailyPrefs());
  }

  // ── One-off / custom reminders (used by Phase 4) ──────────────────────────
  /// Schedules a single notification at [when] on the due-reminders channel.
  Future<void> scheduleOneOff({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb || !_ready) return;
    if (!when.isAfter(DateTime.now())) return; // never schedule in the past
    await _zonedSchedule(
      id: id,
      when: tz.TZDateTime.from(when, tz.local),
      title: title,
      body: body,
      payload: payload,
      channelId: _dueChannel,
      channelName: 'Due payment reminders',
      channelDesc: 'Reminders for bills and payments you set.',
      importance: Importance.high,
    );
  }

  /// Immediate notification (used to surface foreground FCM messages, Phase 5).
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb || !_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _generalChannel,
            'Announcements',
            channelDescription: 'Updates and announcements from FinTrack.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (_) {}
  }

  Future<void> cancel(int id) async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  // ── Internals ─────────────────────────────────────────────────────────────
  Future<void> _zonedSchedule({
    required int id,
    required tz.TZDateTime when,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    required String channelDesc,
    required Importance importance,
    DateTimeComponents? match,
    String? payload,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: importance,
        priority: importance == Importance.high
            ? Priority.high
            : Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        payload: payload,
        scheduledDate: when,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: match,
      );
    } catch (_) {
      // Exact alarms not permitted — fall back to inexact so it still fires.
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          payload: payload,
          scheduledDate: when,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: match,
        );
      } catch (_) {}
    }
  }

  tz.TZDateTime _nextInstanceOfTime(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  TimeOfDay _parseTime(String? raw, int defH, int defM) {
    if (raw == null) return TimeOfDay(hour: defH, minute: defM);
    final parts = raw.split(':');
    if (parts.length != 2) return TimeOfDay(hour: defH, minute: defM);
    final h = int.tryParse(parts[0]) ?? defH;
    final m = int.tryParse(parts[1]) ?? defM;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

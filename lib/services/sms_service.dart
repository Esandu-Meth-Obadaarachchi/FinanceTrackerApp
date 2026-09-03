import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sms_suggestion.dart';
import '../state/app_state.dart';
import 'sms_inbox.dart';

/// Watches for bank SMS and feeds them to [SmsInbox] for review
/// (Android only).
///
/// Listens live while the app runs and scans the last two days of inbox on
/// start, to catch what arrived while it was closed. Background (app killed)
/// delivery is intentionally out of scope: it needs a Firebase-enabled
/// isolate.
///
/// Nothing here writes a transaction. Messages become suggestions the user
/// approves — see [SmsInbox].
class SmsService {
  SmsService._();
  static final SmsService instance = SmsService._();

  final Telephony _telephony = Telephony.instance;
  bool _running = false;
  AppState? _app;

  static const _kEnabled = 'ft_sms_enabled';
  static const _kProcessed = 'ft_sms_processed';

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_kEnabled) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Turns the feature on/off. Returns the effective enabled state (turning on
  /// fails if SMS permission is denied).
  Future<bool> setEnabled(bool value, AppState app) async {
    if (!isSupported) return false;
    if (!value) {
      _running = false;
      await _writeEnabled(false);
      return false;
    }
    final ok = await start(app);
    await _writeEnabled(ok);
    return ok;
  }

  /// Begins listening and scans the recent inbox. Requests SMS permission if
  /// needed; returns false if permission is denied.
  Future<bool> start(AppState app) async {
    if (!isSupported) return false;
    _app = app;
    if (_running) return true;
    bool granted = false;
    try {
      granted = await _telephony.requestPhoneAndSmsPermissions ?? false;
    } catch (_) {}
    if (!granted) return false;
    try {
      _telephony.listenIncomingSms(
        onNewMessage: _onIncoming,
        listenInBackground: false,
      );
    } catch (_) {}
    _running = true;
    await _scanRecent();
    return true;
  }

  /// Starts only if the user has previously enabled the feature.
  Future<void> startIfEnabled(AppState app) async {
    if (await isEnabled()) await start(app);
  }

  void _onIncoming(SmsMessage message) {
    _process(message.body ?? '', DateTime.now(),
        sender: message.address ?? '');
  }

  Future<void> _scanRecent() async {
    try {
      final msgs = await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      );
      final cutoff = DateTime.now().subtract(const Duration(days: 2));
      for (final m in msgs) {
        final when = m.date != null
            ? DateTime.fromMillisecondsSinceEpoch(m.date!)
            : DateTime.now();
        if (when.isBefore(cutoff)) continue;
        await _process(m.body ?? '', when, sender: m.address ?? '');
      }
    } catch (_) {}
  }

  /// Hand the message to [SmsInbox] as a suggestion to review.
  ///
  /// This used to write a transaction outright, and only when regex matched
  /// *and* the card tail mapped to exactly one account. That guard kept bad
  /// data out, but it also silently dropped every message with an
  /// unrecognised merchant or an ambiguous tail — most of them. Queueing
  /// instead means nothing is written without a tap, so a message worth
  /// showing no longer has to clear the bar for writing.
  Future<void> _process(String body, DateTime when, {String sender = ''}) async {
    final app = _app;
    if (app == null) return;

    final sig = SmsSuggestion.signatureOf(body);
    if (await _seen(sig)) return;

    try {
      await SmsInbox.instance.ingest(body, when, app, sender: sender);
      await _markSeen(sig);
    } catch (_) {}
  }

  Future<void> _writeEnabled(bool v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kEnabled, v);
    } catch (_) {}
  }

  Future<bool> _seen(String sig) async {
    try {
      final p = await SharedPreferences.getInstance();
      return (p.getStringList(_kProcessed) ?? const []).contains(sig);
    } catch (_) {
      return false;
    }
  }

  Future<void> _markSeen(String sig) async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = p.getStringList(_kProcessed) ?? <String>[];
      list.add(sig);
      final capped =
          list.length > 300 ? list.sublist(list.length - 300) : list;
      await p.setStringList(_kProcessed, capped);
    } catch (_) {}
  }
}

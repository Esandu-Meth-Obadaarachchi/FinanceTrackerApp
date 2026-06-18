import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

/// Background isolate handler. Must be a top-level function with the entry-point
/// pragma. For our broadcast use-case the OS auto-displays notification messages
/// on the default channel, so there's nothing to do here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Firebase Cloud Messaging for global broadcasts.
///
/// Every user subscribes to the `all` topic (and a per-uid topic for future
/// targeted sends). Broadcasts are sent by hand from the Firebase Console —
/// there is no server on the free tier. Android/iOS only: web cannot subscribe
/// to topics from the client SDK, so this is a no-op on web.
class MessagingService {
  MessagingService._();
  static final MessagingService instance = MessagingService._();

  bool _started = false;

  /// Registers handlers, asks permission, and subscribes to the `all` topic.
  /// Call once after Firebase is initialised (and not on web).
  Future<void> init() async {
    if (kIsWeb || _started) return;
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await FirebaseMessaging.instance.requestPermission();
      await FirebaseMessaging.instance.subscribeToTopic('all');

      // App in foreground: the OS won't show notification messages itself, so
      // surface them through the local-notifications plugin.
      FirebaseMessaging.onMessage.listen((message) {
        final n = message.notification;
        if (n == null) return;
        NotificationService.instance.show(
          id: message.hashCode & 0x7fffffff,
          title: n.title ?? 'FinTrack',
          body: n.body ?? '',
        );
      });
      _started = true;
    } catch (_) {
      // Messaging is best-effort — never block app start.
    }
  }

  /// Subscribes to this user's personal topic for future targeted sends.
  Future<void> subscribeUser(String uid) async {
    if (kIsWeb || uid.isEmpty) return;
    try {
      await FirebaseMessaging.instance.subscribeToTopic('user_$uid');
    } catch (_) {}
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../firebase_options.dart';
import 'notification_service.dart';

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final ValueNotifier<bool> openAlertsRequested = ValueNotifier<bool>(
    false,
  );

  static String? _uid;
  static String? _token;
  static StreamSubscription<String>? _tokenRefreshSubscription;

  static Future<void> initialize() async {
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    }

    // FOREGROUND MESSAGE
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final notification = message.notification;

      if (notification != null) {
        await NotificationService.showFireAlert(
          severity: _extractSeverity(message),
          fireProbability: _extractDouble(message.data['fireProbability'], 0),
          smokeProbability: _extractDouble(message.data['smokeProbability'], 0),
          temperature: _extractDouble(message.data['temperature'], 0),
          humidity: _extractDouble(message.data['humidity'], 0),
        );
      }
    });

    // APP OPENED FROM BACKGROUND NOTIFICATION
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('FCM notification opened from background.');

      _requestAlertsScreen();
    });

    // APP OPENED FROM TERMINATED STATE
    final initialMessage = await _messaging.getInitialMessage();

    if (initialMessage != null) {
      debugPrint('FCM app launch caused by notification.');

      _requestAlertsScreen();
    }
  }

  /// Registers this device's push token under the signed-in user
  /// (`users/{uid}/tokens/{token}`) so the backend can reach every phone the
  /// user is signed in on. Safe to call repeatedly.
  static Future<void> registerForUser(String uid) async {
    if (_uid == uid && _token != null) {
      return;
    }

    _uid = uid;

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Push notifications denied by the user.');
        return;
      }

      final token = await _messaging.getToken(
        vapidKey: kIsWeb && AppConfig.webPushVapidKey.isNotEmpty
            ? AppConfig.webPushVapidKey
            : null,
      );

      if (token != null) {
        await _saveToken(uid, token);
      }

      _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen(
        (newToken) async {
          final currentUid = _uid;

          if (currentUid != null) {
            await _saveToken(currentUid, newToken);
          }
        },
        onError: (error) {
          debugPrint('FCM token refresh error: $error');
        },
      );
    } catch (error) {
      debugPrint('FCM registration failed: $error');
    }
  }

  /// Removes this device's token so a signed-out phone stops getting alerts.
  static Future<void> unregister() async {
    final uid = _uid;
    final token = _token;

    _uid = null;
    _token = null;

    if (uid == null || token == null) {
      return;
    }

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc(token)
          .delete();
      await _messaging.deleteToken();
    } catch (error) {
      debugPrint('FCM unregister failed: $error');
    }
  }

  // Called by NotificationService when the user
  // taps a local foreground notification.
  static void handleLocalNotificationTap() {
    debugPrint('Local notification tapped.');

    _requestAlertsScreen();
  }

  static void _requestAlertsScreen() {
    openAlertsRequested.value = true;
  }

  static String _extractSeverity(RemoteMessage message) {
    final severity = message.data['severity'];

    if (severity != null && severity.toString().isNotEmpty) {
      return severity.toString();
    }

    final title = message.notification?.title ?? '';

    if (title.toUpperCase().contains('CRITICAL')) {
      return 'CRITICAL';
    }

    if (title.toUpperCase().contains('HIGH')) {
      return 'HIGH';
    }

    if (title.toUpperCase().contains('MODERATE')) {
      return 'MODERATE';
    }

    return 'FIRE';
  }

  static double _extractDouble(dynamic value, double fallback) {
    if (value == null) {
      return fallback;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? fallback;
  }

  static Future<void> _saveToken(String uid, String token) async {
    _token = token;

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc(token)
          .set({
            'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (error) {
      debugPrint('Failed to save FCM token: $error');
    }
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // The system tray shows the notification itself; this only needs Firebase
  // ready in the background isolate.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

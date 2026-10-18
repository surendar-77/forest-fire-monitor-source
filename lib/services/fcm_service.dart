import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'node_config.dart';

import 'notification_service.dart';

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final ValueNotifier<bool> openAlertsRequested = ValueNotifier<bool>(
    false,
  );

  static Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint('FCM permission: ${settings.authorizationStatus}');

    final token = await _messaging.getToken();

    debugPrint('================================');
    debugPrint('FCM REGISTRATION TOKEN');
    debugPrint(token ?? 'Token unavailable');
    debugPrint('================================');

    if (token != null) {
      await _saveToken(token);
    }

    _messaging.onTokenRefresh.listen(
      (newToken) async {
        debugPrint('FCM TOKEN REFRESHED: $newToken');

        await _saveToken(newToken);
      },
      onError: (error) {
        debugPrint('FCM token refresh error: $error');
      },
    );

    // FOREGROUND MESSAGE
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('FCM FOREGROUND MESSAGE');

      debugPrint('Title: ${message.notification?.title}');

      debugPrint('Body: ${message.notification?.body}');

      debugPrint('Data: ${message.data}');

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

  static Future<void> _saveToken(String token) async {
    try {
      await _firestore.collection('devices').doc(NodeConfig.nodeId).set({
        'fcmToken': token,
        'notificationEnabled': true,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('FCM token saved to Firestore.');
    } catch (error) {
      debugPrint('Failed to save FCM token: $error');
    }
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  debugPrint('FCM BACKGROUND MESSAGE: ${message.messageId}');

  debugPrint('Background data: ${message.data}');
}

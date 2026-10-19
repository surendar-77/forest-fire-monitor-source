import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static final AudioPlayer _alarmPlayer = AudioPlayer();

  // A channel's sound can't change once created, so the alarm tone lives
  // in its own channel. Must match ANDROID_CHANNEL_ID in worker/src/fcm.ts.
  static const String _channelId = 'forest_fire_alarm';
  static const String _channelName = 'Fire alarms';
  static const String _channelDescription =
      'Fire and smoke alerts, with the fire alarm sound';

  /// android/app/src/main/res/raw/fire_alarm.mp3
  static const _alarmSound = RawResourceAndroidNotificationSound('fire_alarm');

  static bool _alarmPlaying = false;

  static Future<void> initialize({void Function()? onNotificationTap}) async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Permission is requested later by FcmService, after sign-in, so the
    // prompt appears once and in context.
    const DarwinInitializationSettings darwinSettings =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        onNotificationTap?.call();
        stopEmergencyAlarm();
      },
    );

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.requestNotificationsPermission();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.max,
      playSound: true,
      sound: _alarmSound,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
    );

    await androidPlugin?.createNotificationChannel(channel);
    // The old channel (default sound) is no longer used.
    await androidPlugin?.deleteNotificationChannel(channelId: 'forest_fire_alerts');
  }

  static Future<void> showFireAlert({
    required String severity,
    required double fireProbability,
    required double smokeProbability,
    required double temperature,
    required double humidity,
  }) async {
    final bool emergency = severity == 'HIGH' || severity == 'CRITICAL';

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound: _alarmSound,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          enableVibration: true,
          ticker: 'Forest Fire Alert',
        );

    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _notifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: '$severity FIRE ALERT',
      body:
          'Fire ${fireProbability.toStringAsFixed(0)}% | '
          'Smoke ${smokeProbability.toStringAsFixed(0)}% | '
          '${temperature.toStringAsFixed(1)} C',
      notificationDetails: notificationDetails,
    );

    if (emergency) {
      await startEmergencyAlarm();
    }
  }

  static Future<void> startEmergencyAlarm() async {
    if (_alarmPlaying) {
      return;
    }

    _alarmPlaying = true;

    try {
      await _alarmPlayer.setReleaseMode(ReleaseMode.loop);

      await _alarmPlayer.play(
        AssetSource('sounds/emergency_alarm.mp3'),
        volume: 1.0,
      );
    } catch (error) {
      _alarmPlaying = false;
      debugPrint('Emergency alarm failed: $error');
    }
  }

  static Future<void> stopEmergencyAlarm() async {
    if (!_alarmPlaying) {
      return;
    }

    try {
      await _alarmPlayer.stop();
    } finally {
      _alarmPlaying = false;
    }
  }

  static Future<void> dispose() async {
    await stopEmergencyAlarm();
    await _alarmPlayer.dispose();
  }
}

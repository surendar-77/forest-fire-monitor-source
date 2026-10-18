import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'screens/app_shell.dart';
import 'screens/location_settings_screen.dart';
import 'services/fcm_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Notification setup can fail on some platforms (e.g. web without a
  // messaging service worker); don't let that keep the app from starting.
  try {
    await NotificationService.initialize(
      onNotificationTap: FcmService.handleLocalNotificationTap,
    );
  } catch (e) {
    debugPrint('Local notifications unavailable: $e');
  }

  try {
    await FcmService.initialize();
  } catch (e) {
    debugPrint('FCM unavailable: $e');
  }

  runApp(const ForestFireApp());
}

class ForestFireApp extends StatelessWidget {
  const ForestFireApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Forest Fire Monitor',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
      ),
      home: const AppShell(),
      routes: {
        '/location-settings': (context) => const LocationSettingsScreen(),
      },
    );
  }
}

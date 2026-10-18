import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/app_shell.dart';
import 'screens/location_settings_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/fcm_service.dart';
import 'services/node_repository.dart';
import 'services/notification_service.dart';

/// Crashlytics has no web implementation.
bool get _crashReportingSupported => !kIsWeb;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (_crashReportingSupported) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !kDebugMode,
    );
  }

  // Keep the last-known readings available offline. Mobile caches by
  // default; web needs it switched on.
  if (kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
  }

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

  final auth = AuthService()..start();

  runApp(ForestFireApp(auth: auth, repository: NodeRepository()));
}

class ForestFireApp extends StatelessWidget {
  const ForestFireApp({
    super.key,
    required this.auth,
    required this.repository,
  });

  final AuthService auth;
  final NodeRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Forest Fire Monitor',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
      ),
      home: AuthGate(auth: auth, repository: repository),
      routes: {
        '/location-settings': (context) => const LocationSettingsScreen(),
      },
    );
  }
}

/// Shows the sign-in screen until a user is signed in, and stops live data
/// when they sign out so nothing from the previous user stays on screen.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.auth, required this.repository});

  final AuthService auth;
  final NodeRepository repository;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _activeUid;

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_handleAuthChange);
  }

  void _handleAuthChange() {
    final uid = widget.auth.user?.uid;

    if (uid == _activeUid) {
      return;
    }

    _activeUid = uid;

    if (uid == null) {
      unawaited(widget.repository.stop());
    }

    if (_crashReportingSupported) {
      unawaited(FirebaseCrashlytics.instance.setUserIdentifier(uid ?? ''));
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_handleAuthChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.auth,
      builder: (context, _) {
        if (!widget.auth.initialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = widget.auth.user;

        if (user == null) {
          return LoginScreen(auth: widget.auth);
        }

        return AppShell(
          key: ValueKey(user.uid),
          auth: widget.auth,
          repository: widget.repository,
        );
      },
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forest_fire_monitor/models/app_user.dart';
import 'package:forest_fire_monitor/screens/dashboard_screen.dart';
import 'package:forest_fire_monitor/screens/home_map_screen.dart';
import 'package:forest_fire_monitor/services/data_source_controller.dart';
import 'package:forest_fire_monitor/services/node_repository.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'alerts_screen_test.dart' show FakeAuth;

class _NoFirestore extends Fake implements FirebaseFirestore {}

class _NoAuth extends Fake implements FirebaseAuth {}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('demo scenarios change what the sensor panel shows', (
    tester,
  ) async {
    final controller = DataSourceController(
      repository: NodeRepository(firestore: _NoFirestore(), auth: _NoAuth()),
    );
    await controller.switchToSimulation();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardScreen(
            controller: controller,
            auth: FakeAuth(UserRole.admin),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('All clear'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Smoke seen'), 200);
    await tester.tap(find.text('Smoke seen'));
    await tester.pumpAndSettle();
    expect(find.text('All clear'), findsNothing);
  });

  testWidgets('demo mode shows a demo sensor on the map', (tester) async {
    final controller = DataSourceController(
      repository: NodeRepository(firestore: _NoFirestore(), auth: _NoAuth()),
    );
    await controller.switchToSimulation();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeMapScreen(
            controller: controller,
            auth: FakeAuth(UserRole.admin),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Demo sensor'), findsOneWidget);

    expect(find.text('Demo: tap a scenario'), findsOneWidget);

    await tester.tap(find.text('Fire!').first);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.simulationService.activeAlerts, hasLength(1));
    expect(find.textContaining('risk critical'), findsOneWidget);
  });
}

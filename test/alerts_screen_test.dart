import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forest_fire_monitor/models/alert_model.dart';
import 'package:forest_fire_monitor/models/app_user.dart';
import 'package:forest_fire_monitor/models/detection_model.dart';
import 'package:forest_fire_monitor/screens/alerts_screen.dart';
import 'package:forest_fire_monitor/services/auth_service.dart';
import 'package:forest_fire_monitor/services/monitoring_data_source.dart';

class FakeAuth extends AuthService {
  FakeAuth(this.fakeRole);

  final UserRole fakeRole;

  @override
  AppUser? get user => AppUser(
    uid: 'u1',
    email: 'u1@example.org',
    displayName: 'Test User',
    role: fakeRole,
  );

  @override
  bool get initialized => true;

  @override
  UserRole get role => fakeRole;

  @override
  bool get canRespondToAlerts => fakeRole.canRespondToAlerts;

  @override
  bool get isAdmin => fakeRole == UserRole.admin;
}

class FakeSource extends MonitoringDataSource {
  FakeSource(this.alerts);

  final List<AlertModel> alerts;
  final List<String> acknowledged = [];

  @override
  DetectionModel get data => const DetectionModel(
    deviceId: 'NODE-01',
    temperature: 30,
    humidity: 40,
    fireProbability: 0,
    smokeProbability: 0,
    latitude: 0,
    longitude: 0,
    riskScore: 10,
    riskLevel: 'LOW',
    alertActive: true,
  );

  @override
  List<AlertModel> get alertHistory => alerts;

  @override
  List<AlertModel> get activeAlerts => alerts.where((a) => a.isOpen).toList();

  @override
  AlertModel? get currentAlert => activeAlerts.firstOrNull;

  @override
  bool get isDataAvailable => true;

  @override
  bool get isLive => true;

  @override
  DateTime? get lastUpdated => DateTime(2026);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> acknowledgeAlert(String alertId) async {
    acknowledged.add(alertId);
  }

  @override
  Future<void> resolveIncident(String alertId) async {}
}

AlertModel _alert(String id, String status) => AlertModel(
  id: id,
  deviceId: 'NODE-01',
  type: 'FIRE',
  severity: 'CRITICAL',
  fireProbability: 92,
  smokeProbability: 0,
  temperature: 44,
  humidity: 18,
  latitude: 12.9,
  longitude: 77.5,
  detectedAt: DateTime(2026, 10, 18, 9),
  status: status,
);

Future<void> _pump(WidgetTester tester, FakeSource source, UserRole role) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AlertsScreen(simulationService: source, auth: FakeAuth(role)),
      ),
    ),
  );
}

void main() {
  testWidgets('viewers see alerts but no response buttons', (tester) async {
    final source = FakeSource([_alert('a1', AlertStatus.active)]);

    await _pump(tester, source, UserRole.viewer);

    expect(find.textContaining('View-only access'), findsOneWidget);
    expect(find.text('ACKNOWLEDGE ALERT'), findsNothing);
  });

  testWidgets('officers can acknowledge an active alert', (tester) async {
    final source = FakeSource([_alert('a1', AlertStatus.active)]);

    await _pump(tester, source, UserRole.officer);

    final button = find.text('ACKNOWLEDGE ALERT');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();

    expect(source.acknowledged, ['a1']);
  });

  testWidgets('acknowledged alerts offer resolve instead', (tester) async {
    final source = FakeSource([_alert('a1', AlertStatus.acknowledged)]);

    await _pump(tester, source, UserRole.officer);

    await tester.ensureVisible(find.text('RESOLVE INCIDENT'));
    expect(find.text('ACKNOWLEDGE ALERT'), findsNothing);
  });
}

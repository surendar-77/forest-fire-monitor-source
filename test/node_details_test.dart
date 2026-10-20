import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forest_fire_monitor/models/detection_model.dart';
import 'package:forest_fire_monitor/models/live_reading.dart';
import 'package:forest_fire_monitor/models/node_health.dart';
import 'package:forest_fire_monitor/models/node_model.dart';
import 'package:forest_fire_monitor/widgets/node_details_sheet.dart';

final _node = NodeModel(
  id: 'NODE-01',
  name: 'Node 1',
  detection: const DetectionModel(
    deviceId: 'NODE-01',
    temperature: 27,
    humidity: 74,
    fireProbability: 0,
    smokeProbability: 0,
    latitude: 12.97,
    longitude: 77.59,
    riskScore: 12,
    riskLevel: 'LOW',
    alertActive: false,
  ),
  reportedStatus: 'ONLINE',
  hasLocation: true,
  lastSeen: DateTime.now(),
);

Future<void> _show(WidgetTester tester, NodeHealth? health) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NodeDetails(
          node: _node,
          liveStream: Stream.value(const LiveReading()),
          healthStream: Stream.value(health),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows power, Wi-Fi and sensor health from the report', (
    tester,
  ) async {
    await _show(
      tester,
      NodeHealth.fromMap({
        'ts': DateTime.now().millisecondsSinceEpoch,
        'up': 3 * 3600 + 5 * 60,
        'boot': 'brownout',
        'boots': 7,
        'ssid': 'Metro-BoysPG',
        'rssi': -49,
        'ip': '10.0.1.122',
        'net': 'pg',
        'heap': 152000,
        'chipT': 48.0,
        'sent': 990,
        'failed': 10,
        'frames': 120,
        'camAge': 2,
        'mq': 'ok (MQ2 not installed)',
        'dht1': true,
        'dht2': false,
      }),
    );

    expect(find.text('USB / adapter'), findsOneWidget);
    expect(find.text('No battery sensor fitted'), findsOneWidget);
    expect(find.text('3 h 5 min'), findsOneWidget);
    expect(find.text('Power dipped too low'), findsOneWidget);
    expect(find.textContaining('5 V 2 A adapter'), findsOneWidget);
    expect(find.text('Metro-BoysPG'), findsOneWidget);
    expect(find.text('Excellent · -49 dBm'), findsOneWidget);
    expect(find.text('99% delivered'), findsOneWidget);
    expect(find.text('Connected · photo 2s ago'), findsOneWidget);
    expect(find.text('Sensor 1: Working · Sensor 2: No reading'), findsOneWidget);
    expect(find.text('Second smoke sensor not fitted'), findsOneWidget);
  });

  testWidgets('battery and charging appear when a battery sensor is fitted', (
    tester,
  ) async {
    await _show(
      tester,
      NodeHealth.fromMap({
        'ts': DateTime.now().millisecondsSinceEpoch,
        'bat': 64,
        'batV': 3.88,
        'chg': true,
        'boot': 'power-on',
      }),
    );

    expect(find.text('64% · 3.88 V'), findsOneWidget);
    expect(find.text('Charging'), findsWidgets);
    expect(find.text('USB / adapter'), findsNothing);
  });

  testWidgets('explains when the board has not sent a health report', (
    tester,
  ) async {
    await _show(tester, null);
    expect(find.textContaining("hasn't sent a health report"), findsOneWidget);
    expect(find.text('LATEST READINGS'), findsOneWidget);
  });

  test('signal strength words', () {
    expect(NodeHealth.signal(-50).$2, 'Excellent');
    expect(NodeHealth.signal(-70).$2, 'Fair');
    expect(NodeHealth.signal(-90).$2, 'Very weak');
    expect(uptimeLabel(2 * 86400 + 4 * 3600), '2 days 4 h');
    expect(memoryLabel(152000), '148 KB');
  });
}

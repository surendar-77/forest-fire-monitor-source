import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forest_fire_monitor/models/alert_model.dart';
import 'package:forest_fire_monitor/screens/alerts_screen.dart';
import 'package:forest_fire_monitor/utils/friendly.dart';

AlertModel _alert(
  String id, {
  String type = 'FIRE',
  String status = AlertStatus.resolved,
  String? verdict,
  String? outcome,
  double? confidence,
}) {
  return AlertModel.fromFirestore(id, {
    'deviceId': 'NODE-01',
    'type': type,
    'severity': 'HIGH',
    'status': status,
    'detectedAt': DateTime(2026, 10, 20),
    'verdict': ?verdict,
    'outcome': ?outcome,
    if (confidence != null) 'sensorReadings': {'aiConfidence': confidence},
  });
}

void main() {
  test('verdicts and outcomes both count as a judgement', () {
    expect(_alert('a', verdict: AlertVerdict.real).judgedReal, isTrue);
    expect(_alert('b', outcome: AlertOutcome.confirmedFire).judgedReal, isTrue);
    expect(_alert('c', verdict: AlertVerdict.falseAlarm).judgedFalse, isTrue);
    expect(_alert('d', outcome: AlertOutcome.falseAlarm).judgedFalse, isTrue);
    expect(_alert('e').judgedReal || _alert('e').judgedFalse, isFalse);
    expect(_alert('f', confidence: 0.91).aiConfidence, 0.91);
    expect(_alert('g', type: 'SMOKE').isCamera, isTrue);
    expect(_alert('h', type: 'CAMERA_OFFLINE').isCamera, isFalse);
    expect(isSensorProblem('LOW_BATTERY'), isTrue);
    expect(alertTitle('CAMERA_OFFLINE'), 'Camera not sending photos');
  });

  test('suggests a threshold only when it separates real fires from false alarms', () {
    expect(CameraAccuracyCard.separatingThreshold([0.93, 0.88], [0.78, 0.81]), 82);
    expect(CameraAccuracyCard.separatingThreshold([0.80], [0.85]), isNull);
    expect(CameraAccuracyCard.separatingThreshold([], [0.8]), isNull);
  });

  testWidgets('accuracy card shows the share right and a better threshold', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraAccuracyCard(
            alerts: [
              _alert('1', verdict: AlertVerdict.real, confidence: 0.95),
              _alert('2', outcome: AlertOutcome.confirmedFire, confidence: 0.9),
              _alert('3', verdict: AlertVerdict.real, confidence: 0.92),
              _alert('4', verdict: AlertVerdict.falseAlarm, confidence: 0.8),
              _alert('5', type: 'NODE_OFFLINE', outcome: AlertOutcome.falseAlarm),
            ],
          ),
        ),
      ),
    );

    expect(find.text('75%'), findsOneWidget);
    expect(find.textContaining('3 real fires, 1 false alarm'), findsOneWidget);
    expect(find.textContaining('Alerting from 81%'), findsOneWidget);
  });

  testWidgets('no card until a camera alert has been judged', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CameraAccuracyCard(alerts: [_alert('1')])),
      ),
    );
    expect(find.text('Camera AI accuracy'), findsNothing);
  });
}

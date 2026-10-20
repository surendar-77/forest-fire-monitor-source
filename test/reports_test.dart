import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forest_fire_monitor/models/alert_model.dart';
import 'package:forest_fire_monitor/models/node_model.dart';
import 'package:forest_fire_monitor/models/reading_model.dart';
import 'package:forest_fire_monitor/services/report_export_service.dart';
import 'package:forest_fire_monitor/utils/alert_report.dart';
import 'package:forest_fire_monitor/utils/alert_timeline.dart';

final _t0 = DateTime(2026, 10, 20, 10, 0);

AlertModel _alert(String id, Map<String, dynamic> extra) {
  return AlertModel.fromFirestore(id, {
    'deviceId': 'NODE-01',
    'type': 'FIRE',
    'severity': 'HIGH',
    'status': 'RESOLVED',
    'detectedAt': _t0,
    ...extra,
  });
}

void main() {
  test('timeline lists every step in order with response times', () {
    final alert = _alert('a', {
      'pushedAt': _t0.add(const Duration(seconds: 20)),
      'confirmedAt': _t0.add(const Duration(minutes: 2)),
      'ackByName': 'Ravi',
      'ackAt': _t0.add(const Duration(minutes: 4)),
      'verdict': 'REAL',
      'verdictByName': 'Ravi',
      'verdictAt': _t0.add(const Duration(minutes: 5)),
      'resolvedByName': 'Asha',
      'resolvedAt': _t0.add(const Duration(minutes: 80)),
      'outcome': 'CONFIRMED_FIRE',
      'fireServicesNotifiedAt': _t0.add(const Duration(seconds: 30)),
      'fireServicesNotified': ['Ooty station'],
      'sensorReadings': {'aiConfidence': 0.91},
    });
    final events = alertTimeline(alert);
    expect(events.map((e) => e.title).toList(), [
      'Fire seen by camera',
      'Notifications sent',
      'Fire stations told',
      'Fire confirmed, raised to critical',
      'Acknowledged by Ravi',
      'Marked a real fire by Ravi',
      'Resolved by Asha',
    ]);
    expect(events.first.detail, 'Camera AI 91% sure');
    expect(events[4].detail, '4 min after detection');
    expect(events.last.detail, 'Confirmed fire · 1 h 20 min after detection');
    expect(events[2].detail, 'Ooty station');
  });

  test('report counts, medians and false-alarm share', () {
    final alerts = [
      _alert('1', {'ackAt': _t0.add(const Duration(minutes: 2)), 'verdict': 'REAL'}),
      _alert('2', {'ackAt': _t0.add(const Duration(minutes: 6)), 'outcome': 'FALSE_ALARM'}),
      _alert('3', {'ackAt': _t0.add(const Duration(minutes: 10)), 'outcome': 'FALSE_ALARM'}),
      _alert('4', {'type': 'CAMERA_OFFLINE', 'status': 'ACTIVE'}),
      _alert('5', {'detectedAt': _t0.subtract(const Duration(days: 30))}),
    ];
    final r = AlertReport.of(
      alerts,
      from: DateTime(2026, 10, 14),
      to: DateTime(2026, 10, 21),
    );
    expect(r.total, 4);
    expect(r.fireAndSmoke, 3);
    expect(r.sensorProblems, 1);
    expect(r.open, 1);
    expect(r.medianAcknowledge, const Duration(minutes: 6));
    expect(r.falseAlarmPercent, 67);
    expect(r.perDay.length, 7);
    expect(r.perDay.last.value, 4);
    expect(elapsedLabel(const Duration(hours: 26)), '1 day');
  });

  test('readings CSV is oldest first with a header row', () {
    final csv = ReportExportService.buildReadingsCsv([
      ReadingModel.fromReading({
        'ts': DateTime(2026, 10, 20, 10, 1),
        'temperature': 28.4,
        'mq2_1': 770,
        'aiClass': 'Normal',
        'aiConfidence': 0.98,
        'riskScore': 12,
      }),
      ReadingModel.fromReading({
        'ts': DateTime(2026, 10, 20, 10, 0),
        'temperature': 28.1,
        'mq2_1': 765,
      }),
    ]);
    final lines = csv.trim().split(RegExp(r'\r?\n'));
    expect(lines.first, startsWith('Time,Temperature zone 1'));
    expect(lines[1], startsWith('2026-10-20 10:00:00,28.1'));
    expect(lines[2], contains('Normal,98.0,12'));
  });

  test('air at the sensor parses with a colour per status', () {
    final air = LocalAir.fromMap({
      'status': 'GAS',
      'label': 'Gas detected',
      'detail': 'likely LPG',
      'at': DateTime.now(),
    })!;
    expect(air.label, 'Gas detected');
    expect(air.color, Colors.purple.shade600);
    expect(air.isStaleAt(DateTime.now()), isFalse);
    expect(LocalAir.fromMap(null), isNull);
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forest_fire_monitor/models/alert_model.dart';
import 'package:forest_fire_monitor/models/app_user.dart';
import 'package:forest_fire_monitor/models/live_reading.dart';
import 'package:forest_fire_monitor/models/node_model.dart';
import 'package:forest_fire_monitor/models/reading_model.dart';
import 'package:forest_fire_monitor/utils/risk_utils.dart';

void main() {
  group('getRiskLevel', () {
    test('maps score bands', () {
      expect(getRiskLevel(0), 'LOW');
      expect(getRiskLevel(30), 'LOW');
      expect(getRiskLevel(31), 'MODERATE');
      expect(getRiskLevel(60), 'MODERATE');
      expect(getRiskLevel(80), 'HIGH');
      expect(getRiskLevel(81), 'CRITICAL');
    });
  });

  group('AlertModel.fromFirestore', () {
    test('reads pipeline fields leniently', () {
      final alert = AlertModel.fromFirestore('doc1', {
        'deviceId': 'NODE-02',
        'type': 'FIRE',
        'severity': 'CRITICAL',
        'status': 'ACKNOWLEDGED',
        'fireProbability': '91',
        'temperature': 44,
        'detectedAt': Timestamp.fromDate(DateTime.utc(2026, 10, 18, 9)),
        'ackByName': 'Ranger Asha',
        'ackAt': Timestamp.fromDate(DateTime.utc(2026, 10, 18, 9, 4)),
      });

      expect(alert.id, 'doc1');
      expect(alert.deviceId, 'NODE-02');
      expect(alert.fireProbability, 91);
      expect(alert.temperature, 44);
      expect(
        alert.detectedAt.isAtSameMomentAs(DateTime.utc(2026, 10, 18, 9)),
        isTrue,
      );
      expect(alert.acknowledgedBy, 'Ranger Asha');
      expect(alert.isOpen, isTrue);
    });

    test('uses the node location when the alert has 0,0', () {
      final alert = AlertModel.fromFirestore(
        'doc1',
        {'deviceId': 'NODE-01', 'latitude': 0.0, 'longitude': 0.0},
        fallbackLatitude: 12.97,
        fallbackLongitude: 77.59,
      );

      expect(alert.latitude, 12.97);
      expect(alert.longitude, 77.59);
    });

    test('local JSON round-trips including response fields', () {
      final original = AlertModel(
        id: 'a1',
        deviceId: 'SIM-01',
        type: 'CRITICAL FIRE',
        severity: 'CRITICAL',
        fireProbability: 94,
        smokeProbability: 87,
        temperature: 42.5,
        humidity: 28,
        latitude: 13.08,
        longitude: 80.27,
        detectedAt: DateTime(2026, 10, 18, 9),
        status: AlertStatus.resolved,
        acknowledgedBy: 'Simulation',
        acknowledgedAt: DateTime(2026, 10, 18, 9, 2),
        resolvedAt: DateTime(2026, 10, 18, 9, 30),
        notes: 'Test drill',
      );

      final copy = AlertModel.fromJson(original.toJson());

      expect(copy.status, AlertStatus.resolved);
      expect(copy.acknowledgedAt, original.acknowledgedAt);
      expect(copy.resolvedAt, original.resolvedAt);
      expect(copy.notes, 'Test drill');
      expect(copy.isOpen, isFalse);
    });

    test('copyWith changes status without mutating the original', () {
      final alert = AlertModel.fromFirestore('a', {'status': 'ACTIVE'});
      final acked = alert.copyWith(status: AlertStatus.acknowledged);

      expect(alert.status, AlertStatus.active);
      expect(acked.status, AlertStatus.acknowledged);
    });
  });

  group('NodeModel', () {
    final seen = DateTime(2026, 10, 18, 12);

    NodeModel node(Map<String, dynamic> extra) => NodeModel.fromFirestore(
      'NODE-01',
      {'name': 'Ridge', 'lastSeen': Timestamp.fromDate(seen), ...extra},
      fallbackLatitude: 1,
      fallbackLongitude: 2,
    );

    test('status follows lastSeen age', () {
      final n = node({'status': 'ONLINE'});

      expect(
        n.statusAt(seen.add(const Duration(seconds: 30))),
        NodeStatus.online,
      );
      expect(
        n.statusAt(seen.add(const Duration(minutes: 3))),
        NodeStatus.stale,
      );
      expect(
        n.statusAt(seen.add(const Duration(minutes: 11))),
        NodeStatus.offline,
      );
    });

    test('backend OFFLINE wins even if lastSeen is recent', () {
      expect(node({'status': 'OFFLINE'}).statusAt(seen), NodeStatus.offline);
    });

    test('falls back to the default location when none is saved', () {
      final n = node({});

      expect(n.hasLocation, isFalse);
      expect(n.latitude, 1);
      expect(n.longitude, 2);
    });

    test('reads the ML fire-danger rating when present', () {
      final n = node({
        'danger': {
          'probability': 0.61,
          'level': 'HIGH',
          'ffmc': 94.8,
          'isi': 9.67,
          'forecast': false,
        },
      });
      expect(n.danger?.probability, 0.61);
      expect(n.danger?.level, 'HIGH');
      expect(node({}).danger, isNull);
    });

    test('keeps saved coordinates', () {
      final n = node({'latitude': 12.5, 'longitude': 77.1});

      expect(n.hasLocation, isTrue);
      expect(n.latitude, 12.5);
    });
  });

  group('ReadingModel', () {
    test('raw reading uses the higher MQ-2 sensor as smoke', () {
      final r = ReadingModel.fromReading({
        'ts': Timestamp.fromDate(DateTime(2026)),
        'temperature': 30,
        'mq2_1': 300,
        'mq2_2': 520,
      });

      expect(r.smoke, 520);
      expect(r.temperature, 30);
    });

    test('hourly rollup averages sums and keeps peaks', () {
      final r = ReadingModel.fromHourly({
        'hour': Timestamp.fromDate(DateTime(2026)),
        'count': 4,
        'temperatureSum': 120,
        'humiditySum': 200,
        'smokeMax': 610,
        'riskScoreMax': 58,
      });

      expect(r.temperature, 30);
      expect(r.humidity, 50);
      expect(r.smoke, 610);
      expect(r.riskScore, 58);
    });
  });

  group('LiveReading', () {
    test('parses a node sample and detects a paused feed', () {
      final sent = DateTime(2026, 10, 18, 12);
      final r = LiveReading.fromMap({
        't1': 31.4,
        'h1': 48,
        'mq1': 412,
        'mq2': 390,
        'risk': 33,
        'level': 'MODERATE',
        'ai': 'Smoke',
        'conf': 0.81,
        'ts': sent.millisecondsSinceEpoch,
      });

      expect(r.temperature, 31.4);
      expect(r.smoke1, 412);
      expect(r.riskLevel, 'MODERATE');
      expect(r.aiClass, 'Smoke');
      expect(r.temperature2, isNull);
      expect(r.isStaleAt(sent.add(const Duration(seconds: 3))), isFalse);
      expect(r.isStaleAt(sent.add(const Duration(seconds: 15))), isTrue);
    });
  });

  group('UserRole', () {
    test('unknown or missing claims are viewers', () {
      expect(UserRole.fromClaim(null), UserRole.viewer);
      expect(UserRole.fromClaim('superuser'), UserRole.viewer);
      expect(UserRole.fromClaim('officer').canRespondToAlerts, isTrue);
      expect(UserRole.fromClaim('viewer').canRespondToAlerts, isFalse);
    });
  });
}

import 'package:flutter/foundation.dart';

import '../models/alert_model.dart';
import '../models/detection_model.dart';
import 'alert_storage_service.dart';
import 'firestore_service.dart';
import 'notification_service.dart';
import 'monitoring_data_source.dart';
import 'node_config.dart';

class SimulationService extends MonitoringDataSource {
  final AlertStorageService _storage = AlertStorageService();

  final FirestoreService _firestore = FirestoreService();

  DateTime? _lastUpdated;

  DetectionModel _data = DetectionModel(
    deviceId: NodeConfig.nodeId,
    temperature: 25.0,
    humidity: 65.0,
    fireProbability: 3.0,
    smokeProbability: 2.0,
    latitude: 13.0827,
    longitude: 80.2707,
    riskScore: 10,
    riskLevel: 'LOW',
    alertActive: false,
  );

  final List<AlertModel> _alertHistory = [];

  @override
  DetectionModel get data => _data;

  @override
  List<AlertModel> get alertHistory => List.unmodifiable(_alertHistory);

  @override
  List<AlertModel> get activeAlerts {
    return _alertHistory
        .where(
          (alert) => alert.status == 'ACTIVE' || alert.status == 'ACKNOWLEDGED',
        )
        .toList();
  }

  @override
  AlertModel? get currentAlert {
    final active = activeAlerts;
    if (active.isEmpty) return null;
    return active.first;
  }

  @override
  bool get isDataAvailable => true;

  @override
  bool get isLive => false;

  @override
  DateTime? get lastUpdated => _lastUpdated;

  @override
  Future<void> initialize() async {
    final savedHistory = await _storage.loadHistory();

    _alertHistory
      ..clear()
      ..addAll(savedHistory);

    final latestActive = currentAlert;

    if (latestActive != null) {
      _restoreDetectionFromAlert(latestActive);
    } else {
      _setSafeState();
    }

    _lastUpdated = DateTime.now();

    await _storage.saveCurrentAlert(null);

    notifyListeners();
  }

  Future<void> normal() async {
    _setSafeState();
    _lastUpdated = DateTime.now();

    notifyListeners();

    await _saveDetectionToFirebase();
    await _storage.saveHistory(_alertHistory);
  }

  Future<void> smokeDetected() async {
    await _startIncident(
      temperature: 32.0,
      humidity: 45.0,
      fireProbability: 25.0,
      smokeProbability: 72.0,
      riskScore: 50,
      riskLevel: 'MODERATE',
      type: 'SMOKE DETECTED',
    );
  }

  Future<void> highFireRisk() async {
    await _startIncident(
      temperature: 39.0,
      humidity: 34.0,
      fireProbability: 71.0,
      smokeProbability: 76.0,
      riskScore: 72,
      riskLevel: 'HIGH',
      type: 'HIGH FIRE RISK',
    );
  }

  Future<void> criticalFire() async {
    await _startIncident(
      temperature: 42.5,
      humidity: 28.0,
      fireProbability: 94.0,
      smokeProbability: 87.0,
      riskScore: 92,
      riskLevel: 'CRITICAL',
      type: 'CRITICAL FIRE',
    );
  }

  Future<void> _startIncident({
    required double temperature,
    required double humidity,
    required double fireProbability,
    required double smokeProbability,
    required int riskScore,
    required String riskLevel,
    required String type,
  }) async {
    _data = _data.copyWith(
      temperature: temperature,
      humidity: humidity,
      fireProbability: fireProbability,
      smokeProbability: smokeProbability,
      riskScore: riskScore,
      riskLevel: riskLevel,
      alertActive: true,
    );

    _lastUpdated = DateTime.now();

    final alert = AlertModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      deviceId: _data.deviceId,
      type: type,
      severity: riskLevel,
      fireProbability: fireProbability,
      smokeProbability: smokeProbability,
      temperature: temperature,
      humidity: humidity,
      latitude: _data.latitude,
      longitude: _data.longitude,
      detectedAt: DateTime.now(),
      status: 'ACTIVE',
    );

    _alertHistory.insert(0, alert);

    notifyListeners();

    await _saveDetectionToFirebase();

    try {
      await _firestore.saveAlert(alert);
    } catch (error) {
      debugPrint('Firestore alert save failed: $error');
    }

    await _storage.saveHistory(_alertHistory);

    if (riskLevel == 'HIGH' || riskLevel == 'CRITICAL') {
      await NotificationService.showFireAlert(
        severity: riskLevel,
        fireProbability: fireProbability,
        smokeProbability: smokeProbability,
        temperature: temperature,
        humidity: humidity,
      );
    }
  }

  @override
  Future<void> acknowledgeAlert(String alertId) async {
    final alert = _findAlert(alertId);

    if (alert == null || alert.status != 'ACTIVE') {
      return;
    }

    await NotificationService.stopEmergencyAlarm();

    alert.acknowledge();

    _lastUpdated = DateTime.now();

    notifyListeners();

    await _storage.saveHistory(_alertHistory);

    try {
      await _firestore.updateAlertStatus(alertId, 'ACKNOWLEDGED');
    } catch (error) {
      debugPrint('Firestore acknowledge failed: $error');
    }
  }

  @override
  Future<void> resolveIncident(String alertId) async {
    final alert = _findAlert(alertId);

    if (alert == null || alert.status != 'ACKNOWLEDGED') {
      return;
    }

    alert.resolve();

    final remainingActive = activeAlerts;

    if (remainingActive.isNotEmpty) {
      _restoreDetectionFromAlert(remainingActive.first);
    } else {
      _setSafeState();
    }

    _lastUpdated = DateTime.now();

    notifyListeners();

    await _storage.saveHistory(_alertHistory);

    try {
      await _firestore.updateAlertStatus(alertId, 'RESOLVED');
    } catch (error) {
      debugPrint('Firestore resolve failed: $error');
    }

    await _saveDetectionToFirebase();
  }

  Future<void> _saveDetectionToFirebase() async {
    try {
      await _firestore.saveDetection(_data);
      await _firestore.saveDevice(_data);
    } catch (error) {
      debugPrint('Firestore detection save failed: $error');
    }
  }

  AlertModel? _findAlert(String alertId) {
    for (final alert in _alertHistory) {
      if (alert.id == alertId) {
        return alert;
      }
    }

    return null;
  }

  void _restoreDetectionFromAlert(AlertModel alert) {
    _data = _data.copyWith(
      temperature: alert.temperature,
      humidity: alert.humidity,
      fireProbability: alert.fireProbability,
      smokeProbability: alert.smokeProbability,
      latitude: alert.latitude,
      longitude: alert.longitude,
      riskScore: _calculateRiskScore(alert.severity),
      riskLevel: alert.severity,
      alertActive: true,
    );
  }

  void _setSafeState() {
    _data = _data.copyWith(
      temperature: 25.0,
      humidity: 65.0,
      fireProbability: 3.0,
      smokeProbability: 2.0,
      riskScore: 10,
      riskLevel: 'LOW',
      alertActive: false,
    );
  }

  int _calculateRiskScore(String severity) {
    switch (severity) {
      case 'MODERATE':
        return 50;
      case 'HIGH':
        return 72;
      case 'CRITICAL':
        return 92;
      default:
        return 10;
    }
  }
}

import '../models/alert_model.dart';
import '../models/detection_model.dart';
import 'alert_storage_service.dart';
import 'notification_service.dart';
import 'monitoring_data_source.dart';

/// Scripted demo data for training and testing. Everything stays on this
/// device: simulated readings and alerts are never written to Firestore, so
/// they can't reach real officers.
class SimulationService extends MonitoringDataSource {
  static const String nodeId = 'SIM-01';

  final AlertStorageService _storage = AlertStorageService();

  DateTime? _lastUpdated;

  DetectionModel _data = DetectionModel(
    deviceId: nodeId,
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
    return _alertHistory.where((alert) => alert.isOpen).toList();
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
      confirmedAt: type == 'CRITICAL FIRE' ? DateTime.now() : null,
      status: 'ACTIVE',
    );

    _alertHistory.insert(0, alert);

    notifyListeners();

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
    final index = _indexOfAlert(alertId);

    if (index == -1 || _alertHistory[index].status != AlertStatus.active) {
      return;
    }

    await NotificationService.stopEmergencyAlarm();

    _alertHistory[index] = _alertHistory[index].copyWith(
      status: AlertStatus.acknowledged,
      acknowledgedBy: 'Simulation',
      acknowledgedAt: DateTime.now(),
    );

    _lastUpdated = DateTime.now();

    notifyListeners();

    await _storage.saveHistory(_alertHistory);
  }

  @override
  Future<void> resolveIncident(String alertId) async {
    final index = _indexOfAlert(alertId);

    if (index == -1 ||
        _alertHistory[index].status != AlertStatus.acknowledged) {
      return;
    }

    _alertHistory[index] = _alertHistory[index].copyWith(
      status: AlertStatus.resolved,
      resolvedBy: 'Simulation',
      resolvedAt: DateTime.now(),
    );

    final remainingActive = activeAlerts;

    if (remainingActive.isNotEmpty) {
      _restoreDetectionFromAlert(remainingActive.first);
    } else {
      _setSafeState();
    }

    _lastUpdated = DateTime.now();

    notifyListeners();

    await _storage.saveHistory(_alertHistory);
  }

  int _indexOfAlert(String alertId) {
    return _alertHistory.indexWhere((alert) => alert.id == alertId);
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

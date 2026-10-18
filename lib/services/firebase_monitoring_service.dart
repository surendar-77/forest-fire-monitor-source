import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/alert_model.dart';
import '../models/detection_model.dart';
import 'location_service.dart';
import 'monitoring_data_source.dart';
import 'node_config.dart';
import 'notification_service.dart';

class FirebaseMonitoringService extends MonitoringDataSource {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final LocationService _locationService = LocationService();

  static const String deviceId = NodeConfig.nodeId;

  DateTime? _lastUpdated;

  DetectionModel _data = const DetectionModel(
    deviceId: deviceId,
    temperature: 25.0,
    humidity: 65.0,
    fireProbability: 0.0,
    smokeProbability: 0.0,
    latitude: 13.0827,
    longitude: 80.2707,
    riskScore: 0,
    riskLevel: 'LOW',
    alertActive: false,
  );

  final List<AlertModel> _alertHistory = [];

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _deviceSubscription;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _alertsSubscription;

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

    if (active.isEmpty) {
      return null;
    }

    active.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));

    return active.first;
  }

  @override
  bool get isDataAvailable => _lastUpdated != null;

  @override
  bool get isLive => true;

  @override
  DateTime? get lastUpdated => _lastUpdated;

  @override
  Future<void> initialize() async {
    await _cancelSubscriptions();

    final nodeLatitude = await _locationService.getLatitude();

    final nodeLongitude = await _locationService.getLongitude();

    _data = _data.copyWith(latitude: nodeLatitude, longitude: nodeLongitude);

    _deviceSubscription = _firestore
        .collection('devices')
        .doc(deviceId)
        .snapshots()
        .listen(
          _handleDeviceSnapshot,
          onError: (error) {
            debugPrint('Firebase device stream error: $error');
          },
        );

    _alertsSubscription = _firestore
        .collection('alerts')
        .orderBy('detectedAt', descending: true)
        .snapshots()
        .listen(
          _handleAlertsSnapshot,
          onError: (error) {
            debugPrint('Firebase alerts stream error: $error');
          },
        );
  }

  void _handleDeviceSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (!snapshot.exists) {
      debugPrint('Firebase device document not found: $deviceId');
      return;
    }

    final data = snapshot.data();

    if (data == null) {
      return;
    }

    _data = DetectionModel(
      deviceId: _stringValue(data['deviceId'], deviceId),
      temperature: _doubleValue(data['temperature'], 25.0),
      humidity: _doubleValue(data['humidity'], 65.0),
      fireProbability: _doubleValue(data['fireProbability'], 0.0),
      smokeProbability: _doubleValue(data['smokeProbability'], 0.0),
      latitude: _data.latitude,
      longitude: _data.longitude,
      riskScore: _intValue(data['riskScore'], 0),
      riskLevel: _stringValue(data['riskLevel'], 'LOW'),
      alertActive: _boolValue(data['alertActive'], activeAlerts.isNotEmpty),
    );

    _lastUpdated = DateTime.now();

    notifyListeners();
  }

  void _handleAlertsSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final alerts = snapshot.docs.map((document) {
      final data = document.data();

      return AlertModel(
        id: _stringValue(data['alertId'], document.id),
        deviceId: _stringValue(data['deviceId'], deviceId),
        type: _stringValue(data['type'], 'FIRE ALERT'),
        severity: _stringValue(data['severity'], 'LOW'),
        fireProbability: _doubleValue(data['fireProbability'], 0.0),
        smokeProbability: _doubleValue(data['smokeProbability'], 0.0),
        temperature: _doubleValue(data['temperature'], 0.0),
        humidity: _doubleValue(data['humidity'], 0.0),
        latitude: _data.latitude,
        longitude: _data.longitude,
        detectedAt: _dateTimeValue(data['detectedAt']),
        status: _stringValue(data['status'], 'ACTIVE'),
      );
    }).toList();

    _alertHistory
      ..clear()
      ..addAll(alerts);

    notifyListeners();
  }

  @override
  Future<void> acknowledgeAlert(String alertId) async {
    await NotificationService.stopEmergencyAlarm();

    await _firestore.collection('alerts').doc(alertId).update({
      'status': 'ACKNOWLEDGED',
    });
  }

  @override
  Future<void> resolveIncident(String alertId) async {
    await _firestore.collection('alerts').doc(alertId).update({
      'status': 'RESOLVED',
    });
  }

  double _doubleValue(dynamic value, double fallback) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  int _intValue(dynamic value, int fallback) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool _boolValue(dynamic value, bool fallback) {
    if (value is bool) {
      return value;
    }

    return fallback;
  }

  String _stringValue(dynamic value, String fallback) {
    if (value == null) {
      return fallback;
    }

    final result = value.toString();

    return result.isEmpty ? fallback : result;
  }

  DateTime _dateTimeValue(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    final parsed = DateTime.tryParse(value?.toString() ?? '');

    return parsed ?? DateTime.now();
  }

  Future<void> _cancelSubscriptions() async {
    await _deviceSubscription?.cancel();
    await _alertsSubscription?.cancel();

    _deviceSubscription = null;
    _alertsSubscription = null;
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }
}

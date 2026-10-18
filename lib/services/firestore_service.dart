import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/alert_model.dart';
import '../models/detection_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> saveDetection(DetectionModel data) async {
    await _firestore.collection('detections').add({
      'deviceId': data.deviceId,
      'timestamp': FieldValue.serverTimestamp(),
      'latitude': data.latitude,
      'longitude': data.longitude,
      'temperature': data.temperature,
      'humidity': data.humidity,
      'fireProbability': data.fireProbability,
      'smokeProbability': data.smokeProbability,
      'riskScore': data.riskScore,
      'riskLevel': data.riskLevel,
      'alertActive': data.alertActive,
    });
  }

  Future<void> saveAlert(AlertModel alert) async {
    await _firestore.collection('alerts').doc(alert.id).set({
      'alertId': alert.id,
      'deviceId': alert.deviceId,
      'type': alert.type,
      'severity': alert.severity,
      'status': alert.status,
      'fireProbability': alert.fireProbability,
      'smokeProbability': alert.smokeProbability,
      'temperature': alert.temperature,
      'humidity': alert.humidity,
      'latitude': alert.latitude,
      'longitude': alert.longitude,
      'detectedAt': Timestamp.fromDate(alert.detectedAt),
    });
  }

  Future<void> updateAlertStatus(String alertId, String status) async {
    await _firestore.collection('alerts').doc(alertId).update({
      'status': status,
    });
  }

  Future<void> saveDevice(DetectionModel data) async {
    await _firestore.collection('devices').doc(data.deviceId).set({
      'deviceId': data.deviceId,
      'name': data.deviceId,
      'status': 'ONLINE',
      'lastSeen': FieldValue.serverTimestamp(),
      'latitude': data.latitude,
      'longitude': data.longitude,
      'temperature': data.temperature,
      'humidity': data.humidity,
      'fireProbability': data.fireProbability,
      'smokeProbability': data.smokeProbability,
      'riskScore': data.riskScore,
      'riskLevel': data.riskLevel,
      'alertActive': data.alertActive,
    }, SetOptions(merge: true));
  }
}

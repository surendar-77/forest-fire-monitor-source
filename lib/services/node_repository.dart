import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/alert_model.dart';
import '../models/node_model.dart';
import 'location_service.dart';
import 'notification_service.dart';

/// Live view of every monitoring node (`devices`) and recent `alerts`.
/// One instance is shared by all screens; [LiveNodeSource] narrows it to a
/// single node for the existing per-node screens.
class NodeRepository extends ChangeNotifier {
  NodeRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  static const int alertLimit = 200;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final LocationService _locationService = LocationService();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _nodesSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _alertsSubscription;
  Timer? _statusTicker;

  double _fallbackLatitude = LocationService.defaultLatitude;
  double _fallbackLongitude = LocationService.defaultLongitude;

  Map<String, NodeModel> _nodes = {};
  List<AlertModel> _alerts = [];

  bool _nodesLoaded = false;
  bool _fromCache = false;
  DateTime? _lastSynced;
  Object? _error;

  bool get isStarted => _nodesSubscription != null;

  bool get isLoaded => _nodesLoaded;

  /// True while the data on screen came from the offline cache rather than
  /// the server.
  bool get isFromCache => _fromCache;

  DateTime? get lastSynced => _lastSynced;

  Object? get error => _error;

  /// Nodes ordered by risk, highest first, then by name.
  List<NodeModel> get nodes {
    final list = _nodes.values.toList()
      ..sort((a, b) {
        final byRisk = b.detection.riskScore.compareTo(a.detection.riskScore);
        return byRisk != 0 ? byRisk : a.name.compareTo(b.name);
      });

    return list;
  }

  NodeModel? node(String nodeId) => _nodes[nodeId];

  List<AlertModel> get alerts => List.unmodifiable(_alerts);

  List<AlertModel> alertsForNode(String nodeId) {
    return _alerts.where((alert) => alert.deviceId == nodeId).toList();
  }

  List<AlertModel> get openAlerts =>
      _alerts.where((alert) => alert.isOpen).toList();

  Future<void> start() async {
    if (isStarted) {
      return;
    }

    _fallbackLatitude = await _locationService.getLatitude();
    _fallbackLongitude = await _locationService.getLongitude();

    _nodesSubscription = _firestore
        .collection('devices')
        .snapshots(includeMetadataChanges: true)
        .listen(_handleNodes, onError: _handleError);

    _alertsSubscription = _firestore
        .collection('alerts')
        .orderBy('detectedAt', descending: true)
        .limit(alertLimit)
        .snapshots(includeMetadataChanges: true)
        .listen(_handleAlerts, onError: _handleError);

    // Node status depends on the clock (lastSeen age), so re-evaluate it
    // periodically even when no new data arrives.
    _statusTicker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => notifyListeners(),
    );
  }

  Future<void> stop() async {
    await _nodesSubscription?.cancel();
    await _alertsSubscription?.cancel();
    _statusTicker?.cancel();

    _nodesSubscription = null;
    _alertsSubscription = null;
    _statusTicker = null;

    _nodes = {};
    _alerts = [];
    _nodesLoaded = false;
    _error = null;

    notifyListeners();
  }

  void _handleNodes(QuerySnapshot<Map<String, dynamic>> snapshot) {
    _nodes = {
      for (final doc in snapshot.docs)
        doc.id: NodeModel.fromFirestore(
          doc.id,
          doc.data(),
          fallbackLatitude: _fallbackLatitude,
          fallbackLongitude: _fallbackLongitude,
        ),
    };

    _nodesLoaded = true;
    _updateSyncState(snapshot.metadata);
    notifyListeners();
  }

  void _handleAlerts(QuerySnapshot<Map<String, dynamic>> snapshot) {
    _alerts = snapshot.docs.map((doc) {
      final data = doc.data();
      final node = _nodes[data['deviceId']?.toString()];

      return AlertModel.fromFirestore(
        doc.id,
        data,
        fallbackLatitude: node?.latitude ?? _fallbackLatitude,
        fallbackLongitude: node?.longitude ?? _fallbackLongitude,
      );
    }).toList();

    _updateSyncState(snapshot.metadata);
    notifyListeners();
  }

  void _updateSyncState(SnapshotMetadata metadata) {
    _fromCache = metadata.isFromCache;
    _error = null;

    if (!metadata.isFromCache) {
      _lastSynced = DateTime.now();
    }
  }

  void _handleError(Object error) {
    debugPrint('NodeRepository stream error: $error');
    _error = error;
    notifyListeners();
  }

  // ----------------------------------------------------------
  // ALERT ACTIONS (officers and admins; enforced by security rules)
  // ----------------------------------------------------------

  Future<void> acknowledgeAlert(String alertId) async {
    await NotificationService.stopEmergencyAlarm();

    final user = _auth.currentUser;

    await _firestore.collection('alerts').doc(alertId).update({
      'status': AlertStatus.acknowledged,
      'ackBy': user?.uid,
      'ackByName': user?.displayName ?? user?.email,
      'ackAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resolveIncident(String alertId, {String? notes}) async {
    final user = _auth.currentUser;

    await _firestore.collection('alerts').doc(alertId).update({
      'status': AlertStatus.resolved,
      'resolvedBy': user?.uid,
      'resolvedByName': user?.displayName ?? user?.email,
      'resolvedAt': FieldValue.serverTimestamp(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
  }

  // ----------------------------------------------------------
  // NODE SETUP (administrators; enforced by security rules)
  // ----------------------------------------------------------

  Future<void> updateNodeLocation(
    String nodeId, {
    required String name,
    required double latitude,
    required double longitude,
  }) {
    return _firestore.collection('devices').doc(nodeId).set({
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
    }, SetOptions(merge: true));
  }

  @override
  void dispose() {
    _nodesSubscription?.cancel();
    _alertsSubscription?.cancel();
    _statusTicker?.cancel();
    super.dispose();
  }
}

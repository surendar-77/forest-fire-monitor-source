import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/alert_model.dart';
import '../models/node_model.dart';
import '../utils/firestore_parse.dart';
import 'location_service.dart';
import 'notification_service.dart';

/// Live view of every monitoring node (`devices`) and recent `alerts`.
/// One instance is shared by all screens; [LiveNodeSource] narrows it to a
/// single node for the existing per-node screens.
class NodeRepository extends ChangeNotifier {
  NodeRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  /// Newest alerts kept live on screen. Each app start reads up to this many
  /// documents, so it is kept modest for the free plan's daily read quota.
  static const int alertLimit = 100;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final LocationService _locationService = LocationService();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _nodesSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _alertsSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _backendSubscription;
  Timer? _statusTicker;

  double _fallbackLatitude = LocationService.defaultLatitude;
  double _fallbackLongitude = LocationService.defaultLongitude;

  Map<String, NodeModel> _nodes = {};
  List<AlertModel> _alerts = [];

  bool _nodesLoaded = false;
  final Set<String> _seenAlertIds = {};

  /// Newly arrived urgent alert (camera fire/smoke, or High/Critical) for
  /// the in-app pop-up. Only alerts that appear after the app has loaded.
  final ValueNotifier<AlertModel?> incomingAlert = ValueNotifier(null);
  bool _backendLoaded = false;
  DateTime? _backendHeartbeat;
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

  /// The backend service (backend/) writes a heartbeat every 5 minutes.
  static const Duration backendDownAfter = Duration(minutes: 15);

  DateTime? get backendHeartbeat => _backendHeartbeat;

  /// True when the service that polls sensors and sends push alerts appears
  /// to have stopped, so alerts may not arrive.
  bool get isBackendDown {
    if (!_backendLoaded) {
      return false;
    }

    final heartbeat = _backendHeartbeat;

    return heartbeat == null ||
        DateTime.now().difference(heartbeat) > backendDownAfter;
  }

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

    // The saved default map location is only a fallback for nodes without
    // coordinates: never let reading it (device storage, which can fail on
    // some Android builds) stop the data from loading.
    try {
      _fallbackLatitude = await _locationService.getLatitude().timeout(
        const Duration(seconds: 2),
      );
      _fallbackLongitude = await _locationService.getLongitude().timeout(
        const Duration(seconds: 2),
      );
    } catch (error) {
      debugPrint('Default location unavailable, using built-in: $error');
    }

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

    _backendSubscription = _firestore.doc('status/backend').snapshots().listen((
      snapshot,
    ) {
      _backendLoaded = true;
      _backendHeartbeat = parseDateTimeOrNull(
        snapshot.data()?['lastHeartbeat'],
      );
      notifyListeners();
    }, onError: _handleError);

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
    await _backendSubscription?.cancel();
    _statusTicker?.cancel();

    _nodesSubscription = null;
    _alertsSubscription = null;
    _backendSubscription = null;
    _statusTicker = null;
    _backendLoaded = false;
    _backendHeartbeat = null;

    _nodes = {};
    _alerts = [];
    _nodesLoaded = false;
    _seenAlertIds.clear();
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

    // Pop up urgent alerts that nobody has handled yet and that are under
    // 15 minutes old: new ones as they arrive, and on first load the newest
    // one still waiting (so opening the app during a fire shows it).
    // Alerts arrive newest first, so the first match is the one to show.
    AlertModel? toShow;
    for (final alert in _alerts) {
      final isNew = _seenAlertIds.add(alert.id);
      if (!isNew || snapshot.metadata.isFromCache) continue;
      final urgent =
          alert.type == 'FIRE' ||
          alert.type == 'SMOKE' ||
          alert.severity == 'HIGH' ||
          alert.severity == 'CRITICAL';
      final recent = DateTime.now().difference(alert.detectedAt).inMinutes < 15;
      if (alert.status == AlertStatus.active && urgent && recent) {
        toShow ??= alert;
      }
    }
    if (toShow != null) incomingAlert.value = toShow;

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

  Future<void> resolveIncident(
    String alertId, {
    String? notes,
    String? outcome,
  }) async {
    final user = _auth.currentUser;

    await _firestore.collection('alerts').doc(alertId).update({
      'status': AlertStatus.resolved,
      'resolvedBy': user?.uid,
      'resolvedByName': user?.displayName ?? user?.email,
      'resolvedAt': FieldValue.serverTimestamp(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      'outcome': ?outcome,
    });
  }

  /// "Real fire" keeps the alert open and marks it handled; "False alarm"
  /// also resolves it, recorded as a false alarm.
  Future<void> markVerdict(AlertModel alert, String verdict) async {
    final user = _auth.currentUser;
    final doc = _firestore.collection('alerts').doc(alert.id);

    await doc.update({
      'verdict': verdict,
      'verdictBy': user?.uid,
      'verdictByName': user?.displayName ?? user?.email,
      'verdictAt': FieldValue.serverTimestamp(),
    });
    if (alert.status == AlertStatus.active) await acknowledgeAlert(alert.id);
    if (verdict == AlertVerdict.falseAlarm) {
      await resolveIncident(
        alert.id,
        notes: 'Marked as a false alarm.',
        outcome: AlertOutcome.falseAlarm,
      );
    }
  }

  // ----------------------------------------------------------
  // NODE SETUP (administrators; enforced by security rules)
  // ----------------------------------------------------------

  /// Next free id like NODE-02.
  String suggestNodeId() {
    var highest = 0;
    for (final id in _nodes.keys) {
      final match = RegExp(r'^NODE-(\d+)$').firstMatch(id);
      if (match != null) {
        final n = int.parse(match.group(1)!);
        if (n > highest) highest = n;
      }
    }
    return 'NODE-${(highest + 1).toString().padLeft(2, '0')}';
  }

  /// Asks the backend to create a sensor and its secret key. Waits for the
  /// backend (it checks requests every minute) and returns the key, which
  /// goes into the new board's firmware.
  Future<String> addSensor({
    required String nodeId,
    required String name,
    String? zone,
    String? terrain,
    String? channelId,
    String? readApiKey,
  }) async {
    String? clean(String? v) =>
        v == null || v.trim().isEmpty ? null : v.trim();
    final request = await _firestore.collection('adminRequests').add({
      'kind': 'addNode',
      'requestedBy': _auth.currentUser?.uid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'nodeId': nodeId.trim().toUpperCase(),
      'name': name.trim(),
      'zone': ?clean(zone),
      'terrain': ?clean(terrain),
      'channelId': ?clean(channelId),
      'readApiKey': ?clean(readApiKey),
    });

    final result = await request
        .snapshots()
        .map((snapshot) => snapshot.data())
        .firstWhere((data) => data != null && data['status'] != 'pending')
        .timeout(
          const Duration(minutes: 3),
          onTimeout: () => throw TimeoutException(
            'The backend did not answer. Check that it is running.',
          ),
        );
    if (result!['status'] != 'done') {
      throw Exception(result['message'] ?? 'The sensor could not be added.');
    }
    return result['nodeKey'] as String;
  }

  Future<void> updateNodeLocation(
    String nodeId, {
    String? name,
    required double latitude,
    required double longitude,
  }) {
    return _firestore.collection('devices').doc(nodeId).set({
      'name': ?name,
      'latitude': latitude,
      'longitude': longitude,
    }, SetOptions(merge: true));
  }

  Future<void> updateNodeTerrain(String nodeId, String terrain) {
    return _firestore.collection('devices').doc(nodeId).set({
      'terrain': terrain,
    }, SetOptions(merge: true));
  }

  @override
  void dispose() {
    _nodesSubscription?.cancel();
    _alertsSubscription?.cancel();
    _backendSubscription?.cancel();
    _statusTicker?.cancel();
    super.dispose();
  }
}

import '../models/alert_model.dart';
import '../models/detection_model.dart';
import '../models/node_model.dart';
import 'monitoring_data_source.dart';
import 'node_repository.dart';

/// Live Firestore data for one node, adapted to [MonitoringDataSource] so the
/// dashboard, map, monitor and alerts screens work unchanged.
class LiveNodeSource extends MonitoringDataSource {
  LiveNodeSource({required this.repository, required this.nodeId}) {
    repository.addListener(notifyListeners);
  }

  final NodeRepository repository;
  final String nodeId;

  NodeModel? get node => repository.node(nodeId);

  @override
  DetectionModel get data {
    return node?.detection ??
        DetectionModel(
          deviceId: nodeId,
          temperature: 0,
          humidity: 0,
          fireProbability: 0,
          smokeProbability: 0,
          latitude: 0,
          longitude: 0,
          riskScore: 0,
          riskLevel: 'LOW',
          alertActive: false,
        );
  }

  @override
  List<AlertModel> get alertHistory => repository.alertsForNode(nodeId);

  @override
  List<AlertModel> get activeAlerts =>
      alertHistory.where((alert) => alert.isOpen).toList();

  @override
  AlertModel? get currentAlert {
    final active = activeAlerts;

    return active.isEmpty ? null : active.first;
  }

  @override
  bool get isDataAvailable => node?.lastSeen != null;

  @override
  bool get isLive => true;

  @override
  DateTime? get lastUpdated => node?.lastSeen;

  @override
  Future<void> initialize() => repository.start();

  @override
  Future<void> acknowledgeAlert(String alertId) {
    return repository.acknowledgeAlert(alertId);
  }

  @override
  Future<void> resolveIncident(String alertId) {
    return repository.resolveIncident(alertId);
  }

  @override
  void dispose() {
    repository.removeListener(notifyListeners);
    super.dispose();
  }
}

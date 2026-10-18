import 'package:flutter/foundation.dart';

import 'live_node_source.dart';
import 'monitoring_data_source.dart';
import 'node_repository.dart';
import 'simulation_service.dart';

enum DataSourceMode { simulation, live }

/// Chooses what the per-node screens show: live data for the selected node
/// (the default) or the on-device simulation (administrators only).
class DataSourceController extends ChangeNotifier {
  DataSourceController({required this.repository}) {
    repository.addListener(_handleRepositoryChange);
  }

  final NodeRepository repository;

  final SimulationService _simulationService = SimulationService();

  DataSourceMode _mode = DataSourceMode.live;

  String? _selectedNodeId;
  LiveNodeSource? _liveSource;

  bool _simulationReady = false;

  DataSourceMode get mode => _mode;

  bool get isSimulation => _mode == DataSourceMode.simulation;

  bool get isLive => _mode == DataSourceMode.live;

  SimulationService get simulationService => _simulationService;

  String? get selectedNodeId => _selectedNodeId;

  MonitoringDataSource get source {
    if (isSimulation) {
      return _simulationService;
    }

    return _liveSourceFor(_selectedNodeId ?? '');
  }

  Future<void> initialize() async {
    await repository.start();
    _handleRepositoryChange();
  }

  void selectNode(String nodeId) {
    if (_selectedNodeId == nodeId && isLive) {
      return;
    }

    _selectedNodeId = nodeId;
    _mode = DataSourceMode.live;
    notifyListeners();
  }

  Future<void> switchToLive() async {
    if (isLive) {
      return;
    }

    _mode = DataSourceMode.live;
    notifyListeners();
  }

  Future<void> switchToSimulation() async {
    if (isSimulation) {
      return;
    }

    if (!_simulationReady) {
      await _simulationService.initialize();
      _simulationReady = true;
    }

    _mode = DataSourceMode.simulation;
    notifyListeners();
  }

  LiveNodeSource _liveSourceFor(String nodeId) {
    final existing = _liveSource;

    if (existing != null && existing.nodeId == nodeId) {
      return existing;
    }

    existing?.dispose();

    return _liveSource = LiveNodeSource(repository: repository, nodeId: nodeId);
  }

  /// Keeps a valid node selected as nodes appear or disappear.
  void _handleRepositoryChange() {
    final nodes = repository.nodes;

    if (nodes.isEmpty) {
      return;
    }

    final selected = _selectedNodeId;

    if (selected == null || repository.node(selected) == null) {
      _selectedNodeId = nodes.first.id;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    repository.removeListener(_handleRepositoryChange);
    _liveSource?.dispose();
    _simulationService.dispose();
    super.dispose();
  }
}

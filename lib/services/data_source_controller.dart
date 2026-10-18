import 'package:flutter/foundation.dart';

import 'firebase_monitoring_service.dart';
import 'monitoring_data_source.dart';
import 'simulation_service.dart';

enum DataSourceMode { simulation, live }

class DataSourceController extends ChangeNotifier {
  final SimulationService _simulationService = SimulationService();

  final FirebaseMonitoringService _firebaseService =
      FirebaseMonitoringService();

  DataSourceMode _mode = DataSourceMode.simulation;

  MonitoringDataSource get source {
    if (_mode == DataSourceMode.live) {
      return _firebaseService;
    }

    return _simulationService;
  }

  DataSourceMode get mode => _mode;

  bool get isSimulation => _mode == DataSourceMode.simulation;

  bool get isLive => _mode == DataSourceMode.live;

  Future<void> initialize() async {
    await _simulationService.initialize();

    notifyListeners();
  }

  Future<void> switchToLive() async {
    if (_mode == DataSourceMode.live) {
      return;
    }

    await _firebaseService.initialize();

    _mode = DataSourceMode.live;

    notifyListeners();
  }

  void switchToSimulation() {
    if (_mode == DataSourceMode.simulation) {
      return;
    }

    _mode = DataSourceMode.simulation;

    notifyListeners();
  }

  SimulationService get simulationService => _simulationService;

  @override
  void dispose() {
    _simulationService.dispose();
    _firebaseService.dispose();

    super.dispose();
  }
}

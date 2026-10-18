import 'package:flutter/foundation.dart';

import '../models/alert_model.dart';
import '../models/detection_model.dart';

abstract class MonitoringDataSource extends ChangeNotifier {
  DetectionModel get data;

  List<AlertModel> get alertHistory;

  List<AlertModel> get activeAlerts;

  AlertModel? get currentAlert;

  bool get isDataAvailable;

  bool get isLive;

  DateTime? get lastUpdated;

  Future<void> initialize();

  Future<void> acknowledgeAlert(String alertId);

  Future<void> resolveIncident(String alertId);
}

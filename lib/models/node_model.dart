import '../utils/firestore_parse.dart';
import 'detection_model.dart';

enum NodeStatus { online, stale, offline, unknown }

/// Today's fire-danger rating from the backend's ML model
/// (`devices/{id}.danger`), based on standard noon weather at the node.
class FireDanger {
  final double probability;
  final String level;
  final double? ffmc;
  final double? isi;
  final double? temperature;
  final double? humidity;
  final double? wind;
  final double? rain24h;
  final String? forDate;
  final bool forecast;
  final DateTime? updatedAt;
  final String? model;

  const FireDanger({
    required this.probability,
    required this.level,
    this.ffmc,
    this.isi,
    this.temperature,
    this.humidity,
    this.wind,
    this.rain24h,
    this.forDate,
    this.forecast = false,
    this.updatedAt,
    this.model,
  });

  static FireDanger? fromMap(dynamic value) {
    if (value is! Map) return null;
    final probability = parseDoubleOrNull(value['probability']);
    if (probability == null) return null;

    return FireDanger(
      probability: probability,
      level: parseString(value['level'], 'LOW'),
      ffmc: parseDoubleOrNull(value['ffmc']),
      isi: parseDoubleOrNull(value['isi']),
      temperature: parseDoubleOrNull(value['temperature']),
      humidity: parseDoubleOrNull(value['humidity']),
      wind: parseDoubleOrNull(value['wind']),
      rain24h: parseDoubleOrNull(value['rain24h']),
      forDate: parseStringOrNull(value['forDate']),
      forecast: parseBool(value['forecast'], false),
      updatedAt: parseDateTimeOrNull(value['updatedAt']),
      model: parseStringOrNull(value['model']),
    );
  }
}

/// A monitoring node, read from `devices/{nodeId}`.
class NodeModel {
  /// After this long without data the node is shown as stale, even if the
  /// backend has not updated `status` yet.
  static const Duration staleAfter = Duration(minutes: 2);
  static const Duration offlineAfter = Duration(minutes: 10);

  final String id;
  final String name;
  final String? zone;
  final DetectionModel detection;
  final DateTime? lastSeen;
  final String reportedStatus;
  final bool hasLocation;
  final FireDanger? danger;

  const NodeModel({
    required this.id,
    required this.name,
    required this.detection,
    required this.reportedStatus,
    required this.hasLocation,
    this.zone,
    this.lastSeen,
    this.danger,
  });

  double get latitude => detection.latitude;
  double get longitude => detection.longitude;

  NodeStatus statusAt(DateTime now) {
    if (reportedStatus == 'OFFLINE') {
      return NodeStatus.offline;
    }

    final seen = lastSeen;

    if (seen == null) {
      return NodeStatus.unknown;
    }

    final age = now.difference(seen);

    if (age > offlineAfter) {
      return NodeStatus.offline;
    }

    if (age > staleAfter || reportedStatus == 'STALE') {
      return NodeStatus.stale;
    }

    return NodeStatus.online;
  }

  NodeStatus get status => statusAt(DateTime.now());

  factory NodeModel.fromFirestore(
    String documentId,
    Map<String, dynamic> data, {
    double fallbackLatitude = 0,
    double fallbackLongitude = 0,
  }) {
    final latitude = parseDoubleOrNull(data['latitude']);
    final longitude = parseDoubleOrNull(data['longitude']);
    final hasLocation =
        latitude != null &&
        longitude != null &&
        (latitude != 0 || longitude != 0);

    final detection = DetectionModel.fromFirestore(
      documentId,
      data,
      fallbackLatitude: fallbackLatitude,
      fallbackLongitude: fallbackLongitude,
    );

    return NodeModel(
      id: documentId,
      name: parseString(data['name'], documentId),
      zone: parseStringOrNull(data['zone']),
      detection: hasLocation
          ? detection
          : detection.copyWith(
              latitude: fallbackLatitude,
              longitude: fallbackLongitude,
            ),
      lastSeen: parseDateTimeOrNull(data['lastSeen']),
      reportedStatus: parseString(data['status'], 'UNKNOWN').toUpperCase(),
      hasLocation: hasLocation,
      danger: FireDanger.fromMap(data['danger']),
    );
  }
}

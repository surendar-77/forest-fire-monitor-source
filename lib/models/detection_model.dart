import '../utils/firestore_parse.dart';

class DetectionModel {
  final String deviceId;

  final double temperature;
  final double humidity;

  final double fireProbability;
  final double smokeProbability;

  final double latitude;
  final double longitude;

  final int riskScore;
  final String riskLevel;

  final bool alertActive;

  const DetectionModel({
    required this.deviceId,
    required this.temperature,
    required this.humidity,
    required this.fireProbability,
    required this.smokeProbability,
    required this.latitude,
    required this.longitude,
    required this.riskScore,
    required this.riskLevel,
    required this.alertActive,
  });

  /// Reads the latest readings from a `devices/{nodeId}` document.
  factory DetectionModel.fromFirestore(
    String documentId,
    Map<String, dynamic> data, {
    double fallbackLatitude = 0,
    double fallbackLongitude = 0,
  }) {
    return DetectionModel(
      deviceId: parseString(data['deviceId'], documentId),
      temperature: parseDouble(data['temperature'], 0),
      humidity: parseDouble(data['humidity'], 0),
      fireProbability: parseDouble(data['fireProbability'], 0),
      smokeProbability: parseDouble(data['smokeProbability'], 0),
      latitude: parseDouble(data['latitude'], fallbackLatitude),
      longitude: parseDouble(data['longitude'], fallbackLongitude),
      riskScore: parseInt(data['riskScore'], 0),
      riskLevel: parseString(data['riskLevel'], 'LOW'),
      alertActive: parseBool(data['alertActive'], false),
    );
  }

  DetectionModel copyWith({
    String? deviceId,
    double? temperature,
    double? humidity,
    double? fireProbability,
    double? smokeProbability,
    double? latitude,
    double? longitude,
    int? riskScore,
    String? riskLevel,
    bool? alertActive,
  }) {
    return DetectionModel(
      deviceId: deviceId ?? this.deviceId,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      fireProbability: fireProbability ?? this.fireProbability,
      smokeProbability: smokeProbability ?? this.smokeProbability,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      riskScore: riskScore ?? this.riskScore,
      riskLevel: riskLevel ?? this.riskLevel,
      alertActive: alertActive ?? this.alertActive,
    );
  }
}

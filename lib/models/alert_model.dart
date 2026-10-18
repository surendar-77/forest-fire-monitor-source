class AlertModel {
  final String id;
  final String deviceId;
  final String type;
  final String severity;

  final double fireProbability;
  final double smokeProbability;

  final double temperature;
  final double humidity;

  final double latitude;
  final double longitude;

  final DateTime detectedAt;

  String status;

  AlertModel({
    required this.id,
    required this.deviceId,
    required this.type,
    required this.severity,
    required this.fireProbability,
    required this.smokeProbability,
    required this.temperature,
    required this.humidity,
    required this.latitude,
    required this.longitude,
    required this.detectedAt,
    required this.status,
  });

  // ----------------------------------------------------------
  // ACKNOWLEDGE
  // ----------------------------------------------------------

  void acknowledge() {
    status = 'ACKNOWLEDGED';
  }

  // ----------------------------------------------------------
  // RESOLVE
  // ----------------------------------------------------------

  void resolve() {
    status = 'RESOLVED';
  }

  // ----------------------------------------------------------
  // CONVERT TO JSON
  // ----------------------------------------------------------

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceId': deviceId,
      'type': type,
      'severity': severity,
      'fireProbability': fireProbability,
      'smokeProbability': smokeProbability,
      'temperature': temperature,
      'humidity': humidity,
      'latitude': latitude,
      'longitude': longitude,
      'detectedAt': detectedAt.toIso8601String(),
      'status': status,
    };
  }

  // ----------------------------------------------------------
  // CREATE FROM JSON
  // ----------------------------------------------------------

  factory AlertModel.fromJson(Map<String, dynamic> json) {
    return AlertModel(
      id: json['id'] as String,
      deviceId: json['deviceId'] as String,
      type: json['type'] as String,
      severity: json['severity'] as String,
      fireProbability: (json['fireProbability'] as num).toDouble(),
      smokeProbability: (json['smokeProbability'] as num).toDouble(),
      temperature: (json['temperature'] as num).toDouble(),
      humidity: (json['humidity'] as num).toDouble(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      detectedAt: DateTime.parse(json['detectedAt'] as String),
      status: json['status'] as String,
    );
  }
}

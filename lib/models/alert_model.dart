import '../utils/firestore_parse.dart';

class AlertStatus {
  static const String active = 'ACTIVE';
  static const String acknowledged = 'ACKNOWLEDGED';
  static const String resolved = 'RESOLVED';
}

/// What a resolved alert turned out to be. Recorded by the officer; the
/// false-alarm rate and these labels feed model training (stage 3).
class AlertOutcome {
  static const String confirmedFire = 'CONFIRMED_FIRE';
  static const String falseAlarm = 'FALSE_ALARM';
  static const String controlledBurn = 'CONTROLLED_BURN';
  static const String test = 'TEST';

  static const all = [confirmedFire, falseAlarm, controlledBurn, test];

  static String label(String? outcome) {
    switch (outcome) {
      case confirmedFire:
        return 'Confirmed fire';
      case falseAlarm:
        return 'False alarm';
      case controlledBurn:
        return 'Controlled burn';
      case test:
        return 'Test / drill';
      default:
        return 'Not recorded';
    }
  }
}

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

  final String status;

  final String? acknowledgedBy;
  final DateTime? acknowledgedAt;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final String? notes;
  final String? outcome;

  /// Set by the backend once fire has been seen without a break for
  /// 2 minutes; the map only draws fire areas for confirmed fires.
  final DateTime? confirmedAt;

  /// When the sensor last reported this fire (repeats extend the alert).
  final DateTime? lastDetectedAt;

  const AlertModel({
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
    this.acknowledgedBy,
    this.acknowledgedAt,
    this.resolvedBy,
    this.resolvedAt,
    this.notes,
    this.outcome,
    this.confirmedAt,
    this.lastDetectedAt,
  });

  bool get isOpen =>
      status == AlertStatus.active || status == AlertStatus.acknowledged;

  AlertModel copyWith({
    String? status,
    String? acknowledgedBy,
    DateTime? acknowledgedAt,
    String? resolvedBy,
    DateTime? resolvedAt,
    String? notes,
    String? outcome,
    double? latitude,
    double? longitude,
  }) {
    return AlertModel(
      id: id,
      deviceId: deviceId,
      type: type,
      severity: severity,
      fireProbability: fireProbability,
      smokeProbability: smokeProbability,
      temperature: temperature,
      humidity: humidity,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      detectedAt: detectedAt,
      status: status ?? this.status,
      acknowledgedBy: acknowledgedBy ?? this.acknowledgedBy,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      resolvedBy: resolvedBy ?? this.resolvedBy,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      notes: notes ?? this.notes,
      outcome: outcome ?? this.outcome,
      confirmedAt: confirmedAt,
      lastDetectedAt: lastDetectedAt,
    );
  }

  // ----------------------------------------------------------
  // FIRESTORE
  // ----------------------------------------------------------

  /// Builds an alert from an `alerts/{id}` document. Alerts written by the
  /// ingestion pipeline often carry 0,0 coordinates, so the node's location
  /// is used when the alert has none.
  factory AlertModel.fromFirestore(
    String documentId,
    Map<String, dynamic> data, {
    double fallbackLatitude = 0,
    double fallbackLongitude = 0,
  }) {
    final latitude = parseDouble(data['latitude'], 0);
    final longitude = parseDouble(data['longitude'], 0);
    final hasLocation = latitude != 0 || longitude != 0;

    return AlertModel(
      id: parseString(data['alertId'], documentId),
      deviceId: parseString(data['deviceId'], ''),
      type: parseString(data['type'], 'FIRE ALERT'),
      severity: parseString(data['severity'], 'LOW'),
      fireProbability: parseDouble(data['fireProbability'], 0),
      smokeProbability: parseDouble(data['smokeProbability'], 0),
      temperature: parseDouble(data['temperature'], 0),
      humidity: parseDouble(data['humidity'], 0),
      latitude: hasLocation ? latitude : fallbackLatitude,
      longitude: hasLocation ? longitude : fallbackLongitude,
      detectedAt: parseDateTime(data['detectedAt']),
      status: parseString(data['status'], AlertStatus.active),
      acknowledgedBy: parseStringOrNull(data['ackByName'] ?? data['ackBy']),
      acknowledgedAt: parseDateTimeOrNull(data['ackAt']),
      resolvedBy: parseStringOrNull(
        data['resolvedByName'] ?? data['resolvedBy'],
      ),
      resolvedAt: parseDateTimeOrNull(data['resolvedAt']),
      notes: parseStringOrNull(data['notes']),
      outcome: parseStringOrNull(data['outcome']),
      confirmedAt: parseDateTimeOrNull(data['confirmedAt']),
      lastDetectedAt: parseDateTimeOrNull(data['lastDetectedAt']),
    );
  }

  // ----------------------------------------------------------
  // LOCAL JSON (simulation history)
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
      'acknowledgedBy': acknowledgedBy,
      'acknowledgedAt': acknowledgedAt?.toIso8601String(),
      'resolvedBy': resolvedBy,
      'resolvedAt': resolvedAt?.toIso8601String(),
      'notes': notes,
      'outcome': outcome,
    };
  }

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
      acknowledgedBy: json['acknowledgedBy'] as String?,
      acknowledgedAt: parseDateTimeOrNull(json['acknowledgedAt']),
      resolvedBy: json['resolvedBy'] as String?,
      resolvedAt: parseDateTimeOrNull(json['resolvedAt']),
      notes: json['notes'] as String?,
      outcome: json['outcome'] as String?,
    );
  }
}

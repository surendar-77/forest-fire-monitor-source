import '../utils/firestore_parse.dart';
import 'detection_model.dart';

enum NodeStatus { online, stale, offline, unknown }

/// Today's fire-danger rating from the backend's ML model
/// (`devices/{id}.danger`), based on standard noon weather at the node.
class FireDanger {
  /// Danger index 0-1 (1/3 = Medium, 2/3 = High), terrain-adjusted.
  final double probability;

  /// Chance (0-1) of a satellite-detected fire within 10 km today,
  /// terrain-adjusted, and the average over Indian forest days.
  final double? chance;
  final double? averageChance;
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
  final String? terrain;
  final double? baseProbability;

  /// Next 24 h, hour by hour (terrain-adjusted).
  final List<DangerHour> timeline;
  final DangerHour? peak;

  /// If a fire started now: how fast and which way (FBP estimate).
  final FireSpread? spread;

  const FireDanger({
    required this.probability,
    required this.level,
    this.chance,
    this.averageChance,
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
    this.terrain,
    this.baseProbability,
    this.timeline = const [],
    this.peak,
    this.spread,
  });

  static FireDanger? fromMap(dynamic value) {
    if (value is! Map) return null;
    final probability = parseDoubleOrNull(value['probability']);
    if (probability == null) return null;

    return FireDanger(
      probability: probability,
      level: parseString(value['level'], 'LOW'),
      chance: parseDoubleOrNull(value['chance']),
      averageChance: parseDoubleOrNull(value['averageChance']),
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
      terrain: parseStringOrNull(value['terrain']),
      baseProbability: parseDoubleOrNull(value['baseProbability']),
      timeline: value['timeline'] is List
          ? (value['timeline'] as List)
                .map(DangerHour.fromMap)
                .whereType<DangerHour>()
                .toList()
          : const [],
      peak: DangerHour.fromMap(value['peak']),
      spread: FireSpread.fromMap(value['spread']),
    );
  }
}

class FireSpread {
  final double headRos; // m/min
  final double backRos;
  final double lengthToBreadth;
  final double towardDeg;
  final String towardCompass;
  final int headDistance1h; // m
  final int backDistance1h;
  final double windKmh;
  final String fuelModel;
  final String note;

  const FireSpread({
    required this.headRos,
    required this.backRos,
    required this.lengthToBreadth,
    required this.towardDeg,
    required this.towardCompass,
    required this.headDistance1h,
    required this.backDistance1h,
    required this.windKmh,
    required this.fuelModel,
    required this.note,
  });

  static FireSpread? fromMap(dynamic value) {
    if (value is! Map) return null;
    final head = parseDoubleOrNull(value['headRos']);
    if (head == null) return null;
    return FireSpread(
      headRos: head,
      backRos: parseDouble(value['backRos'], 0),
      lengthToBreadth: parseDouble(value['lengthToBreadth'], 1),
      towardDeg: parseDouble(value['towardDeg'], 0),
      towardCompass: parseString(value['towardCompass'], ''),
      headDistance1h: parseInt(value['headDistance1h'], 0),
      backDistance1h: parseInt(value['backDistance1h'], 0),
      windKmh: parseDouble(value['windKmh'], 0),
      fuelModel: parseString(value['fuelModel'], ''),
      note: parseString(value['note'], ''),
    );
  }
}

class AirQuality {
  final double? pm25;
  final double? pm10;
  final double? usAqi;
  final String category;

  const AirQuality({this.pm25, this.pm10, this.usAqi, required this.category});

  static AirQuality? fromMap(dynamic value) {
    if (value is! Map) return null;
    return AirQuality(
      pm25: parseDoubleOrNull(value['pm25']),
      pm10: parseDoubleOrNull(value['pm10']),
      usAqi: parseDoubleOrNull(value['usAqi']),
      category: parseString(value['category'], 'Unknown'),
    );
  }
}

/// A NASA FIRMS (VIIRS) satellite fire detection near a node.
class SatelliteHotspot {
  final double latitude;
  final double longitude;
  final String acquired;
  final String confidence;
  final double? frp;
  final double distanceKm;

  const SatelliteHotspot({
    required this.latitude,
    required this.longitude,
    required this.acquired,
    required this.confidence,
    required this.distanceKm,
    this.frp,
  });

  static SatelliteHotspot? fromMap(dynamic value) {
    if (value is! Map) return null;
    final lat = parseDoubleOrNull(value['latitude']);
    final lng = parseDoubleOrNull(value['longitude']);
    if (lat == null || lng == null) return null;
    return SatelliteHotspot(
      latitude: lat,
      longitude: lng,
      acquired: parseString(value['acquired'], ''),
      confidence: parseString(value['confidence'], 'nominal'),
      frp: parseDoubleOrNull(value['frp']),
      distanceKm: parseDouble(value['distanceKm'], 0),
    );
  }
}

/// LoRa link to a node as measured by a receiver board
/// (`devices/{id}.lora`, written by the backend once a minute).
class LoraLink {
  /// After this long without a report the receiver counts as offline.
  static const Duration staleAfter = Duration(minutes: 3);

  final int? rssi;
  final int? rssiMin;
  final double? snr;
  final int packets;
  final int lost;
  final int? lossPercent;
  final String quality;
  final int bars;
  final String gateway;
  final DateTime? lastPacketAt;
  final DateTime? updatedAt;

  const LoraLink({
    this.rssi,
    this.rssiMin,
    this.snr,
    this.packets = 0,
    this.lost = 0,
    this.lossPercent,
    this.quality = 'No signal',
    this.bars = 0,
    this.gateway = '',
    this.lastPacketAt,
    this.updatedAt,
  });

  bool isStaleAt(DateTime now) {
    final t = updatedAt;
    return t == null || now.difference(t) > staleAfter;
  }

  static LoraLink? fromMap(dynamic value) {
    if (value is! Map) return null;
    return LoraLink(
      rssi: parseDoubleOrNull(value['rssi'])?.round(),
      rssiMin: parseDoubleOrNull(value['rssiMin'])?.round(),
      snr: parseDoubleOrNull(value['snr']),
      packets: parseInt(value['packets'], 0),
      lost: parseInt(value['lost'], 0),
      lossPercent: parseDoubleOrNull(value['lossPercent'])?.round(),
      quality: parseString(value['quality'], 'No signal'),
      bars: parseInt(value['bars'], 0),
      gateway: parseString(value['gateway'], ''),
      lastPacketAt: parseDateTimeOrNull(value['lastPacketAt']),
      updatedAt: parseDateTimeOrNull(value['updatedAt']),
    );
  }
}

class DangerHour {
  /// Local time at the node, "2026-10-19T14:00".
  final String time;
  final double probability;
  final String level;

  const DangerHour(this.time, this.probability, this.level);

  static DangerHour? fromMap(dynamic value) {
    if (value is! Map) return null;
    final p = parseDoubleOrNull(value['probability']);
    final t = parseStringOrNull(value['time']);
    if (p == null || t == null) return null;
    return DangerHour(t, p, parseString(value['level'], 'LOW'));
  }

  /// "14:00"
  String get hourLabel => time.length >= 16 ? time.substring(11, 16) : time;
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

  /// ML detection state against this node's learned baseline:
  /// LEARNING, NORMAL, ELEVATED, SUSPICIOUS or LIKELY.
  final String? anomalyLevel;

  /// Sensor furthest from normal (mq1, mq2, temp, hum), if any.
  final String? anomalyDriver;

  /// Terrain / fuel type id (see Terrain), set by an administrator.
  final String? terrain;

  final AirQuality? airQuality;

  /// Satellite fire detections within the backend's radius (last 24 h).
  final List<SatelliteHotspot> hotspots;

  /// LoRa signal from the receiver board, if one reports this node.
  final LoraLink? lora;

  const NodeModel({
    required this.id,
    required this.name,
    required this.detection,
    required this.reportedStatus,
    required this.hasLocation,
    this.zone,
    this.lastSeen,
    this.danger,
    this.anomalyLevel,
    this.anomalyDriver,
    this.terrain,
    this.airQuality,
    this.hotspots = const [],
    this.lora,
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
      anomalyLevel: data['anomaly'] is Map
          ? parseStringOrNull((data['anomaly'] as Map)['level'])
          : null,
      anomalyDriver: data['anomaly'] is Map
          ? parseStringOrNull((data['anomaly'] as Map)['driver'])
          : null,
      terrain: parseStringOrNull(data['terrain']),
      airQuality: AirQuality.fromMap(data['airQuality']),
      lora: LoraLink.fromMap(data['lora']),
      hotspots:
          data['satellite'] is Map &&
              (data['satellite'] as Map)['hotspots'] is List
          ? ((data['satellite'] as Map)['hotspots'] as List)
                .map(SatelliteHotspot.fromMap)
                .whereType<SatelliteHotspot>()
                .toList()
          : const [],
    );
  }
}

import '../utils/firestore_parse.dart';

/// One per-second sample a node writes to `live/{nodeId}/values` in the
/// Realtime Database.
class LiveReading {
  /// Older than this and the live card says the feed has paused.
  static const Duration staleAfter = Duration(seconds: 10);

  final DateTime? time;
  final double? temperature;
  final double? humidity;
  final double? temperature2;
  final double? humidity2;
  final int? smoke1;
  final int? smoke2;
  final int? riskScore;
  final String? riskLevel;
  final String? aiClass;
  final double? aiConfidence;

  const LiveReading({
    this.time,
    this.temperature,
    this.humidity,
    this.temperature2,
    this.humidity2,
    this.smoke1,
    this.smoke2,
    this.riskScore,
    this.riskLevel,
    this.aiClass,
    this.aiConfidence,
  });

  factory LiveReading.fromMap(Map<Object?, Object?> map) {
    final ts = map['ts'];

    int? asInt(Object? value) => parseDoubleOrNull(value)?.round();

    return LiveReading(
      time: ts is num ? DateTime.fromMillisecondsSinceEpoch(ts.toInt()) : null,
      temperature: parseDoubleOrNull(map['t1']),
      humidity: parseDoubleOrNull(map['h1']),
      temperature2: parseDoubleOrNull(map['t2']),
      humidity2: parseDoubleOrNull(map['h2']),
      smoke1: asInt(map['mq1']),
      smoke2: asInt(map['mq2']),
      riskScore: asInt(map['risk']),
      riskLevel: parseStringOrNull(map['level']),
      aiClass: parseStringOrNull(map['ai']),
      aiConfidence: parseDoubleOrNull(map['conf']),
    );
  }

  bool isStaleAt(DateTime now) {
    final t = time;
    return t == null || now.difference(t) > staleAfter;
  }
}

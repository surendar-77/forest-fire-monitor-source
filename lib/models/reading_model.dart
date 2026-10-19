import '../utils/firestore_parse.dart';

/// One point on a trend chart: a raw reading from
/// `devices/{id}/readings`, or an hourly average from `devices/{id}/hourly`.
class ReadingModel {
  final DateTime time;
  final double? temperature;
  final double? humidity;
  final double? temperature2;
  final double? humidity2;

  /// Higher of the two MQ-2 sensors, and each one.
  final double? smoke;
  final double? smoke1;
  final double? smoke2;

  /// Camera AI, 0-100.
  final double? fireProbability;
  final double? smokeProbability;
  final double? riskScore;

  /// Camera AI class ("Fire", "Smoke", "Normal") and confidence 0-1; raw
  /// readings only.
  final String? aiClass;
  final double? aiConfidence;

  const ReadingModel({
    required this.time,
    this.temperature,
    this.humidity,
    this.temperature2,
    this.humidity2,
    this.smoke,
    this.smoke1,
    this.smoke2,
    this.fireProbability,
    this.smokeProbability,
    this.riskScore,
    this.aiClass,
    this.aiConfidence,
  });

  factory ReadingModel.fromReading(Map<String, dynamic> data) {
    final mq2a = parseDoubleOrNull(data['mq2_1'] ?? data['mq2Sensor1']);
    final mq2b = parseDoubleOrNull(data['mq2_2'] ?? data['mq2Sensor2']);

    return ReadingModel(
      time: parseDateTime(data['ts']),
      temperature: parseDoubleOrNull(data['temperature']),
      humidity: parseDoubleOrNull(data['humidity']),
      temperature2: parseDoubleOrNull(data['temperature2']),
      humidity2: parseDoubleOrNull(data['humidity2']),
      smoke: _maxOf(mq2a, mq2b),
      smoke1: mq2a,
      smoke2: mq2b,
      fireProbability: parseDoubleOrNull(data['fireProbability']),
      smokeProbability: parseDoubleOrNull(data['smokeProbability']),
      riskScore: parseDoubleOrNull(data['riskScore']),
      aiClass: parseStringOrNull(data['aiClass']),
      aiConfidence: parseDoubleOrNull(data['aiConfidence']),
    );
  }

  /// Hourly rollups store running sums and a count; the chart shows the
  /// average, except smoke, camera AI and risk where the hour's peak
  /// matters more.
  factory ReadingModel.fromHourly(Map<String, dynamic> data) {
    final count = parseDouble(data['count'], 0);

    // Newer rollups count each sensor separately, so readings where the
    // DHT22 gave nothing don't drag the average down.
    double? average(
      String sumField,
      String countField, {
      bool fallbackToCount = true,
    }) {
      final sum = parseDoubleOrNull(data[sumField]);
      final n = data[countField] == null && !fallbackToCount
          ? 0.0
          : parseDouble(data[countField], count);
      return sum == null || n == 0 ? null : sum / n;
    }

    return ReadingModel(
      time: parseDateTime(data['hour']),
      temperature: average('temperatureSum', 'temperatureCount'),
      humidity: average('humiditySum', 'humidityCount'),
      temperature2: average(
        'temperature2Sum',
        'temperature2Count',
        fallbackToCount: false,
      ),
      humidity2: average(
        'humidity2Sum',
        'humidity2Count',
        fallbackToCount: false,
      ),
      smoke: parseDoubleOrNull(data['smokeMax']),
      smoke1: parseDoubleOrNull(data['smoke1Max']),
      smoke2: parseDoubleOrNull(data['smoke2Max']),
      fireProbability: parseDoubleOrNull(data['fireProbabilityMax']),
      smokeProbability: parseDoubleOrNull(data['smokeProbabilityMax']),
      riskScore: parseDoubleOrNull(data['riskScoreMax']),
    );
  }

  static double? _maxOf(double? a, double? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a > b ? a : b;
  }
}

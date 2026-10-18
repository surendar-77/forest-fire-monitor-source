import '../utils/firestore_parse.dart';

/// One point on a trend chart: a raw reading from
/// `devices/{id}/readings`, or an hourly average from `devices/{id}/hourly`.
class ReadingModel {
  final DateTime time;
  final double? temperature;
  final double? humidity;
  final double? smoke;
  final double? fireProbability;
  final double? riskScore;

  const ReadingModel({
    required this.time,
    this.temperature,
    this.humidity,
    this.smoke,
    this.fireProbability,
    this.riskScore,
  });

  factory ReadingModel.fromReading(Map<String, dynamic> data) {
    final mq2a = parseDoubleOrNull(data['mq2_1'] ?? data['mq2Sensor1']);
    final mq2b = parseDoubleOrNull(data['mq2_2'] ?? data['mq2Sensor2']);

    return ReadingModel(
      time: parseDateTime(data['ts']),
      temperature: parseDoubleOrNull(data['temperature']),
      humidity: parseDoubleOrNull(data['humidity']),
      smoke: _maxOf(mq2a, mq2b),
      fireProbability: parseDoubleOrNull(data['fireProbability']),
      riskScore: parseDoubleOrNull(data['riskScore']),
    );
  }

  /// Hourly rollups store running sums and a count; the chart shows the
  /// average, except risk where the hour's peak matters more.
  factory ReadingModel.fromHourly(Map<String, dynamic> data) {
    final count = parseDouble(data['count'], 0);

    // Newer rollups count each sensor separately, so readings where the
    // DHT22 gave nothing don't drag the average down.
    double? average(String sumField, String countField) {
      final sum = parseDoubleOrNull(data[sumField]);
      final n = parseDouble(data[countField], count);
      return sum == null || n == 0 ? null : sum / n;
    }

    return ReadingModel(
      time: parseDateTime(data['hour']),
      temperature: average('temperatureSum', 'temperatureCount'),
      humidity: average('humiditySum', 'humidityCount'),
      smoke: parseDoubleOrNull(data['smokeMax']),
      fireProbability: parseDoubleOrNull(data['fireProbabilityMax']),
      riskScore: parseDoubleOrNull(data['riskScoreMax']),
    );
  }

  static double? _maxOf(double? a, double? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a > b ? a : b;
  }
}

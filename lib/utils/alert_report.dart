import '../models/alert_model.dart';
import 'friendly.dart';

/// Figures for an alert report over a period.
class AlertReport {
  AlertReport._({
    required this.alerts,
    required this.from,
    required this.to,
    required this.byType,
    required this.bySensor,
    required this.perDay,
    required this.medianAcknowledge,
    required this.medianResolve,
    required this.acknowledgedCount,
    required this.realFires,
    required this.falseAlarms,
  });

  final List<AlertModel> alerts;
  final DateTime from;
  final DateTime to;

  /// Alert type -> count, most common first.
  final List<MapEntry<String, int>> byType;

  /// Sensor id -> count, most alerts first.
  final List<MapEntry<String, int>> bySensor;

  /// One entry per day from [from] to [to] (local midnight -> count).
  final List<MapEntry<DateTime, int>> perDay;

  final Duration? medianAcknowledge;
  final Duration? medianResolve;
  final int acknowledgedCount;
  final int realFires;
  final int falseAlarms;

  int get total => alerts.length;
  int get open => alerts.where((a) => a.isOpen).length;
  int get fireAndSmoke => alerts.where((a) => a.isCamera).length;
  int get sensorProblems =>
      alerts.where((a) => isSensorProblem(a.type) || a.type == 'NODE_OFFLINE').length;

  /// Share of judged camera alerts that were false alarms, 0-100.
  int? get falseAlarmPercent {
    final judged = realFires + falseAlarms;
    return judged == 0 ? null : (falseAlarms * 100 / judged).round();
  }

  static Duration? _median(List<Duration> values) {
    if (values.isEmpty) return null;
    values.sort();
    return values[values.length ~/ 2];
  }

  factory AlertReport.of(List<AlertModel> all, {required DateTime from, required DateTime to}) {
    final alerts = all
        .where((a) => !a.detectedAt.isBefore(from) && a.detectedAt.isBefore(to))
        .toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));

    Map<String, int> count(String Function(AlertModel) key) {
      final m = <String, int>{};
      for (final a in alerts) {
        m[key(a)] = (m[key(a)] ?? 0) + 1;
      }
      return m;
    }

    List<MapEntry<String, int>> sorted(Map<String, int> m) =>
        m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final days = <DateTime, int>{};
    final firstDay = DateTime(from.year, from.month, from.day);
    for (var d = firstDay; d.isBefore(to); d = DateTime(d.year, d.month, d.day + 1)) {
      days[d] = 0;
    }
    for (final a in alerts) {
      final local = a.detectedAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (days.containsKey(day)) days[day] = days[day]! + 1;
    }

    final camera = alerts.where((a) => a.isCamera);
    return AlertReport._(
      alerts: alerts,
      from: from,
      to: to,
      byType: sorted(count((a) => a.type)),
      bySensor: sorted(count((a) => a.deviceId)),
      perDay: days.entries.toList(),
      medianAcknowledge: _median([
        for (final a in alerts)
          if (a.timeToAcknowledge != null && !a.timeToAcknowledge!.isNegative) a.timeToAcknowledge!,
      ]),
      medianResolve: _median([
        for (final a in alerts)
          if (a.timeToResolve != null && !a.timeToResolve!.isNegative && a.resolvedBy != 'Cleanup')
            a.timeToResolve!,
      ]),
      acknowledgedCount: alerts.where((a) => a.acknowledgedAt != null).length,
      realFires: camera.where((a) => a.judgedReal).length,
      falseAlarms: camera.where((a) => a.judgedFalse).length,
    );
  }
}

import 'package:flutter/material.dart';

import '../models/node_model.dart';
import '../models/terrain.dart';

/// Today's ML fire-danger rating for a node, adjusted for its terrain, with
/// the hour-by-hour outlook and the weather behind it.
class FireDangerCard extends StatelessWidget {
  const FireDangerCard({
    super.key,
    required this.node,
    this.canEdit = false,
    this.onTerrainChanged,
  });

  final NodeModel node;
  final bool canEdit;
  final ValueChanged<String>? onTerrainChanged;

  static Color colorFor(String level) {
    switch (level) {
      case 'HIGH':
      case 'VERY HIGH':
        return Colors.red;
      case 'MEDIUM':
      case 'MODERATE':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final danger = node.danger;
    final terrain = Terrain.byId(node.terrain);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _terrainRow(context, terrain),
            const Divider(height: 22),
            if (danger == null)
              Text(
                node.hasLocation
                    ? 'Fire danger is calculated hourly from weather at the '
                          'node; the first rating appears within the hour.'
                    : canEdit
                    ? "Set this node's location (below) to get fire-danger "
                          'ratings and the hourly outlook.'
                    : "Available once an administrator sets this node's location.",
                style: TextStyle(color: Colors.grey.shade700),
              )
            else
              ..._dangerBody(danger),
            if (danger?.spread != null) ...[
              const Divider(height: 22),
              _spreadSection(danger!.spread!),
            ],
            if (node.airQuality != null) ...[
              const Divider(height: 22),
              _airSection(node.airQuality!),
            ],
            if (node.hotspots.isNotEmpty) ...[
              const Divider(height: 22),
              _satelliteSection(node.hotspots),
            ],
          ],
        ),
      ),
    );
  }

  Widget _terrainRow(BuildContext context, Terrain terrain) {
    return Row(
      children: [
        Icon(Icons.park_outlined, color: Colors.green.shade700),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Terrain', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
              Text(
                '${terrain.label}  (fuel ×${terrain.factor})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (canEdit && onTerrainChanged != null)
          PopupMenuButton<String>(
            tooltip: 'Change terrain',
            icon: const Icon(Icons.edit_outlined),
            onSelected: onTerrainChanged,
            itemBuilder: (context) => [
              for (final t in Terrain.all)
                CheckedPopupMenuItem(
                  value: t.id,
                  checked: t.id == terrain.id,
                  child: Text('${t.label}  ×${t.factor}'),
                ),
            ],
          ),
      ],
    );
  }

  List<Widget> _dangerBody(FireDanger danger) {
    final color = colorFor(danger.level);
    final index = (danger.probability * 100).round();
    final chance = danger.chance;
    final average = danger.averageChance;
    final peak = danger.peak;

    return [
      Row(
        children: [
          Icon(Icons.local_fire_department, color: color),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Today',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${danger.level[0]}${danger.level.substring(1).toLowerCase()}',
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$index',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'danger index / 100 for this terrain',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      if (chance != null) ...[
        const SizedBox(height: 4),
        Text(
          '${_percent(chance)} chance of a satellite-detected fire within 10 km today'
          '${average == null ? '' : ' (average Indian forest day: ${_percent(average)})'}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
      if (peak != null) ...[
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.schedule, size: 18, color: colorFor(peak.level)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Highest in the next 24 h: ${peak.hourLabel} '
                '(index ${(peak.probability * 100).round()}, ${peak.level})',
                style: TextStyle(fontWeight: FontWeight.w600, color: colorFor(peak.level)),
              ),
            ),
          ],
        ),
      ],
      if (danger.timeline.isNotEmpty) ...[
        const SizedBox(height: 10),
        _timeline(danger.timeline),
        ..._riskyHours(danger.timeline),
      ],
      const SizedBox(height: 12),
      Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          _fact('Noon temp', danger.temperature, '°C', 1),
          _fact('Humidity', danger.humidity, '%', 0),
          _fact('Wind', danger.wind, ' km/h', 0),
          _fact('Rain 24 h', danger.rain24h, ' mm', 1),
          _fact('Fuel dryness (FFMC)', danger.ffmc, '', 0),
          _fact('Spread index (ISI)', danger.isi, '', 1),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        '${danger.forecast ? "Based on today's noon forecast" : "Based on today's noon weather"}'
        ' · ML model trained on 3 years of NASA satellite fire data from 45 Indian '
        'forests (AUC 0.85 on states it never saw), adjusted for terrain fuel type',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
      ),
    ];
  }

  /// 24 small bars, one per hour, coloured by level.
  Widget _timeline(List<DangerHour> hours) {
    return SizedBox(
      height: 64,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, h) in hours.indexed)
            Expanded(
              child: Tooltip(
                message: '${h.hourLabel}  index ${(h.probability * 100).round()} ${h.level}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: 4 + 40 * h.probability.clamp(0, 1),
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: colorFor(h.level),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      i % 6 == 0 ? h.hourLabel.substring(0, 2) : '',
                      style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// "High danger 12:00–16:00" style summary of risky stretches.
  List<Widget> _riskyHours(List<DangerHour> hours) {
    final spans = <String>[];
    int? start;
    for (var i = 0; i <= hours.length; i++) {
      final risky = i < hours.length && hours[i].level != 'LOW';
      if (risky && start == null) start = i;
      if (!risky && start != null) {
        final from = hours[start].hourLabel;
        final to = hours[i - 1].hourLabel;
        final worst = hours.sublist(start, i).any((h) => h.level == 'HIGH') ? 'High' : 'Medium';
        spans.add(from == to ? '$worst at $from' : '$worst $from–$to');
        start = null;
      }
    }
    if (spans.isEmpty) {
      return [
        Text(
          'No medium or high danger expected in the next 24 h.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
      ];
    }
    return [
      Text(
        'Watch: ${spans.join(', ')}',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ];
  }

  String _percent(double p) =>
      p < 0.01 ? '<1%' : '${(p * 100).toStringAsFixed(p < 0.1 ? 1 : 0)}%';

  String _distance(int metres) =>
      metres >= 1000 ? '${(metres / 1000).toStringAsFixed(1)} km' : '$metres m';

  Widget _spreadSection(FireSpread s) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Transform.rotate(
          angle: s.towardDeg * 3.14159265 / 180,
          child: const Icon(Icons.navigation, color: Colors.deepOrange, size: 28),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'If a fire started now',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'Spreads toward ${s.towardCompass} at ~${s.headRos.toStringAsFixed(1)} m/min: '
                'about ${_distance(s.headDistance1h)} in the first hour '
                '(wind ${s.windKmh.toStringAsFixed(0)} km/h).',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Indicative estimate, Canadian FBP System, fuel ${s.fuelModel}: ${s.note}. '
                'No slope data.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _airSection(AirQuality air) {
    final aqi = air.usAqi;
    final color = aqi == null
        ? Colors.grey
        : aqi <= 50
        ? Colors.green
        : aqi <= 100
        ? Colors.amber.shade800
        : aqi <= 150
        ? Colors.orange
        : Colors.red;

    return Row(
      children: [
        Icon(Icons.air, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Air quality: ${aqi?.round() ?? '--'} AQI · ${air.category}'
            '${air.pm25 == null ? '' : ' · PM2.5 ${air.pm25!.toStringAsFixed(0)} µg/m³'}',
            style: TextStyle(fontWeight: FontWeight.w600, color: color),
          ),
        ),
      ],
    );
  }

  Widget _satelliteSection(List<SatelliteHotspot> hotspots) {
    final nearest = hotspots.first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.satellite_alt, color: Colors.red),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${hotspots.length} satellite fire detection${hotspots.length == 1 ? '' : 's'} '
            'nearby in the last 24 h · nearest ${nearest.distanceKm.toStringAsFixed(1)} km '
            '(${nearest.confidence} confidence, ${nearest.acquired} UTC, NASA VIIRS)',
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.red),
          ),
        ),
      ],
    );
  }

  Widget _fact(String label, double? value, String unit, int digits) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
        Text(
          value == null ? '--' : '${value.toStringAsFixed(digits)}$unit',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

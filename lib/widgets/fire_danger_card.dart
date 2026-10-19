import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/node_model.dart';
import '../models/terrain.dart';
import '../utils/friendly.dart';

/// Today's fire weather at a sensor in plain words: a verdict, the riskiest
/// hours, and anything nearby (satellite fires, smoke). The numbers behind
/// it sit under "Details".
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
        return Colors.red.shade700;
      case 'MEDIUM':
      case 'MODERATE':
        return Colors.orange.shade800;
      default:
        return Colors.green.shade700;
    }
  }

  static String _verdict(String level) {
    switch (level) {
      case 'HIGH':
      case 'VERY HIGH':
        return 'Fires start easily and spread fast today. Avoid any burning and stay alert.';
      case 'MEDIUM':
      case 'MODERATE':
        return 'Fires can start today. Take care with any burning.';
      default:
        return 'Fires are unlikely to start or spread today.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final danger = node.danger;
    final terrain = Terrain.byId(node.terrain);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: danger == null ? _noRating() : _verdictSection(danger),
          ),
          if (node.hotspots.isNotEmpty) _satellite(node.hotspots),
          if (node.airQuality != null) _air(node.airQuality!),
          _forestType(terrain),
          if (danger != null) _details(danger),
        ],
      ),
    );
  }

  Widget _noRating() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        node.hasLocation
            ? 'The first fire-weather rating for this sensor appears within the hour.'
            : canEdit
            ? "Add this sensor's location (below) to see its fire weather."
            : "Fire weather appears once an administrator adds this sensor's location.",
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }

  Widget _verdictSection(FireDanger danger) {
    final color = colorFor(danger.level);
    final peak = danger.peak;
    final riskyPeak = peak != null && peak.level != 'LOW';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.local_fire_department_outlined, color: color),
            const SizedBox(width: 8),
            Text(
              levelLabel(danger.level),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'fire danger',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(_verdict(danger.level), style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                riskyPeak
                    ? 'Riskiest time: ${hourLabel12(peak.hourLabel)} (${levelLabel(peak.level).toLowerCase()})'
                    : 'No risky hours expected in the next 24 hours',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ),
          ],
        ),
        if (danger.timeline.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Risk forecast, next 24 hours',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _timeline(danger.timeline),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  /// Green → amber → red as the danger index rises (0-1).
  static Color _gradientColor(double index) {
    final v = index.clamp(0.0, 1.0);
    const green = Color(0xFF2E7D32);
    const amber = Color(0xFFF9A825);
    const red = Color(0xFFC62828);
    return v < 0.5
        ? Color.lerp(green, amber, v / 0.5)!
        : Color.lerp(amber, red, (v - 0.5) / 0.5)!;
  }

  /// Risk forecast for the next 24 hours as a line whose colour follows the
  /// risk, over Medium / High guide lines.
  Widget _timeline(List<DangerHour> hours) {
    final spots = [
      for (final (i, h) in hours.indexed)
        FlSpot(i.toDouble(), (h.probability * 100).clamp(0, 100).toDouble()),
    ];
    final colors = [for (final h in hours) _gradientColor(h.probability)];
    final gradient = LinearGradient(
      colors: colors.length == 1 ? [colors.first, colors.first] : colors,
    );
    final areaGradient = LinearGradient(
      colors: [
        for (final c
            in (colors.length == 1 ? [colors.first, colors.first] : colors))
          c.withValues(alpha: 0.18),
      ],
    );

    HorizontalLine guide(double y, String label, Color color) => HorizontalLine(
      y: y,
      color: color.withValues(alpha: 0.5),
      strokeWidth: 1,
      dashArray: [4, 4],
      label: HorizontalLineLabel(
        show: true,
        alignment: Alignment.topRight,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
        labelResolver: (_) => label,
      ),
    );

    return SizedBox(
      height: 150,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (hours.length - 1).toDouble(),
          minY: 0,
          maxY: 100,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(
            show: true,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              guide(100 / 3, 'Medium', Colors.orange.shade800),
              guide(200 / 3, 'High', Colors.red.shade700),
            ],
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 6,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= hours.length || value != i.toDouble()) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      i == 0 ? 'Now' : hourLabel12(hours[i].hourLabel),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Colors.grey.shade900,
              getTooltipItems: (touched) => [
                for (final spot in touched)
                  LineTooltipItem(
                    '${hourLabel12(hours[spot.x.round()].hourLabel)}\n'
                    '${levelLabel(hours[spot.x.round()].level)} · ${spot.y.round()}/100',
                    const TextStyle(color: Colors.white, fontSize: 12),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              gradient: gradient,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, gradient: areaGradient),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, Color color, String text, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
          ?trailing,
        ],
      ),
    );
  }

  Widget _satellite(List<SatelliteHotspot> hotspots) {
    final nearest = hotspots.first;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.satellite_alt, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Satellite spotted ${hotspots.length == 1 ? 'a fire' : '${hotspots.length} fires'} '
              'nearby in the last 24 hours. Nearest is '
              '${nearest.distanceKm.toStringAsFixed(1)} km away.',
              style: TextStyle(
                color: Colors.red.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _air(AirQuality air) {
    final aqi = air.usAqi;
    final color = aqi == null
        ? Colors.grey
        : aqi <= 50
        ? Colors.green.shade700
        : aqi <= 100
        ? Colors.amber.shade800
        : aqi <= 150
        ? Colors.orange.shade800
        : Colors.red.shade700;
    return _line(
      Icons.air,
      color,
      'Air quality: ${air.category.toLowerCase()}${aqi == null ? '' : ' (AQI ${aqi.round()})'}',
    );
  }

  Widget _forestType(Terrain terrain) {
    return _line(
      Icons.park_outlined,
      Colors.green.shade700,
      'Forest type: ${terrain.label}',
      trailing: canEdit && onTerrainChanged != null
          ? PopupMenuButton<String>(
              tooltip: 'Change forest type',
              icon: Icon(
                Icons.edit_outlined,
                size: 20,
                color: Colors.grey.shade700,
              ),
              onSelected: onTerrainChanged,
              itemBuilder: (context) => [
                for (final t in Terrain.all)
                  CheckedPopupMenuItem(
                    value: t.id,
                    checked: t.id == terrain.id,
                    child: Text(t.label),
                  ),
              ],
            )
          : const SizedBox(height: 40),
    );
  }

  Widget _details(FireDanger danger) {
    final chance = danger.chance;
    final average = danger.averageChance;
    return Theme(
      data: ThemeData(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          'Details',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade800),
        ),
        children: [
          if (chance != null)
            Text(
              'Chance of a fire within 10 km today: ${_percent(chance)}'
              '${average == null ? '' : ' (a typical Indian forest day is ${_percent(average)})'}.',
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _fact('Midday temperature', danger.temperature, '°C', 1),
              _fact('Humidity', danger.humidity, '%', 0),
              _fact('Wind', danger.wind, ' km/h', 0),
              _fact('Rain (24 h)', danger.rain24h, ' mm', 1),
              _fact('Dry fuel score (FFMC)', danger.ffmc, '', 0),
              _fact('Spread score (ISI)', danger.isi, '', 1),
            ],
          ),
          if (danger.spread != null) ...[
            const SizedBox(height: 14),
            _spread(danger.spread!),
          ],
          const SizedBox(height: 12),
          Text(
            '${danger.forecast ? "From today's midday forecast" : "From today's midday weather"}. '
            'Predicted by a model trained on 3 years of NASA satellite fire records from '
            '45 Indian forests, adjusted for the forest type.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _spread(FireSpread s) {
    final distance = s.headDistance1h >= 1000
        ? '${(s.headDistance1h / 1000).toStringAsFixed(1)} km'
        : '${s.headDistance1h} m';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Transform.rotate(
          angle: s.towardDeg * 3.14159265 / 180,
          child: Icon(
            Icons.navigation,
            color: Colors.deepOrange.shade400,
            size: 22,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'If a fire started now, it would move toward the ${s.towardCompass} '
            'and cover about $distance in the first hour (wind ${s.windKmh.toStringAsFixed(0)} km/h). '
            'Rough estimate; slope is not included.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  String _percent(double p) =>
      p < 0.01 ? 'under 1%' : '${(p * 100).toStringAsFixed(p < 0.1 ? 1 : 0)}%';

  Widget _fact(String label, double? value, String unit, int digits) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
        ),
        Text(
          value == null ? '--' : '${value.toStringAsFixed(digits)}$unit',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

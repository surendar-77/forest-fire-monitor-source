import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// One line on a [TrendChart].
class TrendSeries {
  const TrendSeries(this.label, this.color, this.points);

  final String label;
  final Color color;

  /// (time, value) pairs; nulls are gaps.
  final List<(DateTime, double?)> points;

  bool get hasData => points.any((p) => p.$2 != null);
}

/// Pinch to zoom the time axis, drag sideways to move along it.
FlTransformationConfig chartZoomConfig(TransformationController controller) =>
    FlTransformationConfig(
      scaleAxis: FlScaleAxis.horizontal,
      minScale: 1,
      maxScale: 25,
      trackpadScrollCausesScale: true,
      transformationController: controller,
    );

/// Current horizontal zoom factor of a chart (1 = whole period).
double chartZoom(TransformationController controller) =>
    controller.value.getMaxScaleOnAxis();

/// "Reset zoom" chip shown while a chart is zoomed in.
class ChartZoomReset extends StatelessWidget {
  const ChartZoomReset({super.key, required this.controller});

  final TransformationController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Matrix4>(
      valueListenable: controller,
      builder: (context, matrix, _) {
        final zoom = matrix.getMaxScaleOnAxis();
        if (zoom <= 1.01) {
          return Tooltip(
            message: 'Pinch to zoom, drag sideways to move',
            child: Icon(Icons.zoom_in, size: 18, color: Colors.grey.shade500),
          );
        }
        return ActionChip(
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.zoom_out_map, size: 16),
          label: Text('${zoom.toStringAsFixed(zoom < 10 ? 1 : 0)}x · Reset'),
          onPressed: () => controller.value = Matrix4.identity(),
        );
      },
    );
  }
}

/// A titled card with a time-series line chart, a legend and the latest
/// value of each line. Pinch to zoom, drag to move along the time axis.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.title,
    required this.series,
    this.unit = '',
    this.decimals = 1,
    this.minY,
    this.maxY,
    this.bands = const [],
    this.icon,
  });

  final String title;
  final List<TrendSeries> series;
  final String unit;
  final int decimals;
  final double? minY;
  final double? maxY;

  /// Coloured background bands, e.g. risk levels: (from, to, colour).
  final List<(double, double, Color)> bands;
  final IconData? icon;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  final TransformationController _zoom = TransformationController();

  String get title => widget.title;
  List<TrendSeries> get series => widget.series;
  String get unit => widget.unit;
  int get decimals => widget.decimals;
  double? get minY => widget.minY;
  double? get maxY => widget.maxY;
  List<(double, double, Color)> get bands => widget.bands;
  IconData? get icon => widget.icon;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final withData = series.where((s) => s.hasData).toList();
    final allTimes = [
      for (final s in withData)
        for (final p in s.points) p.$1,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (withData.isNotEmpty) ChartZoomReset(controller: _zoom),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final s in series)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 10, height: 3, color: s.color),
                      const SizedBox(width: 5),
                      Text(
                        '${s.label} ${_latest(s)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 170,
              child: withData.isEmpty || allTimes.length < 2
                  ? Center(
                      child: Text(
                        'No data in this period',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ValueListenableBuilder<Matrix4>(
                      valueListenable: _zoom,
                      builder: (context, matrix, _) => _chart(
                        withData,
                        allTimes,
                        matrix.getMaxScaleOnAxis(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _latest(TrendSeries s) {
    final last = s.points
        .lastWhere((p) => p.$2 != null, orElse: () => (DateTime(0), null))
        .$2;
    return last == null ? '--' : '${last.toStringAsFixed(decimals)}$unit';
  }

  Widget _chart(List<TrendSeries> data, List<DateTime> times, double zoom) {
    final first = times.reduce((a, b) => a.isBefore(b) ? a : b);
    final last = times.reduce((a, b) => a.isAfter(b) ? a : b);
    // Labels follow what is on screen, so zooming in shows finer times.
    final visible = Duration(
      milliseconds: (last.difference(first).inMilliseconds / zoom).round(),
    );
    final fmt = visible.inHours >= 30
        ? DateFormat('d MMM')
        : visible.inMinutes >= 10
        ? DateFormat('HH:mm')
        : DateFormat('HH:mm:ss');
    final interval = (visible.inMilliseconds / 4)
        .clamp(5000, double.infinity)
        .toDouble();

    return LineChart(
      transformationConfig: chartZoomConfig(_zoom),
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        rangeAnnotations: RangeAnnotations(
          horizontalRangeAnnotations: [
            for (final b in bands)
              HorizontalRangeAnnotation(y1: b.$1, y2: b.$2, color: b.$3),
          ],
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  v.toStringAsFixed(v.abs() >= 100 ? 0 : decimals.clamp(0, 1)),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: interval,
              getTitlesWidget: (v, meta) {
                if (v == meta.min || v == meta.max) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    fmt.format(DateTime.fromMillisecondsSinceEpoch(v.toInt())),
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.grey.shade900,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  '${data[spot.barIndex].label}: ${spot.y.toStringAsFixed(decimals)}$unit\n'
                  '${DateFormat('d MMM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(spot.x.toInt()))}',
                  TextStyle(
                    color: data[spot.barIndex].color.withValues(alpha: 1),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          for (final s in data)
            LineChartBarData(
              spots: [
                for (final p in s.points)
                  p.$2 == null
                      ? FlSpot.nullSpot
                      : FlSpot(p.$1.millisecondsSinceEpoch.toDouble(), p.$2!),
              ],
              isCurved: true,
              preventCurveOverShooting: true,
              color: s.color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: data.length == 1,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    s.color.withValues(alpha: 0.25),
                    s.color.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

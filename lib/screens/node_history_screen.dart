import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/node_model.dart';
import '../models/reading_model.dart';
import '../services/auth_service.dart';
import '../services/history_service.dart';
import '../services/node_repository.dart';
import '../services/report_export_service.dart';
import '../utils/risk_utils.dart';

class NodeHistoryScreen extends StatefulWidget {
  const NodeHistoryScreen({
    super.key,
    required this.node,
    required this.repository,
    required this.auth,
    this.historyService,
  });

  final NodeModel node;
  final NodeRepository repository;
  final AuthService auth;
  final HistoryService? historyService;

  @override
  State<NodeHistoryScreen> createState() => _NodeHistoryScreenState();
}

class _NodeHistoryScreenState extends State<NodeHistoryScreen> {
  late final HistoryService _history =
      widget.historyService ?? HistoryService();

  HistoryRange _range = HistoryRange.day;
  late Future<List<ReadingModel>> _readings;

  @override
  void initState() {
    super.initState();
    _readings = _history.load(widget.node.id, _range);
  }

  void _selectRange(HistoryRange range) {
    setState(() {
      _range = range;
      _readings = _history.load(widget.node.id, range);
    });
  }

  Future<void> _export(bool pdf) async {
    final alerts = widget.repository.alertsForNode(widget.node.id);

    if (alerts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No alerts to export for this node.')),
      );
      return;
    }

    try {
      if (pdf) {
        await ReportExportService.sharePdf(
          alerts,
          scope: widget.node.id,
          title: 'Fire Alert Report: ${widget.node.name}',
        );
      } else {
        await ReportExportService.shareCsv(alerts, scope: widget.node.id);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.node.name),
        actions: [
          if (widget.auth.canRespondToAlerts)
            PopupMenuButton<bool>(
              tooltip: 'Export alert report',
              icon: const Icon(Icons.download),
              onSelected: _export,
              itemBuilder: (context) => const [
                PopupMenuItem(value: false, child: Text('Export CSV')),
                PopupMenuItem(value: true, child: Text('Export PDF')),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Center(
            child: SegmentedButton<HistoryRange>(
              segments: [
                for (final range in HistoryRange.values)
                  ButtonSegment(value: range, label: Text(range.label)),
              ],
              selected: {_range},
              onSelectionChanged: (selection) => _selectRange(selection.first),
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<ReadingModel>>(
            future: _readings,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError) {
                return _message(
                  Icons.error_outline,
                  'Could not load history: ${snapshot.error}',
                );
              }

              final readings = snapshot.data ?? const [];

              if (readings.isEmpty) {
                return _message(
                  Icons.timeline,
                  'No readings recorded in the last ${_range.label}.',
                );
              }

              return Column(
                children: [
                  _TrendChart(
                    title: 'Fire risk score',
                    unit: '',
                    color: Colors.red,
                    readings: readings,
                    value: (r) => r.riskScore,
                    minY: 0,
                    maxY: 100,
                    bands: true,
                  ),
                  _TrendChart(
                    title: 'Temperature',
                    unit: '°C',
                    color: Colors.deepOrange,
                    readings: readings,
                    value: (r) => r.temperature,
                  ),
                  _TrendChart(
                    title: 'Humidity',
                    unit: '%',
                    color: Colors.blue,
                    readings: readings,
                    value: (r) => r.humidity,
                    minY: 0,
                    maxY: 100,
                  ),
                  _TrendChart(
                    title: 'Smoke sensor (MQ-2)',
                    unit: '',
                    color: Colors.blueGrey,
                    readings: readings,
                    value: (r) => r.smoke,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _message(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Colors.grey),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.title,
    required this.unit,
    required this.color,
    required this.readings,
    required this.value,
    this.minY,
    this.maxY,
    this.bands = false,
  });

  final String title;
  final String unit;
  final Color color;
  final List<ReadingModel> readings;
  final double? Function(ReadingModel) value;
  final double? minY;
  final double? maxY;

  /// Shades the LOW/MODERATE/HIGH/CRITICAL bands behind a risk chart.
  final bool bands;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (final reading in readings)
        if (value(reading) != null)
          FlSpot(
            reading.time.millisecondsSinceEpoch.toDouble(),
            value(reading)!,
          ),
    ];

    final latest = spots.isEmpty ? null : spots.last.y;
    final first = readings.first.time;
    final last = readings.last.time;
    final spansDays = last.difference(first).inHours >= 24;
    final timeFormat = spansDays ? DateFormat('d MMM') : DateFormat('HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (latest != null)
                    Text(
                      '${latest.toStringAsFixed(1)}$unit',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 170,
              child: spots.isEmpty
                  ? const Center(child: Text('No data for this sensor'))
                  : LineChart(
                      LineChartData(
                        minY: minY,
                        maxY: maxY,
                        gridData: const FlGridData(drawVerticalLine: false),
                        borderData: FlBorderData(show: false),
                        rangeAnnotations: bands
                            ? RangeAnnotations(
                                horizontalRangeAnnotations: [
                                  _band(0, 30, 'LOW'),
                                  _band(30, 60, 'MODERATE'),
                                  _band(60, 80, 'HIGH'),
                                  _band(80, 100, 'CRITICAL'),
                                ],
                              )
                            : const RangeAnnotations(),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(),
                          rightTitles: const AxisTitles(),
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 38,
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 26,
                              interval: _timeInterval(first, last),
                              getTitlesWidget: (value, meta) {
                                if (value == meta.min || value == meta.max) {
                                  return const SizedBox.shrink();
                                }

                                return SideTitleWidget(
                                  meta: meta,
                                  child: Text(
                                    timeFormat.format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        value.toInt(),
                                      ),
                                    ),
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (touched) => touched.map((spot) {
                              final time = DateTime.fromMillisecondsSinceEpoch(
                                spot.x.toInt(),
                              );
                              return LineTooltipItem(
                                '${spot.y.toStringAsFixed(1)}$unit\n'
                                '${DateFormat('d MMM HH:mm').format(time)}',
                                const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            preventCurveOverShooting: true,
                            color: color,
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: color.withValues(alpha: 0.08),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  HorizontalRangeAnnotation _band(double from, double to, String level) {
    return HorizontalRangeAnnotation(
      y1: from,
      y2: to,
      color: riskColor(level).withValues(alpha: 0.06),
    );
  }

  /// About four labels across the x axis, whatever the range.
  double? _timeInterval(DateTime first, DateTime last) {
    final span = last.difference(first).inMilliseconds;
    return span <= 0 ? null : span / 4;
  }
}

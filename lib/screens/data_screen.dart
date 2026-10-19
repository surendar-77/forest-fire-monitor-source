import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/node_model.dart';
import '../models/reading_model.dart';
import '../services/auth_service.dart';
import '../services/data_source_controller.dart';
import '../services/history_service.dart';
import '../widgets/fire_danger_card.dart';
import '../widgets/node_selector.dart';
import '../widgets/trend_chart.dart';

/// Every reading and prediction for the selected sensor as graphs:
/// temperature, humidity and smoke for both zones, the camera AI scores and
/// its recent predictions, the overall risk, and the 24 h fire forecast.
class DataScreen extends StatefulWidget {
  const DataScreen({super.key, required this.controller, required this.auth});

  final DataSourceController controller;
  final AuthService auth;

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  final HistoryService _history = HistoryService();
  HistoryRange _range = HistoryRange.day;
  String? _loadedFor;
  Future<List<ReadingModel>>? _readings;
  Future<List<ReadingModel>>? _predictions;

  void _load(String nodeId) {
    final key = '$nodeId/${_range.name}';
    if (_loadedFor == key) return;
    _loadedFor = key;
    _readings = _history.load(nodeId, _range);
    _predictions = FirebaseFirestore.instance
        .collection('devices')
        .doc(nodeId)
        .collection('readings')
        .orderBy('ts', descending: true)
        .limit(120)
        .get()
        .then(
          (s) => s.docs.map((d) => ReadingModel.fromReading(d.data())).toList(),
        );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.controller.repository,
      ]),
      builder: (context, _) {
        if (!widget.controller.isLive) {
          return const Center(
            child: Text(
              'Graphs are available with real sensors (not demo mode).',
            ),
          );
        }
        final repo = widget.controller.repository;
        final id = widget.controller.selectedNodeId;
        final NodeModel? node = id == null ? null : repo.node(id);
        if (node == null) {
          return const Center(child: Text('No sensors yet.'));
        }
        _load(node.id);

        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _loadedFor = null);
            _load(node.id);
            await _readings;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              if (repo.nodes.length > 1) ...[
                NodeSelector(
                  nodes: repo.nodes,
                  selectedNodeId: node.id,
                  onSelected: widget.controller.selectNode,
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      node.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SegmentedButton<HistoryRange>(
                    showSelectedIcon: false,
                    segments: [
                      for (final r in HistoryRange.values)
                        ButtonSegment(value: r, label: Text(r.label)),
                    ],
                    selected: {_range},
                    onSelectionChanged: (v) => setState(() => _range = v.first),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _range == HistoryRange.hour
                    ? 'Every reading (about one a minute).'
                    : 'Hourly averages; smoke, camera and risk show each hour\'s peak.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<ReadingModel>>(
                future: _readings,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not load readings: ${snap.error}'),
                    );
                  }
                  return Column(children: _charts(snap.data ?? const []));
                },
              ),
              const SizedBox(height: 4),
              _predictionLog(),
              const SizedBox(height: 4),
              _section('Fire weather forecast'),
              FireDangerCard(node: node),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _charts(List<ReadingModel> r) {
    List<(DateTime, double?)> s(double? Function(ReadingModel) f) => [
      for (final x in r) (x.time, f(x)),
    ];
    return [
      TrendChart(
        title: 'Temperature',
        icon: Icons.thermostat,
        unit: '°C',
        series: [
          TrendSeries('Zone 1', Colors.deepOrange, s((x) => x.temperature)),
          TrendSeries(
            'Zone 2',
            Colors.amber.shade700,
            s((x) => x.temperature2),
          ),
        ],
      ),
      TrendChart(
        title: 'Humidity',
        icon: Icons.water_drop_outlined,
        unit: '%',
        decimals: 0,
        series: [
          TrendSeries('Zone 1', Colors.blue, s((x) => x.humidity)),
          TrendSeries('Zone 2', Colors.cyan.shade600, s((x) => x.humidity2)),
        ],
      ),
      TrendChart(
        title: 'Smoke sensors (MQ-2)',
        icon: Icons.cloud_outlined,
        decimals: 0,
        series: [
          TrendSeries(
            'Sensor 1',
            Colors.blueGrey.shade700,
            s((x) => x.smoke1 ?? x.smoke),
          ),
          TrendSeries('Sensor 2', Colors.purple.shade300, s((x) => x.smoke2)),
        ],
      ),
      TrendChart(
        title: 'Camera AI',
        icon: Icons.photo_camera_outlined,
        unit: '%',
        decimals: 0,
        minY: 0,
        maxY: 100,
        series: [
          TrendSeries('Fire', Colors.red.shade600, s((x) => x.fireProbability)),
          TrendSeries(
            'Smoke',
            Colors.grey.shade600,
            s((x) => x.smokeProbability),
          ),
        ],
      ),
      TrendChart(
        title: 'Overall fire risk',
        icon: Icons.local_fire_department_outlined,
        decimals: 0,
        minY: 0,
        maxY: 100,
        bands: [
          (0, 33, Colors.green.withValues(alpha: 0.06)),
          (33, 66, Colors.orange.withValues(alpha: 0.07)),
          (66, 100, Colors.red.withValues(alpha: 0.07)),
        ],
        series: [
          TrendSeries('Risk score', Colors.red.shade400, s((x) => x.riskScore)),
        ],
      ),
    ];
  }

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );

  /// The camera AI's predictions as a graph: one dot per saved reading,
  /// height = confidence, colour = what it saw (Fire / Smoke / Normal).
  Widget _predictionLog() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section('Camera AI predictions'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: FutureBuilder<List<ReadingModel>>(
              future: _predictions,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final rows =
                    (snap.data ?? const [])
                        .where(
                          (r) => r.aiClass != null && r.aiConfidence != null,
                        )
                        .toList()
                      ..sort((a, b) => a.time.compareTo(b.time));
                if (rows.length < 2) {
                  return SizedBox(
                    height: 80,
                    child: Center(
                      child: Text(
                        'Predictions appear here as new readings arrive.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  );
                }
                return _aiChart(rows);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _aiChart(List<ReadingModel> rows) {
    final counts = <String, int>{};
    for (final r in rows) {
      counts[r.aiClass!] = (counts[r.aiClass!] ?? 0) + 1;
    }
    final spots = [
      for (final r in rows)
        FlSpot(r.time.millisecondsSinceEpoch.toDouble(), r.aiConfidence! * 100),
    ];
    final first = rows.first.time;
    final last = rows.last.time;
    final span = last.difference(first);
    final fmt = span.inHours >= 30 ? DateFormat('d MMM') : DateFormat('HH:mm');
    final latest = rows.last;

    Widget legend(String c) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: _aiColor(c), shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$c ${counts[c] ?? 0}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _aiIcon(latest.aiClass),
              size: 18,
              color: _aiColor(latest.aiClass),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Latest: ${latest.aiClass} ${(latest.aiConfidence! * 100).round()}% · '
                '${DateFormat('HH:mm').format(latest.time.toLocal())}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [legend('Fire'), legend('Smoke'), legend('Normal')],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 190,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: 100,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: 25,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: Colors.grey.shade200, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  axisNameWidget: Text(
                    'confidence %',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 25,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        v.toStringAsFixed(0),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: (span.inMilliseconds / 4)
                        .clamp(60000, double.infinity)
                        .toDouble(),
                    getTitlesWidget: (v, meta) {
                      if (v == meta.min || v == meta.max) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          fmt.format(
                            DateTime.fromMillisecondsSinceEpoch(v.toInt()),
                          ),
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
                    for (final t in touched)
                      LineTooltipItem(
                        '${rows[t.spotIndex].aiClass} ${t.y.round()}%\n'
                        '${DateFormat('d MMM HH:mm').format(rows[t.spotIndex].time.toLocal())}',
                        TextStyle(color: Colors.white, fontSize: 11),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  color: Colors.grey.shade300,
                  barWidth: 1,
                  dotData: FlDotData(
                    getDotPainter: (spot, _, _, index) => FlDotCirclePainter(
                      radius: rows[index].aiClass == 'Normal' ? 3 : 5,
                      color: _aiColor(rows[index].aiClass),
                      strokeWidth: 1,
                      strokeColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Last ${rows.length} saved readings (about one a minute).',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Color _aiColor(String? c) => c == 'Fire'
      ? Colors.red.shade700
      : c == 'Smoke'
      ? Colors.orange.shade800
      : Colors.green.shade700;

  IconData _aiIcon(String? c) => c == 'Fire'
      ? Icons.local_fire_department
      : c == 'Smoke'
      ? Icons.cloud
      : Icons.check_circle_outline;
}

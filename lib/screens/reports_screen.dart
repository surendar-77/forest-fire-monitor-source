import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/alert_model.dart';
import '../services/auth_service.dart';
import '../services/node_repository.dart';
import '../services/report_export_service.dart';
import '../utils/alert_report.dart';
import '../utils/alert_timeline.dart';
import '../utils/friendly.dart';

/// Alert reports over a period: how many, what kind, from which sensor, how
/// fast people responded, how often the camera was wrong, and every alert
/// with its timeline. Downloads as PDF or CSV.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.repository,
    required this.auth,
    this.loader,
  });

  final NodeRepository repository;
  final AuthService auth;

  /// For tests; defaults to reading `alerts` from Firestore.
  final Future<List<AlertModel>> Function(DateTime from)? loader;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const _periods = [7, 30, 90];
  int _days = 7;
  String? _sensor;
  late Future<List<AlertModel>> _alerts;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime get _from {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day - (_days - 1));
  }

  void _load() {
    final from = _from;
    _alerts = widget.loader != null ? widget.loader!(from) : _query(from);
  }

  Future<List<AlertModel>> _query(DateTime from) async {
    final snap = await FirebaseFirestore.instance
        .collection('alerts')
        .where('detectedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .orderBy('detectedAt', descending: true)
        .limit(1000)
        .get();
    return snap.docs.map((d) => AlertModel.fromFirestore(d.id, d.data())).toList();
  }

  String _name(String id) => widget.repository.node(id)?.name ?? id;

  Future<void> _export(bool pdf, AlertReport report) async {
    final messenger = ScaffoldMessenger.of(context);
    if (report.alerts.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('No alerts in this period.')));
      return;
    }
    setState(() => _exporting = true);
    try {
      final scope = '${_sensor ?? 'all'}_${_days}d';
      if (pdf) {
        await ReportExportService.sharePdf(
          report.alerts,
          scope: scope,
          from: report.from,
          to: DateTime.now(),
          title: _sensor == null
              ? 'Forest Fire Alert Report'
              : 'Forest Fire Alert Report: ${_name(_sensor!)}',
          sensorNames: {for (final n in widget.repository.nodes) n.id: n.name},
        );
      } else {
        await ReportExportService.shareCsv(report.alerts, scope: scope);
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $error')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alert reports')),
      body: FutureBuilder<List<AlertModel>>(
        future: _alerts,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load alerts: ${snap.error}'),
            );
          }
          final all = snap.data ?? const <AlertModel>[];
          final sensors = {for (final a in all) a.deviceId}.toList()..sort();
          final report = AlertReport.of(
            _sensor == null ? all : all.where((a) => a.deviceId == _sensor).toList(),
            from: _from,
            to: DateTime.now().add(const Duration(minutes: 1)),
          );
          return RefreshIndicator(
            onRefresh: () async {
              setState(_load);
              await _alerts;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _filters(sensors),
                const SizedBox(height: 12),
                _stats(report),
                const SizedBox(height: 12),
                _perDay(report),
                const SizedBox(height: 12),
                _breakdown(report),
                const SizedBox(height: 12),
                if (widget.auth.canRespondToAlerts) _downloads(report),
                const SizedBox(height: 16),
                Text(
                  'Every alert (${report.total})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                if (report.alerts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No alerts in this period.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  )
                else
                  for (final alert in report.alerts) _alertTile(alert),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filters(List<String> sensors) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (final d in _periods) ButtonSegment(value: d, label: Text('$d days')),
          ],
          selected: {_days},
          onSelectionChanged: (v) => setState(() {
            _days = v.first;
            _load();
          }),
        ),
        if (sensors.length > 1)
          DropdownButton<String?>(
            value: _sensor,
            hint: const Text('All sensors'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All sensors')),
              for (final id in sensors)
                DropdownMenuItem(value: id, child: Text(_name(id))),
            ],
            onChanged: (v) => setState(() => _sensor = v),
          ),
      ],
    );
  }

  Widget _stats(AlertReport r) {
    Widget tile(String value, String label, IconData icon, Color color) => SizedBox(
      width: 160,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      label,
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        tile('${r.total}', 'alerts', Icons.notifications_outlined, Colors.blueGrey),
        tile('${r.fireAndSmoke}', 'fire or smoke', Icons.local_fire_department, Colors.red.shade700),
        tile('${r.sensorProblems}', 'sensor problems', Icons.build_circle_outlined, Colors.orange.shade800),
        tile('${r.open}', 'still open', Icons.pending_actions, Colors.red.shade400),
        tile(
          r.medianAcknowledge == null ? '-' : elapsedLabel(r.medianAcknowledge!),
          'typical time to acknowledge',
          Icons.directions_run,
          Colors.blue.shade700,
        ),
        tile(
          r.medianResolve == null ? '-' : elapsedLabel(r.medianResolve!),
          'typical time to resolve',
          Icons.task_alt,
          Colors.green.shade700,
        ),
        tile(
          r.falseAlarmPercent == null ? '-' : '${r.falseAlarmPercent}%',
          'false alarms (${r.realFires + r.falseAlarms} judged)',
          Icons.block,
          Colors.grey.shade700,
        ),
      ],
    );
  }

  Widget _perDay(AlertReport r) {
    final days = r.perDay;
    final maxCount = days.fold<int>(0, (m, e) => e.value > m ? e.value : m);
    final labelEvery = (days.length / 6).ceil().clamp(1, 1000);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Alerts per day', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 10),
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  maxY: (maxCount < 4 ? 4 : maxCount + 1).toDouble(),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        getTitlesWidget: (v, meta) => v % 1 != 0
                            ? const SizedBox.shrink()
                            : SideTitleWidget(
                                meta: meta,
                                child: Text(
                                  v.toInt().toString(),
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                ),
                              ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i >= days.length || i % labelEvery != 0) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              DateFormat('d/M').format(days[i].key),
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.grey.shade900,
                      getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                        '${DateFormat('d MMM').format(days[group.x].key)}\n${rod.toY.toInt()} alerts',
                        const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < days.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: days[i].value.toDouble(),
                            width: days.length > 40 ? 3 : (days.length > 10 ? 6 : 14),
                            color: Colors.red.shade400,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ],
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

  Widget _breakdown(AlertReport r) {
    if (r.total == 0) return const SizedBox.shrink();
    Widget bar(String label, int count, Color color, IconData icon) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          SizedBox(width: 150, child: Text(label, overflow: TextOverflow.ellipsis)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: count / r.total,
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 28, child: Text('$count', textAlign: TextAlign.right)),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('By type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 6),
            for (final e in r.byType)
              bar(alertTitle(e.key), e.value, Colors.red.shade400, alertIcon(e.key)),
            if (r.bySensor.length > 1) ...[
              const SizedBox(height: 12),
              const Text('By sensor', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 6),
              for (final e in r.bySensor)
                bar(_name(e.key), e.value, Colors.blueGrey, Icons.sensors),
            ],
          ],
        ),
      ),
    );
  }

  Widget _downloads(AlertReport r) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _exporting ? null : () => _export(true, r),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF report'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _exporting ? null : () => _export(false, r),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('CSV'),
          ),
        ),
      ],
    );
  }

  Widget _alertTile(AlertModel alert) {
    final color = severityColor(alert.severity);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        shape: const Border(),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.10),
          child: Icon(alertIcon(alert.type), color: color, size: 20),
        ),
        title: Text(alertTitle(alert.type), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${_name(alert.deviceId)} · ${DateFormat('d MMM, HH:mm').format(alert.detectedAt)} · '
          '${alertStatusLabel(alert.status)}',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        children: [AlertTimelineView(alert: alert)],
      ),
    );
  }
}

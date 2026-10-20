import 'package:flutter/material.dart';

import '../models/alert_model.dart';
import '../services/auth_service.dart';
import '../services/monitoring_data_source.dart';
import '../services/node_repository.dart';
import '../services/notification_service.dart';
import '../services/report_export_service.dart';
import '../utils/friendly.dart';

const List<String> _severities = ['CRITICAL', 'HIGH', 'MODERATE', 'LOW'];

class AlertsScreen extends StatefulWidget {
  final MonitoringDataSource simulationService;
  final AuthService auth;

  /// Live alerts for every node. Null in simulation mode, where alerts come
  /// from [simulationService].
  final NodeRepository? repository;

  const AlertsScreen({
    super.key,
    required this.simulationService,
    required this.auth,
    this.repository,
  });

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  String? _nodeFilter;
  String? _severityFilter;
  bool _showResolved = false;

  MonitoringDataSource get simulationService => widget.simulationService;

  bool get _canRespond => widget.auth.canRespondToAlerts;

  List<AlertModel> get _allAlerts {
    final repository = widget.repository;
    return repository != null
        ? repository.alerts
        : simulationService.alertHistory;
  }

  String _sensorName(String id) => widget.repository?.node(id)?.name ?? id;

  bool _matchesFilters(AlertModel alert) {
    return (_nodeFilter == null || alert.deviceId == _nodeFilter) &&
        (_severityFilter == null || alert.severity == _severityFilter);
  }

  Future<void> _acknowledge(AlertModel alert) async {
    await _runAction(() async {
      await NotificationService.stopEmergencyAlarm();

      final repository = widget.repository;

      if (repository != null) {
        await repository.acknowledgeAlert(alert.id);
      } else {
        await simulationService.acknowledgeAlert(alert.id);
      }
    }, 'Marked as being handled.');
  }

  Future<void> _resolve(AlertModel alert) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => const _ResolveDialog(),
    );

    if (result == null) {
      return;
    }
    final (outcome, notes) = result;

    await _runAction(() async {
      final repository = widget.repository;

      if (repository != null) {
        await repository.resolveIncident(
          alert.id,
          notes: notes,
          outcome: outcome,
        );
      } else {
        await simulationService.resolveIncident(alert.id);
      }
    }, 'Alert resolved.');
  }

  Future<void> _verdict(AlertModel alert, String verdict) async {
    final repository = widget.repository;
    if (repository == null) return;
    await _runAction(
      () => repository.markVerdict(alert, verdict),
      verdict == AlertVerdict.real
          ? 'Marked as a real fire. Resolve it once the fire is out.'
          : 'Marked as a false alarm and resolved. Thanks, this trains the camera AI.',
    );
  }

  Future<void> _runAction(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      final denied = error.toString().contains('permission-denied');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            denied
                ? "You don't have permission to do that."
                : 'Something went wrong: $error',
          ),
        ),
      );
    }
  }

  Future<void> _export(bool pdf, List<AlertModel> alerts) async {
    final messenger = ScaffoldMessenger.of(context);

    if (alerts.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No alerts match the current filters.')),
      );
      return;
    }

    final scope = _nodeFilter ?? 'all';

    try {
      if (pdf) {
        await ReportExportService.sharePdf(alerts, scope: scope);
      } else {
        await ReportExportService.shareCsv(alerts, scope: scope);
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        simulationService,
        ?widget.repository,
        widget.auth,
      ]),
      builder: (context, child) {
        final all = _allAlerts;
        final filtered = all.where(_matchesFilters).toList();
        final open = filtered.where((alert) => alert.isOpen).toList();
        final resolved = filtered
            .where((alert) => alert.status == AlertStatus.resolved)
            .toList();
        final nodeIds = {for (final alert in all) alert.deviceId}.toList()
          ..sort();
        final shown = _showResolved ? resolved : open;

        return RefreshIndicator(
          onRefresh: () async {
            // Alerts stream in real time; this just gives pull-to-refresh
            // the expected feel.
            await Future<void>.delayed(const Duration(milliseconds: 300));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _header(open.length),
              const SizedBox(height: 14),
              _tabs(open.length, resolved.length),
              const SizedBox(height: 10),
              _filters(nodeIds, filtered),
              if (!_canRespond) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'View-only access. Officers acknowledge and resolve alerts.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (widget.repository != null)
                CameraAccuracyCard(alerts: all),
              if (_showResolved && resolved.isNotEmpty) ...[
                _outcomeSummary(resolved),
                const SizedBox(height: 8),
              ],
              if (shown.isEmpty)
                _empty()
              else
                for (final alert in shown) _alertTile(alert),
            ],
          ),
        );
      },
    );
  }

  Widget _header(int openCount) {
    final clear = openCount == 0;
    final color = clear ? Colors.green.shade700 : Colors.red.shade700;
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: color.withValues(alpha: 0.10),
          child: Icon(
            clear ? Icons.check : Icons.notifications_active_outlined,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                clear
                    ? 'Nothing needs attention'
                    : '$openCount alert${openCount == 1 ? '' : 's'} need${openCount == 1 ? 's' : ''} attention',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                clear
                    ? 'You will be notified the moment something happens.'
                    : 'Newest first. Tap an alert for details.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
        if (_canRespond)
          PopupMenuButton<bool>(
            tooltip: 'Download report',
            icon: const Icon(Icons.download_outlined),
            onSelected: (pdf) =>
                _export(pdf, _allAlerts.where(_matchesFilters).toList()),
            itemBuilder: (context) => const [
              PopupMenuItem(value: true, child: Text('Download PDF report')),
              PopupMenuItem(
                value: false,
                child: Text('Download spreadsheet (CSV)'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _tabs(int openCount, int resolvedCount) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: false, label: Text('Open ($openCount)')),
        ButtonSegment(value: true, label: Text('Resolved ($resolvedCount)')),
      ],
      selected: {_showResolved},
      onSelectionChanged: (value) =>
          setState(() => _showResolved = value.first),
    );
  }

  Widget _filters(List<String> nodeIds, List<AlertModel> filtered) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (widget.repository != null && nodeIds.length > 1) ...[
            PopupMenuButton<String?>(
              tooltip: 'Filter by sensor',
              onSelected: (value) => setState(() => _nodeFilter = value),
              itemBuilder: (context) => [
                const PopupMenuItem(value: null, child: Text('All sensors')),
                for (final id in nodeIds)
                  PopupMenuItem(value: id, child: Text(_sensorName(id))),
              ],
              child: Chip(
                avatar: const Icon(Icons.sensors, size: 16),
                label: Text(
                  _nodeFilter == null
                      ? 'All sensors'
                      : _sensorName(_nodeFilter!),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          FilterChip(
            label: const Text('Any level'),
            selected: _severityFilter == null,
            onSelected: (_) => setState(() => _severityFilter = null),
          ),
          for (final severity in _severities) ...[
            const SizedBox(width: 6),
            FilterChip(
              label: Text(levelLabel(severity)),
              selected: _severityFilter == severity,
              onSelected: (selected) =>
                  setState(() => _severityFilter = selected ? severity : null),
            ),
          ],
        ],
      ),
    );
  }

  Widget _alertTile(AlertModel alert) {
    final color = severityColor(alert.severity);
    final canAck = _canRespond && alert.status == AlertStatus.active;
    final canResolve = _canRespond && alert.status == AlertStatus.acknowledged;
    final canJudge = _canRespond &&
        widget.repository != null &&
        alert.isOpen &&
        alert.isCamera &&
        alert.verdict == null;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetails(alert),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: color.withValues(alpha: 0.10),
                    child: Icon(alertIcon(alert.type), color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alertTitle(alert.type),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_sensorName(alert.deviceId)} · ${timeAgo(alert.detectedAt)}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pill(
                    alertStatusLabel(alert.status),
                    color: alertStatusColor(alert.status),
                  ),
                ],
              ),
              if (alert.message != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 52),
                  child: Text(
                    alert.message!,
                    style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
                  ),
                ),
              ],
              if (alert.isOpen && alert.verdict == AlertVerdict.real) ...[
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.only(left: 52),
                  child: Pill('Confirmed real by a responder', color: Colors.red),
                ),
              ],
              if (canJudge) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 52),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Is it a real fire?',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                              ),
                              onPressed: () =>
                                  _verdict(alert, AlertVerdict.real),
                              icon: const Icon(
                                Icons.local_fire_department,
                                size: 18,
                              ),
                              label: const Text('Real fire'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _verdict(alert, AlertVerdict.falseAlarm),
                              icon: const Icon(Icons.block, size: 18),
                              label: const Text('False alarm'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (canAck || canResolve) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(width: 52),
                    Expanded(
                      child: canAck
                          ? FilledButton.tonalIcon(
                              onPressed: () => _acknowledge(alert),
                              icon: const Icon(Icons.directions_run, size: 18),
                              label: const Text('Acknowledge'),
                            )
                          : FilledButton.tonalIcon(
                              onPressed: () => _resolve(alert),
                              icon: const Icon(Icons.task_alt, size: 18),
                              label: const Text('Resolve'),
                            ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _outcomeSummary(List<AlertModel> resolved) {
    final recorded = resolved.where((a) => a.outcome != null).toList();
    if (recorded.isEmpty) return const SizedBox.shrink();
    final falseAlarms = recorded
        .where((a) => a.outcome == AlertOutcome.falseAlarm)
        .length;
    final confirmed = recorded
        .where((a) => a.outcome == AlertOutcome.confirmedFire)
        .length;
    return Text(
      '$confirmed confirmed fire${confirmed == 1 ? '' : 's'} · '
      '${(falseAlarms * 100 / recorded.length).round()}% false alarms '
      '(of ${recorded.length} with a recorded outcome)',
      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            _showResolved ? Icons.history : Icons.verified_outlined,
            size: 44,
            color: _showResolved ? Colors.grey.shade400 : Colors.green.shade600,
          ),
          const SizedBox(height: 12),
          Text(
            _showResolved ? 'No resolved alerts yet' : 'No open alerts',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            _showResolved
                ? 'Resolved alerts will be listed here.'
                : 'All sensors are quiet.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  void _showDetails(AlertModel alert) {
    final color = severityColor(alert.severity);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) {
        final canAck = _canRespond && alert.status == AlertStatus.active;
        final canResolve =
            _canRespond && alert.status == AlertStatus.acknowledged;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(alertIcon(alert.type), color: color, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        alertTitle(alert.type),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    Pill(
                      alertStatusLabel(alert.status),
                      color: alertStatusColor(alert.status),
                    ),
                    Pill('${levelLabel(alert.severity)} level', color: color),
                  ],
                ),
                const SizedBox(height: 16),
                _row('Sensor', _sensorName(alert.deviceId)),
                _row(
                  'When',
                  '${timeAgo(alert.detectedAt)} (${_dateTime(alert.detectedAt)})',
                ),
                if (alert.message != null) _row('What happened', alert.message!),
                if (alert.isCamera)
                  _row(
                    'Camera AI',
                    alert.aiConfidence != null
                        ? '${alert.type == 'FIRE' ? 'Fire' : 'Smoke'} · ${(alert.aiConfidence! * 100).round()}% sure'
                        : 'fire ${alert.fireProbability.toStringAsFixed(0)}% · smoke ${alert.smokeProbability.toStringAsFixed(0)}%',
                  ),
                if (alert.verdict != null)
                  _row(
                    'Responder said',
                    alert.verdict == AlertVerdict.real
                        ? 'Real fire'
                        : 'False alarm',
                  ),
                _row(
                  'Weather at sensor',
                  '${alert.temperature.toStringAsFixed(1)}°C · ${alert.humidity.toStringAsFixed(0)}% humidity',
                ),
                _row(
                  'Location',
                  '${alert.latitude.toStringAsFixed(4)}, ${alert.longitude.toStringAsFixed(4)}',
                ),
                if (alert.acknowledgedAt != null)
                  _row(
                    'Handled by',
                    '${alert.acknowledgedBy ?? 'Unknown'} · ${_dateTime(alert.acknowledgedAt!)}',
                  ),
                if (alert.resolvedAt != null)
                  _row(
                    'Resolved by',
                    '${alert.resolvedBy ?? 'Unknown'} · ${_dateTime(alert.resolvedAt!)}',
                  ),
                if (alert.outcome != null)
                  _row('What it was', AlertOutcome.label(alert.outcome)),
                if (alert.notes != null && alert.notes!.isNotEmpty)
                  _row('Notes', alert.notes!),
                if (canAck || canResolve) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(context);
                        canAck ? _acknowledge(alert) : _resolve(alert);
                      },
                      child: Text(
                        canAck ? "Acknowledge (I'm handling it)" : 'Resolve',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _dateTime(DateTime t) {
    final day = t.day.toString().padLeft(2, '0');
    final month = t.month.toString().padLeft(2, '0');
    return '$day/$month/${t.year}, ${clockTime(t)}';
  }
}

/// How often the camera AI was right, from responders' "Real fire" /
/// "False alarm" calls and resolution outcomes, and which confidence
/// threshold would have separated the two.
class CameraAccuracyCard extends StatelessWidget {
  const CameraAccuracyCard({super.key, required this.alerts});

  final List<AlertModel> alerts;

  static double? _average(Iterable<double> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;

  /// A whole-percent threshold above every false alarm and at or below
  /// every real fire, or null when none separates them.
  static int? separatingThreshold(List<double> real, List<double> falses) {
    if (real.isEmpty || falses.isEmpty) return null;
    final above = (falses.reduce((a, b) => a > b ? a : b) * 100).floor() + 1;
    final lowestReal = (real.reduce((a, b) => a < b ? a : b) * 100).floor();
    return above <= lowestReal && above <= 99 ? above : null;
  }

  @override
  Widget build(BuildContext context) {
    final judged = alerts
        .where((a) => a.isCamera && (a.judgedReal || a.judgedFalse))
        .toList();
    if (judged.isEmpty) return const SizedBox.shrink();

    final real = judged.where((a) => a.judgedReal).toList();
    final falses = judged.where((a) => a.judgedFalse).toList();
    final percent = (real.length * 100 / judged.length).round();
    final realConf = [for (final a in real) ?a.aiConfidence];
    final falseConf = [for (final a in falses) ?a.aiConfidence];
    final avgReal = _average(realConf);
    final avgFalse = _average(falseConf);
    final threshold = separatingThreshold(realConf, falseConf);
    final color = percent >= 80
        ? Colors.green.shade700
        : percent >= 50
        ? Colors.orange.shade800
        : Colors.red.shade700;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color.withValues(alpha: 0.10),
              child: Text(
                '$percent%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Camera AI accuracy',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${real.length} real fire${real.length == 1 ? '' : 's'}, '
                    '${falses.length} false alarm${falses.length == 1 ? '' : 's'} '
                    '(of ${judged.length} checked by responders)',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                  if (avgReal != null || avgFalse != null)
                    Text(
                      [
                        if (avgReal != null)
                          'real fires averaged ${(avgReal * 100).round()}% sure',
                        if (avgFalse != null)
                          'false alarms ${(avgFalse * 100).round()}%',
                      ].join(' · '),
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  if (threshold != null && threshold > 75)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Alerting from $threshold% instead of 75% would have kept every real fire '
                        'and stopped these false alarms.',
                        style: TextStyle(
                          color: Colors.blue.shade800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolveDialog extends StatefulWidget {
  const _ResolveDialog();

  @override
  State<_ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends State<_ResolveDialog> {
  final _notesController = TextEditingController();
  String? _outcome;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Resolve alert'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'What was it?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'This helps measure false alarms and improve detection.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final outcome in AlertOutcome.all)
                  ChoiceChip(
                    label: Text(AlertOutcome.label(outcome)),
                    selected: _outcome == outcome,
                    onSelected: (_) => setState(() => _outcome = outcome),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'What you found, action taken, area affected',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _outcome == null
              ? null
              : () =>
                    Navigator.pop(context, (_outcome!, _notesController.text)),
          child: const Text('Resolve'),
        ),
      ],
    );
  }
}

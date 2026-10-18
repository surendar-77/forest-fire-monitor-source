import 'package:flutter/material.dart';

import '../models/alert_model.dart';
import '../services/auth_service.dart';
import '../services/monitoring_data_source.dart';
import '../services/node_repository.dart';
import '../services/notification_service.dart';
import '../services/report_export_service.dart';

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

  MonitoringDataSource get simulationService => widget.simulationService;

  bool get _canRespond => widget.auth.canRespondToAlerts;

  List<AlertModel> get _allAlerts {
    final repository = widget.repository;
    return repository != null
        ? repository.alerts
        : simulationService.alertHistory;
  }

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
    }, 'Alert acknowledged.');
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
        await repository.resolveIncident(alert.id, notes: notes, outcome: outcome);
      } else {
        await simulationService.resolveIncident(alert.id);
      }
    }, 'Incident resolved.');
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
                ? 'You don\'t have permission to do that.'
                : 'Action failed: $error',
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

        final activeAlerts = filtered.where((alert) => alert.isOpen).toList();

        final history = filtered
            .where((alert) => alert.status == AlertStatus.resolved)
            .toList();

        final nodeIds = {for (final alert in all) alert.deviceId}.toList()
          ..sort();

        return RefreshIndicator(
          onRefresh: () async {
            // Alerts stream in real time; this just gives pull-to-refresh
            // the expected feel.
            await Future<void>.delayed(const Duration(milliseconds: 300));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _summaryCard(activeCount: activeAlerts.length),

              if (history.isNotEmpty) ...[
                const SizedBox(height: 10),
                _outcomeStats(history),
              ],

              const SizedBox(height: 14),

              _filterBar(nodeIds, filtered),

              if (!_canRespond) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.visibility_outlined,
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'View-only access. Officers acknowledge and resolve '
                        'alerts.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 20),

              // ==========================================
              // ACTIVE ALERTS
              // ==========================================
              const Text(
                'Active Alerts',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              if (activeAlerts.isEmpty)
                _emptyActiveCard()
              else
                ...activeAlerts.map(
                  (alert) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _activeAlertCard(context, alert),
                  ),
                ),

              const SizedBox(height: 12),

              // ==========================================
              // ALERT HISTORY
              // ==========================================
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Alert History',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '${history.length} incidents',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              if (history.isEmpty)
                _emptyHistoryCard()
              else
                ...history.map(
                  (alert) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _historyCard(context, alert),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ==================================================
  // OUTCOME STATS (false-alarm rate)
  // ==================================================

  Widget _outcomeStats(List<AlertModel> resolved) {
    final recorded = resolved.where((a) => a.outcome != null).toList();
    final counts = {
      for (final o in AlertOutcome.all) o: recorded.where((a) => a.outcome == o).length,
    };
    final falseAlarms = counts[AlertOutcome.falseAlarm] ?? 0;
    final rate = recorded.isEmpty ? null : (falseAlarms * 100 / recorded.length).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rate == null
                  ? 'No outcomes recorded yet'
                  : 'False-alarm rate: $rate% of ${recorded.length} recorded',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final o in AlertOutcome.all)
                  Text(
                    '${AlertOutcome.label(o)}: ${counts[o]}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                if (resolved.length > recorded.length)
                  Text(
                    'Not recorded: ${resolved.length - recorded.length}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================================================
  // FILTERS
  // ==================================================

  Widget _filterBar(List<String> nodeIds, List<AlertModel> filtered) {
    return Row(
      children: [
        if (widget.repository != null) ...[
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _nodeFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Node',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('All nodes')),
                for (final id in nodeIds)
                  DropdownMenuItem(value: id, child: Text(id)),
              ],
              onChanged: (value) => setState(() => _nodeFilter = value),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: _severityFilter,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Severity',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('All')),
              for (final severity in _severities)
                DropdownMenuItem(value: severity, child: Text(severity)),
            ],
            onChanged: (value) => setState(() => _severityFilter = value),
          ),
        ),
        if (_canRespond)
          PopupMenuButton<bool>(
            tooltip: 'Export report',
            icon: const Icon(Icons.download),
            onSelected: (pdf) => _export(pdf, filtered),
            itemBuilder: (context) => const [
              PopupMenuItem(value: false, child: Text('Export CSV')),
              PopupMenuItem(value: true, child: Text('Export PDF')),
            ],
          ),
      ],
    );
  }

  // ==================================================
  // SUMMARY CARD
  // ==================================================

  Widget _summaryCard({required int activeCount}) {
    final hasAlerts = activeCount > 0;

    return Card(
      elevation: 2,
      color: hasAlerts
          ? Colors.red.withValues(alpha: 0.06)
          : Colors.green.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: hasAlerts
                    ? Colors.red.withValues(alpha: 0.10)
                    : Colors.green.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasAlerts ? Icons.warning_amber_rounded : Icons.check_circle,
                color: hasAlerts ? Colors.red : Colors.green,
                size: 30,
              ),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasAlerts
                        ? '$activeCount ACTIVE '
                              'ALERT${activeCount == 1 ? '' : 'S'}'
                        : 'SYSTEM NORMAL',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: hasAlerts ? Colors.red : Colors.green,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasAlerts
                        ? 'Fire incidents require attention.'
                        : 'No active fire incidents detected.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================================================
  // EMPTY ACTIVE ALERTS
  // ==================================================

  Widget _emptyActiveCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(Icons.shield_outlined, size: 48, color: Colors.green.shade600),
            const SizedBox(height: 12),
            const Text(
              'No Active Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            Text(
              'The monitoring system is currently normal.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  // ==================================================
  // ACTIVE ALERT CARD
  // ==================================================

  Widget _activeAlertCard(BuildContext context, AlertModel alert) {
    final color = _severityColor(alert.severity);

    final isSmoke = alert.type == 'SMOKE DETECTED';

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ------------------------------------------
            // HEADER
            // ------------------------------------------

            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSmoke ? Icons.cloud : Icons.local_fire_department,
                    color: color,
                    size: 28,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    '${alert.severity} ALERT',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),

                _statusChip(alert.status),
              ],
            ),

            const SizedBox(height: 18),

            // ------------------------------------------
            // DETAILS
            // ------------------------------------------
            _detailRow('Alert Type', alert.type),

            _detailRow(
              'Fire Probability',
              '${alert.fireProbability.toStringAsFixed(0)}%',
            ),

            _detailRow(
              'Smoke Probability',
              '${alert.smokeProbability.toStringAsFixed(0)}%',
            ),

            _detailRow(
              'Temperature',
              '${alert.temperature.toStringAsFixed(1)}°C',
            ),

            _detailRow('Humidity', '${alert.humidity.toStringAsFixed(0)}%'),

            _detailRow('Monitoring Node', alert.deviceId),

            _detailRow(
              'Location',
              '${alert.latitude.toStringAsFixed(4)}° N, '
                  '${alert.longitude.toStringAsFixed(4)}° E',
            ),

            _detailRow('Detected', _formatTime(alert.detectedAt)),

            if (alert.acknowledgedBy != null || alert.acknowledgedAt != null)
              _detailRow(
                'Acknowledged',
                [
                  alert.acknowledgedBy,
                  if (alert.acknowledgedAt != null)
                    _formatTime(alert.acknowledgedAt!),
                ].whereType<String>().join(' · '),
              ),

            const SizedBox(height: 12),

            // ------------------------------------------
            // ACTION
            // ------------------------------------------
            if (_canRespond && alert.status == AlertStatus.active)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _acknowledge(alert),
                  icon: const Icon(Icons.check),
                  label: const Text('ACKNOWLEDGE ALERT'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

            if (_canRespond && alert.status == AlertStatus.acknowledged)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _resolve(alert),
                  icon: const Icon(Icons.done_all),
                  label: const Text('RESOLVE INCIDENT'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==================================================
  // HISTORY CARD
  // ==================================================

  Widget _historyCard(BuildContext context, AlertModel alert) {
    final color = _severityColor(alert.severity);

    final isSmoke = alert.type == 'SMOKE DETECTED';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _showHistoryDetails(context, alert);
        },
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSmoke ? Icons.cloud : Icons.local_fire_department,
                  color: color,
                  size: 24,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${alert.severity} • '
                      '${alert.type}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDateTime(alert.detectedAt),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              _statusChip(alert.status),

              const SizedBox(width: 4),

              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  // ==================================================
  // HISTORY DETAILS
  // ==================================================

  void _showHistoryDetails(BuildContext context, AlertModel alert) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${alert.severity} ALERT'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogRow('Type', alert.type),
                _dialogRow(
                  'Fire',
                  '${alert.fireProbability.toStringAsFixed(0)}%',
                ),
                _dialogRow(
                  'Smoke',
                  '${alert.smokeProbability.toStringAsFixed(0)}%',
                ),
                _dialogRow(
                  'Temperature',
                  '${alert.temperature.toStringAsFixed(1)}°C',
                ),
                _dialogRow('Humidity', '${alert.humidity.toStringAsFixed(0)}%'),
                _dialogRow('Node', alert.deviceId),
                _dialogRow('Latitude', alert.latitude.toStringAsFixed(6)),
                _dialogRow('Longitude', alert.longitude.toStringAsFixed(6)),
                _dialogRow('Detected', _formatDateTime(alert.detectedAt)),
                if (alert.acknowledgedAt != null)
                  _dialogRow(
                    'Acknowledged',
                    '${_formatDateTime(alert.acknowledgedAt!)}'
                        '${alert.acknowledgedBy == null ? '' : '\nby ${alert.acknowledgedBy}'}',
                  ),
                if (alert.resolvedAt != null)
                  _dialogRow(
                    'Resolved',
                    '${_formatDateTime(alert.resolvedAt!)}'
                        '${alert.resolvedBy == null ? '' : '\nby ${alert.resolvedBy}'}',
                  ),
                if (alert.outcome != null)
                  _dialogRow('Outcome', AlertOutcome.label(alert.outcome)),
                if (alert.notes != null) _dialogRow('Notes', alert.notes!),
                _dialogRow('Status', alert.status),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  // ==================================================
  // DETAIL ROW
  // ==================================================

  Widget _detailRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              title,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dialogRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ==================================================
  // STATUS CHIP
  // ==================================================

  Widget _statusChip(String status) {
    final isResolved = status == 'RESOLVED';

    final isAcknowledged = status == 'ACKNOWLEDGED';

    final color = isResolved
        ? Colors.green
        : isAcknowledged
        ? Colors.orange
        : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  // ==================================================
  // EMPTY HISTORY
  // ==================================================

  Widget _emptyHistoryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(Icons.history, color: Colors.grey.shade500),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No resolved incidents yet.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================================================
  // SEVERITY COLOR
  // ==================================================

  Color _severityColor(String severity) {
    switch (severity) {
      case 'CRITICAL':
        return Colors.red;
      case 'HIGH':
        return Colors.deepOrange;
      case 'MODERATE':
        return Colors.orange;
      case 'LOW':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // ==================================================
  // DATE / TIME
  // ==================================================

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;

    final minute = dateTime.minute.toString().padLeft(2, '0');

    final period = dateTime.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }

  String _formatDateTime(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');

    final month = dateTime.month.toString().padLeft(2, '0');

    final year = dateTime.year.toString();

    return '$day/$month/$year • '
        '${_formatTime(dateTime)}';
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
      title: const Text('Resolve incident'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'What was it?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Recorded outcomes measure false alarms and train the '
              'detection model.',
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
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Field notes (optional)',
                hintText: 'What was found, action taken, area affected...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: _outcome == null
              ? null
              : () => Navigator.pop(context, (_outcome!, _notesController.text)),
          child: const Text('RESOLVE'),
        ),
      ],
    );
  }
}

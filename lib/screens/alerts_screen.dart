import 'package:flutter/material.dart';

import '../models/alert_model.dart';
import '../services/monitoring_data_source.dart';
import '../services/notification_service.dart';

class AlertsScreen extends StatelessWidget {
  final MonitoringDataSource simulationService;

  const AlertsScreen({super.key, required this.simulationService});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: simulationService,
      builder: (context, child) {
        final activeAlerts = simulationService.activeAlerts;

        final history = simulationService.alertHistory
            .where((alert) => alert.status == 'RESOLVED')
            .toList();

        return RefreshIndicator(
          onRefresh: () async {
            // The real-time Firebase implementation
            // will later replace this simulation refresh.
            await Future<void>.delayed(const Duration(milliseconds: 300));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _summaryCard(activeCount: activeAlerts.length),

              const SizedBox(height: 24),

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

            const SizedBox(height: 12),

            // ------------------------------------------
            // ACTION
            // ------------------------------------------
            if (alert.status == 'ACTIVE')
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await NotificationService.stopEmergencyAlarm();
                    await simulationService.acknowledgeAlert(alert.id);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('ACKNOWLEDGE ALERT'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

            if (alert.status == 'ACKNOWLEDGED')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    simulationService.resolveIncident(alert.id);
                  },
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

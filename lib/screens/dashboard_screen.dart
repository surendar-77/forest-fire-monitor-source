import 'package:flutter/material.dart';

import '../models/node_model.dart';
import '../widgets/monitoring_node_card.dart';
import '../widgets/node_selector.dart';
import '../widgets/node_status_chip.dart';
import '../widgets/risk_card.dart';
import '../widgets/sensor_card.dart';
import '../widgets/alert_card.dart';
import '../services/auth_service.dart';
import '../services/data_source_controller.dart';
import '../services/live_node_source.dart';
import '../services/monitoring_data_source.dart';
import '../services/location_service.dart';
import 'location_settings_screen.dart';
import 'node_history_screen.dart';

class DashboardScreen extends StatefulWidget {
  final DataSourceController controller;
  final AuthService auth;

  const DashboardScreen({
    super.key,
    required this.controller,
    required this.auth,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final LocationService _locationService = LocationService();

  String _locationName = LocationService.defaultName;
  double _latitude = LocationService.defaultLatitude;
  double _longitude = LocationService.defaultLongitude;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final name = await _locationService.getLocationName();

    final latitude = await _locationService.getLatitude();

    final longitude = await _locationService.getLongitude();

    if (!mounted) {
      return;
    }

    setState(() {
      _locationName = name;
      _latitude = latitude;
      _longitude = longitude;
    });
  }

  MonitoringDataSource get _source => widget.controller.source;

  NodeModel? get _node {
    final source = _source;
    return source is LiveNodeSource ? source.node : null;
  }

  Future<void> _editLocation() async {
    final node = _node;

    if (node == null) {
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (context) => const LocationSettingsScreen()),
      );

      if (changed == true) {
        await _loadLocation();
      }

      return;
    }

    final repository = widget.controller.repository;

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => LocationSettingsScreen(
          initialName: node.name,
          initialLatitude: node.latitude,
          initialLongitude: node.longitude,
          onSave: (name, latitude, longitude) {
            return repository.updateNodeLocation(
              node.id,
              name: name,
              latitude: latitude,
              longitude: longitude,
            );
          },
        ),
      ),
    );
  }

  void _openHistory() {
    final node = _node;

    if (node == null) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NodeHistoryScreen(
          node: node,
          repository: widget.controller.repository,
          auth: widget.auth,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.controller.repository,
        widget.auth,
      ]),
      builder: (context, child) {
        final data = _source.data;
        final node = _node;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.controller.isLive) ...[
                NodeSelector(
                  nodes: widget.controller.repository.nodes,
                  selectedNodeId: widget.controller.selectedNodeId,
                  onSelected: widget.controller.selectNode,
                ),

                const SizedBox(height: 12),
              ],

              _systemStatusBanner(node),

              const SizedBox(height: 12),

              // MONITORING NODE STATUS
              MonitoringNodeCard(
                nodeId: node?.id ?? data.deviceId,
                subtitle: node == null
                    ? 'Simulated node'
                    : '${node.zone ?? 'Monitoring Area'} • '
                          '${NodeStatusChip.labelFor(node.status)}',
                status: node?.status ?? NodeStatus.online,
              ),

              if (node != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openHistory,
                    icon: const Icon(Icons.show_chart),
                    label: const Text('HISTORY & TRENDS'),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // FIRE RISK
              RiskCard(riskLevel: data.riskLevel, riskScore: data.riskScore),

              const SizedBox(height: 24),

              // AI DETECTION
              const Text(
                'AI Detection',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: SensorCard(
                      icon: Icons.local_fire_department,
                      title: 'Fire Probability',
                      value: '${data.fireProbability.toStringAsFixed(0)}%',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SensorCard(
                      icon: Icons.cloud,
                      title: 'Smoke Probability',
                      value: '${data.smokeProbability.toStringAsFixed(0)}%',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ENVIRONMENTAL DATA
              const Text(
                'Environmental Data',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: SensorCard(
                      icon: Icons.thermostat,
                      title: 'Temperature',
                      value: '${data.temperature.toStringAsFixed(1)}°C',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SensorCard(
                      icon: Icons.water_drop,
                      title: 'Humidity',
                      value: '${data.humidity.toStringAsFixed(0)}%',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // MONITORING LOCATION
              _locationCard(node),

              const SizedBox(height: 16),

              // ALERT
              AlertCard(
                alertActive: data.alertActive,
                riskLevel: data.riskLevel,
                fireProbability: data.fireProbability,
                smokeProbability: data.smokeProbability,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _systemStatusBanner(NodeModel? node) {
    final source = _source;
    final live = source.isLive;
    final available = source.isDataAvailable;
    final lastUpdated = source.lastUpdated;
    final status = node?.status ?? NodeStatus.online;
    final openAlerts = source.activeAlerts.length;
    final staleSince = lastUpdated == null ? '--' : _formatUpdated(lastUpdated);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  live ? Icons.cloud_done : Icons.science_outlined,
                  color: live ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    live ? 'LIVE DATA' : 'SIMULATION MODE',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                NodeStatusChip(status: status, compact: true),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _statusItem(
                    Icons.memory,
                    'Node',
                    node?.id ?? source.data.deviceId,
                  ),
                ),
                Expanded(
                  child: _statusItem(
                    Icons.notifications_active,
                    'Open alerts',
                    '$openAlerts',
                  ),
                ),
                Expanded(
                  child: _statusItem(
                    Icons.update,
                    'Updated',
                    lastUpdated == null ? '--' : _formatUpdated(lastUpdated),
                  ),
                ),
              ],
            ),
            if (status == NodeStatus.stale ||
                status == NodeStatus.offline) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: NodeStatusChip.colorFor(status),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'No data from this node since $staleSince. '
                      'Readings below may be out of date.',
                      style: TextStyle(
                        color: NodeStatusChip.colorFor(status),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (live && !available) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  node == null
                      ? 'No monitoring nodes are reporting yet.'
                      : 'Waiting for monitoring data from ${node.id}.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 17, color: Colors.grey.shade600),
        const SizedBox(width: 5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatUpdated(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute:$second $period';
  }

  Widget _locationCard(NodeModel? node) {
    final name = node?.name ?? _locationName;
    final latitude = node?.latitude ?? _latitude;
    final longitude = node?.longitude ?? _longitude;
    final canEdit = node == null || widget.auth.isAdmin;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on, color: Colors.red),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Monitoring Location',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (canEdit)
                  IconButton(
                    tooltip: 'Edit location',
                    onPressed: _editLocation,
                    icon: const Icon(Icons.edit_location_alt),
                  ),
              ],
            ),

            const SizedBox(height: 14),

            Text(
              name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 6),

            Text(
              'Fixed tree-mounted monitoring node',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                const Icon(Icons.gps_fixed, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${latitude.toStringAsFixed(6)}, '
                    '${longitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),

            if (node != null && !node.hasLocation) ...[
              const SizedBox(height: 8),
              Text(
                'This node has no saved coordinates yet; showing the '
                'default location.',
                style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
              ),
            ],

            if (canEdit) ...[
              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _editLocation,
                  icon: const Icon(Icons.edit),
                  label: const Text('EDIT LOCATION'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

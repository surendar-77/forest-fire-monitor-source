import 'package:flutter/material.dart';

import '../models/node_model.dart';
import '../utils/risk_utils.dart';
import '../widgets/fire_danger_card.dart';
import '../widgets/live_feed_card.dart';
import '../widgets/node_selector.dart';
import '../widgets/overview_strip.dart';
import '../widgets/node_status_chip.dart';
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

  Future<void> _setTerrain(String nodeId, String terrain) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.controller.repository.updateNodeTerrain(nodeId, terrain);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Terrain saved. Risk updates with the next reading.'),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save terrain: $error')),
      );
    }
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
        final node = _node;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.controller.isLive) ...[
                OverviewStrip(repository: widget.controller.repository),
                const SizedBox(height: 16),
                NodeSelector(
                  nodes: widget.controller.repository.nodes,
                  selectedNodeId: widget.controller.selectedNodeId,
                  onSelected: widget.controller.selectNode,
                ),
                const SizedBox(height: 16),
              ],

              _statusCard(node),

              if (node != null) LiveFeedCard(nodeId: node.id),

              _sectionTitle('Latest readings'),
              _readingsCard(),

              if (node != null) ...[
                _sectionTitle('Fire danger'),
                FireDangerCard(
                  node: node,
                  canEdit: widget.auth.isAdmin,
                  onTerrainChanged: (terrain) => _setTerrain(node.id, terrain),
                ),
              ],

              _sectionTitle('Location'),
              _locationCard(node),

              if (node != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _openHistory,
                  icon: const Icon(Icons.show_chart, size: 20),
                  label: const Text('History & trends'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// One card for the selected node: who it is, whether it's reporting,
  /// its current risk and why.
  Widget _statusCard(NodeModel? node) {
    final source = _source;
    final data = source.data;
    final status = node?.status ?? NodeStatus.online;
    final lastUpdated = source.lastUpdated;
    final color = riskColor(data.riskLevel);
    final muted = Colors.grey.shade600;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node?.name ?? data.deviceId,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        node == null
                            ? 'Simulated node'
                            : [
                                if (node.zone != null) node.zone!,
                                node.id,
                                if (lastUpdated != null)
                                  'updated ${_formatUpdated(lastUpdated)}',
                              ].join(' · '),
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                NodeStatusChip(status: status, compact: true),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(bottom: 9, right: 8),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  _titleCase(data.riskLevel),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    'fire risk · ${data.riskScore}/100',
                    style: TextStyle(color: muted),
                  ),
                ),
              ],
            ),
            if (data.alertActive) ...[
              const SizedBox(height: 12),
              _notice(
                Icons.warning_amber_rounded,
                Colors.red.shade700,
                'Active alert · fire ${data.fireProbability.toStringAsFixed(0)}% · '
                'smoke ${data.smokeProbability.toStringAsFixed(0)}%',
              ),
            ],
            if (status == NodeStatus.stale || status == NodeStatus.offline) ...[
              const SizedBox(height: 12),
              _notice(
                Icons.cloud_off_outlined,
                Colors.orange.shade800,
                'No data since ${lastUpdated == null ? '--' : _formatUpdated(lastUpdated)}. '
                'Readings may be out of date.',
              ),
            ],
            if (source.isLive && !source.isDataAvailable) ...[
              const SizedBox(height: 12),
              _notice(
                Icons.hourglass_empty,
                muted,
                node == null
                    ? 'No monitoring nodes are reporting yet.'
                    : 'Waiting for data from ${node.id}.',
              ),
            ],
            if (node != null) ...[
              const SizedBox(height: 12),
              Text(
                _detectionText(node),
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _notice(IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _readingsCard() {
    final data = _source.data;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            _reading('Temperature', '${data.temperature.toStringAsFixed(1)}°C'),
            _reading('Humidity', '${data.humidity.toStringAsFixed(0)}%'),
            _reading(
              'Fire (AI)',
              '${data.fireProbability.toStringAsFixed(0)}%',
            ),
            _reading(
              'Smoke (AI)',
              '${data.smokeProbability.toStringAsFixed(0)}%',
            ),
          ],
        ),
      ),
    );
  }

  Widget _reading(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _titleCase(String level) =>
      level.isEmpty ? level : '${level[0]}${level.substring(1).toLowerCase()}';

  /// Explains the ML risk score.
  String _detectionText(NodeModel node) {
    const sensorNames = {
      'mq1': 'smoke sensor 1',
      'mq2': 'smoke sensor 2',
      'temp1': 'temperature 1',
      'temp2': 'temperature 2',
      'hum1': 'humidity 1 (drier)',
      'hum2': 'humidity 2 (drier)',
    };

    final level = node.anomalyLevel;
    if (level == null || level == 'LEARNING') {
      return "Learning this node's normal sensor readings (about an hour of "
          'data). Camera AI alerts work meanwhile.';
    }
    if (level == 'NORMAL') {
      return "All 6 sensors are within this node's normal range.";
    }
    final driver = sensorNames[node.anomalyDriver] ?? 'sensors';
    return "${_titleCase(level)}: $driver is outside this node's normal range.";
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
    final missing = node != null && !node.hasLocation;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        leading: Icon(
          Icons.location_on_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          missing
              ? 'No saved coordinates yet (showing the default location)'
              : '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
          style: TextStyle(
            color: missing ? Colors.orange.shade800 : Colors.grey.shade600,
          ),
        ),
        trailing: canEdit
            ? IconButton(
                tooltip: 'Edit location',
                onPressed: _editLocation,
                icon: const Icon(Icons.edit_outlined),
              )
            : null,
      ),
    );
  }
}

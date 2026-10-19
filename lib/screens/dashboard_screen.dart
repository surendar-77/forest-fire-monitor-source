import 'package:flutter/material.dart';

import '../models/node_model.dart';
import '../models/alert_model.dart';
import '../utils/friendly.dart';
import '../widgets/simulation_controls.dart';
import '../widgets/fire_danger_card.dart';
import '../widgets/live_feed_card.dart';
import '../widgets/lora_card.dart';
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

  /// Switches the app to the Alerts tab.
  final VoidCallback? onOpenAlerts;

  /// Set when shown inside the slide-up panel over the Home map: the panel
  /// drives scrolling, and the map already shows the overview figures.
  final ScrollController? scrollController;
  final bool embedded;

  const DashboardScreen({
    super.key,
    required this.controller,
    required this.auth,
    this.onOpenAlerts,
    this.scrollController,
    this.embedded = false,
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
          controller: widget.scrollController,
          padding: EdgeInsets.fromLTRB(16, widget.embedded ? 0 : 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.embedded)
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              if (widget.controller.isLive) ...[
                if (!widget.embedded) ...[
                  OverviewStrip(repository: widget.controller.repository),
                  const SizedBox(height: 16),
                ],
                NodeSelector(
                  nodes: widget.controller.repository.nodes,
                  selectedNodeId: widget.controller.selectedNodeId,
                  onSelected: widget.controller.selectNode,
                ),
                const SizedBox(height: 16),
              ],

              _statusCard(node),

              if (node != null) LiveFeedCard(nodeId: node.id),

              if (widget.controller.isSimulation) ...[
                _sectionTitle('Try a scenario'),
                SimulationControls(
                  simulationService: widget.controller.simulationService,
                ),
              ],

              _sectionTitle('Sensor readings'),
              _readingsCard(),
              if (node != null) LoraCard(link: node.lora),

              if (node != null) ...[
                _sectionTitle('Fire weather today'),
                FireDangerCard(
                  node: node,
                  canEdit: widget.auth.isAdmin,
                  onTerrainChanged: (terrain) => _setTerrain(node.id, terrain),
                ),
              ],

              _sectionTitle('More'),
              _moreCard(node),
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

  /// The selected sensor at a glance: one plain verdict, coloured to match,
  /// with what to do next.
  Widget _statusCard(NodeModel? node) {
    final source = _source;
    final data = source.data;
    final status = node?.status ?? NodeStatus.online;
    final lastUpdated = source.lastUpdated;
    final muted = Colors.grey.shade600;

    // Most serious first; an old "went offline" alert doesn't headline once
    // the sensor is back online.
    final List<AlertModel> openHere =
        (widget.controller.isLive
                ? widget.controller.repository.openAlerts
                      .where((a) => a.deviceId == node?.id)
                      .toList()
                : List<AlertModel>.of(source.activeAlerts))
            .where(
              (a) => !(a.type == 'NODE_OFFLINE' && status == NodeStatus.online),
            )
            .toList()
          ..sort((a, b) {
            final byType = _alertPriority(a).compareTo(_alertPriority(b));
            return byType != 0 ? byType : b.detectedAt.compareTo(a.detectedAt);
          });
    final offline = status == NodeStatus.stale || status == NodeStatus.offline;
    final waiting = source.isLive && !source.isDataAvailable;
    final level = data.riskLevel;

    final IconData icon;
    final Color color;
    final String title;
    final String message;

    if (openHere.isNotEmpty) {
      icon = alertIcon(openHere.first.type);
      color = Colors.red.shade700;
      title = alertTitle(openHere.first.type);
      message = openHere.length == 1
          ? 'Reported ${timeAgo(openHere.first.detectedAt)}. Check the alert and respond.'
          : '${openHere.length} open alerts for this sensor. Check them and respond.';
    } else if (waiting) {
      icon = Icons.hourglass_empty;
      color = muted;
      title = 'Waiting for data';
      message = node == null
          ? 'No sensors are reporting yet.'
          : 'This sensor has not sent any readings yet.';
    } else if (offline) {
      icon = Icons.wifi_off;
      color = Colors.orange.shade800;
      title = 'Sensor offline';
      message =
          'No signal since ${lastUpdated == null ? 'a while' : _formatUpdated(lastUpdated)}. '
          "Check the sensor's power and Wi-Fi. Readings below may be old.";
    } else if (level == 'HIGH' || level == 'CRITICAL') {
      icon = Icons.local_fire_department;
      color = Colors.red.shade700;
      title = 'High fire risk';
      message = 'Readings point to a possible fire. Check the area now.';
    } else if (level == 'MEDIUM' || level == 'MODERATE') {
      icon = Icons.visibility_outlined;
      color = Colors.orange.shade800;
      title = 'Be alert';
      message = 'Some readings are above normal. Keep an eye on this sensor.';
    } else {
      icon = Icons.check_circle_outline;
      color = Colors.green.shade700;
      title = 'All clear';
      message = 'No signs of fire at this sensor.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    node?.name ?? data.deviceId,
                    style: TextStyle(color: muted, fontWeight: FontWeight.w500),
                  ),
                ),
                NodeStatusChip(status: status, compact: true),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: color.withValues(alpha: 0.10),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(message, style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              ],
            ),
            if (openHere.isNotEmpty && widget.onOpenAlerts != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                  ),
                  onPressed: widget.onOpenAlerts,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('View alerts'),
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Text(
              [
                'Risk score ${data.riskScore}/100',
                if (lastUpdated != null && !offline)
                  'updated ${_formatUpdated(lastUpdated)}',
              ].join(' · '),
              style: TextStyle(color: muted, fontSize: 12),
            ),
            if (node != null) ...[
              const SizedBox(height: 4),
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

  static int _alertPriority(AlertModel alert) {
    switch (alert.type.toUpperCase()) {
      case 'FIRE':
      case 'FIRE DETECTED':
      case 'CRITICAL FIRE':
        return 0;
      case 'SMOKE':
      case 'SMOKE DETECTED':
        return 1;
      case 'SATELLITE_HOTSPOT':
        return 2;
      case 'NODE_OFFLINE':
        return 4;
      default:
        return 3;
    }
  }

  Widget _readingsCard() {
    final data = _source.data;
    final cameraClear = data.fireProbability < 50 && data.smokeProbability < 50;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            _reading(
              data.temperature2 == null ? 'Temperature' : 'Temp 1 / 2',
              data.temperature2 == null
                  ? '${data.temperature.toStringAsFixed(1)}°C'
                  : '${data.temperature.toStringAsFixed(0)}° / ${data.temperature2!.toStringAsFixed(0)}°',
            ),
            _reading(
              data.humidity2 == null ? 'Humidity' : 'Humidity 1 / 2',
              data.humidity2 == null
                  ? '${data.humidity.toStringAsFixed(0)}%'
                  : '${data.humidity.toStringAsFixed(0)}% / ${data.humidity2!.toStringAsFixed(0)}%',
            ),
            _reading(
              'Camera',
              cameraClear
                  ? 'Clear'
                  : data.fireProbability >= data.smokeProbability
                  ? 'Fire'
                  : 'Smoke',
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
      return "Learning this sensor's normal sensor readings (about an hour of "
          'data). Camera AI alerts work meanwhile.';
    }
    if (level == 'NORMAL') {
      return "All 6 sensors are within this sensor's normal range.";
    }
    final driver = sensorNames[node.anomalyDriver] ?? 'sensors';
    return "${_titleCase(level)}: $driver is outside this sensor's normal range.";
  }

  String _formatUpdated(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute:$second $period';
  }

  Widget _moreCard(NodeModel? node) {
    final name = node?.name ?? _locationName;
    final latitude = node?.latitude ?? _latitude;
    final longitude = node?.longitude ?? _longitude;
    final canEdit = node == null || widget.auth.isAdmin;
    final missing = node != null && !node.hasLocation;
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.location_on_outlined, color: primary),
            title: Text('Location of $name'),
            subtitle: Text(
              missing
                  ? 'Not set yet'
                  : '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
              style: TextStyle(
                color: missing ? Colors.orange.shade800 : Colors.grey.shade600,
              ),
            ),
            trailing: canEdit ? const Icon(Icons.chevron_right) : null,
            onTap: canEdit ? _editLocation : null,
          ),
          if (node != null) ...[
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: Icon(Icons.show_chart, color: primary),
              title: const Text('History & trends'),
              subtitle: Text(
                'Readings over the last day and week',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openHistory,
            ),
          ],
        ],
      ),
    );
  }
}

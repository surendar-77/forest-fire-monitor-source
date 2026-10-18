import 'package:flutter/material.dart';

import '../widgets/monitoring_node_card.dart';
import '../widgets/risk_card.dart';
import '../widgets/sensor_card.dart';
import '../widgets/alert_card.dart';
import '../services/monitoring_data_source.dart';
import '../services/location_service.dart';
import 'location_settings_screen.dart';
import '../services/node_config.dart';

class DashboardScreen extends StatefulWidget {
  final MonitoringDataSource simulationService;

  const DashboardScreen({super.key, required this.simulationService});

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

  Future<void> _editLocation() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const LocationSettingsScreen()),
    );

    if (changed == true) {
      await _loadLocation();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.simulationService,
      builder: (context, child) {
        final data = widget.simulationService.data;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _systemStatusBanner(data),

              const SizedBox(height: 12),

              // MONITORING NODE STATUS
              const MonitoringNodeCard(),

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
                      value: '°C',
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
              _locationCard(),

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

  Widget _systemStatusBanner(dynamic data) {
    final live = widget.simulationService.isLive;
    final available = widget.simulationService.isDataAvailable;
    final lastUpdated = widget.simulationService.lastUpdated;

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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: (available ? Colors.green : Colors.orange)
                        .withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    available ? 'ONLINE' : 'WAITING',
                    style: TextStyle(
                      color: available ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _statusItem(Icons.memory, 'Node', NodeConfig.nodeId),
                ),
                Expanded(
                  child: _statusItem(
                    Icons.notifications_active,
                    'Alerts',
                    'ACTIVE',
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
            if (live && !available) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Waiting for monitoring data from NODE-01.',
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

  Widget _locationCard() {
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
                IconButton(
                  tooltip: 'Edit location',
                  onPressed: _editLocation,
                  icon: const Icon(Icons.edit_location_alt),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Text(
              _locationName,
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
                    '${_latitude.toStringAsFixed(6)}, '
                    '${_longitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),

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
        ),
      ),
    );
  }
}

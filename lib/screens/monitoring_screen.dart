import 'package:flutter/material.dart';

import '../services/monitoring_data_source.dart';
import '../services/simulation_service.dart';
import '../services/location_service.dart';
import '../widgets/simulation_controls.dart';

class MonitoringScreen extends StatefulWidget {
  final MonitoringDataSource simulationService;
  final SimulationService? simulationController;

  const MonitoringScreen({
    super.key,
    required this.simulationService,
    this.simulationController,
  });

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  final LocationService _locationService = LocationService();

  String _locationName = LocationService.defaultName;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final name = await _locationService.getLocationName();

    if (!mounted) {
      return;
    }

    setState(() {
      _locationName = name;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.simulationService,
      builder: (context, child) {
        final data = widget.simulationService.data;

        final hasAlert = data.alertActive;

        final riskColor = _riskColor(data.riskLevel);

        return RefreshIndicator(
          onRefresh: () async {
            await _loadLocation();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              // ==========================================
              // SYSTEM STATUS
              // ==========================================

              _systemStatusCard(hasAlert: hasAlert, riskLevel: data.riskLevel),

              const SizedBox(height: 20),

              // ==========================================
              // MONITORING NODE
              // ==========================================
              _nodeCard(),

              const SizedBox(height: 24),

              const Text(
                'AI Detection',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              // ==========================================
              // AI VALUES
              // ==========================================
              Row(
                children: [
                  Expanded(
                    child: _metricCard(
                      icon: Icons.local_fire_department,
                      title: 'FIRE',
                      value: '${data.fireProbability.toStringAsFixed(0)}%',
                      color: _probabilityColor(data.fireProbability),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _metricCard(
                      icon: Icons.cloud,
                      title: 'SMOKE',
                      value: '${data.smokeProbability.toStringAsFixed(0)}%',
                      color: _probabilityColor(data.smokeProbability),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              const Text(
                'Environmental Conditions',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _metricCard(
                      icon: Icons.thermostat,
                      title: 'TEMPERATURE',
                      value: '${data.temperature.toStringAsFixed(1)}°C',
                      color: _temperatureColor(data.temperature),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _metricCard(
                      icon: Icons.water_drop,
                      title: 'HUMIDITY',
                      value: '${data.humidity.toStringAsFixed(0)}%',
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ==========================================
              // RISK ASSESSMENT
              // ==========================================
              const Text(
                'Risk Assessment',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              _riskAssessmentCard(
                riskLevel: data.riskLevel,
                riskScore: data.riskScore,
                color: riskColor,
              ),

              const SizedBox(height: 24),

              // ==========================================
              // CURRENT LOCATION
              // ==========================================
              _locationCard(data),

              const SizedBox(height: 24),

              // ==========================================
              // SIMULATION CONTROLS
              // ==========================================
              if (widget.simulationController != null) ...[
                const Text(
                  'Simulation Controls',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 6),

                Text(
                  'Use these scenarios to test the monitoring '
                  'and alert system.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),

                const SizedBox(height: 12),

                SimulationControls(
                  simulationService: widget.simulationController!,
                ),

                const SizedBox(height: 24),
              ],

              // ==========================================
              // INFORMATION
              // ==========================================
              Card(
                color: Colors.blue.withValues(alpha: 0.05),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'The monitoring node continuously '
                          'observes environmental conditions '
                          'and visual AI predictions. The final '
                          'risk level is used to determine '
                          'whether an alert requires attention.',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================================================
  // SYSTEM STATUS
  // ==================================================

  Widget _systemStatusCard({
    required bool hasAlert,
    required String riskLevel,
  }) {
    final color = hasAlert ? _riskColor(riskLevel) : Colors.green;

    return Card(
      elevation: 3,
      color: color.withValues(alpha: 0.07),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasAlert ? Icons.warning_amber_rounded : Icons.check_circle,
                color: color,
                size: 32,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasAlert ? 'ATTENTION REQUIRED' : 'SYSTEM NORMAL',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasAlert
                        ? '$riskLevel risk detected by monitoring system.'
                        : 'No significant fire or smoke detected.',
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
  // MONITORING NODE
  // ==================================================

  Widget _nodeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.forest, color: Colors.green, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MONITORING NODE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _locationName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Fixed tree-mounted monitoring unit',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.circle, color: Colors.green, size: 12),
          ],
        ),
      ),
    );
  }

  // ==================================================
  // METRIC CARD
  // ==================================================

  Widget _metricCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================================================
  // RISK ASSESSMENT
  // ==================================================

  Widget _riskAssessmentCard({
    required String riskLevel,
    required int riskScore,
    required Color color,
  }) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.shield, color: color, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CURRENT RISK LEVEL',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        riskLevel,
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$riskScore',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const Text('/100', style: TextStyle(color: Colors.grey)),
              ],
            ),

            const SizedBox(height: 16),

            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: riskScore / 100,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                color: color,
              ),
            ),

            const SizedBox(height: 10),

            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('LOW', style: TextStyle(fontSize: 10, color: Colors.grey)),
                Text(
                  'MODERATE',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
                Text(
                  'HIGH',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
                Text(
                  'CRITICAL',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================================================
  // LOCATION
  // ==================================================

  Widget _locationCard(dynamic data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Monitoring Location',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _locationName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.gps_fixed, color: Colors.grey, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${data.latitude.toStringAsFixed(6)}, '
                    '${data.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================================================
  // COLORS
  // ==================================================

  Color _riskColor(String riskLevel) {
    switch (riskLevel) {
      case 'LOW':
        return Colors.green;
      case 'MODERATE':
        return Colors.orange;
      case 'HIGH':
        return Colors.deepOrange;
      case 'CRITICAL':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _probabilityColor(double probability) {
    if (probability >= 80) {
      return Colors.red;
    }

    if (probability >= 60) {
      return Colors.deepOrange;
    }

    if (probability >= 30) {
      return Colors.orange;
    }

    return Colors.green;
  }

  Color _temperatureColor(double temperature) {
    if (temperature >= 40) {
      return Colors.red;
    }

    if (temperature >= 35) {
      return Colors.deepOrange;
    }

    if (temperature >= 30) {
      return Colors.orange;
    }

    return Colors.blue;
  }
}

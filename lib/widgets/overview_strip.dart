import 'package:flutter/material.dart';

import '../models/node_model.dart';
import '../services/node_repository.dart';
import '../utils/risk_utils.dart';

/// Headline figures across all nodes, like an incident liveboard: what an
/// officer needs at a glance before drilling into one node.
class OverviewStrip extends StatelessWidget {
  const OverviewStrip({super.key, required this.repository});

  final NodeRepository repository;

  static const _order = ['LOW', 'MEDIUM', 'MODERATE', 'HIGH', 'CRITICAL'];

  @override
  Widget build(BuildContext context) {
    final nodes = repository.nodes;
    final online = nodes.where((n) => n.status == NodeStatus.online).length;
    final openAlerts = repository.openAlerts.length;
    final hotspots = nodes.fold<int>(0, (sum, n) => sum + n.hotspots.length);

    String highest = 'LOW';
    for (final n in nodes) {
      final level = n.detection.riskLevel;
      if (_order.indexOf(level) > _order.indexOf(highest)) highest = level;
    }

    return Row(
      children: [
        _tile(
          context,
          icon: Icons.sensors,
          value: '$online/${nodes.length}',
          label: 'Nodes online',
          color: online == nodes.length ? Colors.green : Colors.orange,
        ),
        _tile(
          context,
          icon: Icons.notifications_active,
          value: '$openAlerts',
          label: 'Open alerts',
          color: openAlerts == 0 ? Colors.green : Colors.red,
        ),
        _tile(
          context,
          icon: Icons.local_fire_department,
          value: highest,
          label: 'Highest risk',
          color: riskColor(highest),
        ),
        _tile(
          context,
          icon: Icons.satellite_alt,
          value: '$hotspots',
          label: 'Satellite fires',
          color: hotspots == 0 ? Colors.green : Colors.red,
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              FittedBox(
                child: Text(
                  value,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

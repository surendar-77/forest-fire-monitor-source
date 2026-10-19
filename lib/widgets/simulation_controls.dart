import 'package:flutter/material.dart';

import '../services/simulation_service.dart';

/// Demo scenarios: tap one to see how the app reacts.
class SimulationControls extends StatelessWidget {
  final SimulationService simulationService;

  const SimulationControls({super.key, required this.simulationService});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _scenario(Icons.check_circle_outline, Colors.green.shade700, 'Normal day',
              'Everything is fine', simulationService.normal),
          const Divider(height: 1, indent: 56),
          _scenario(Icons.cloud_outlined, Colors.orange.shade800, 'Smoke seen',
              'The camera spots smoke', simulationService.smokeDetected),
          const Divider(height: 1, indent: 56),
          _scenario(Icons.warning_amber_rounded, Colors.deepOrange, 'High fire risk',
              'Hot, dry readings point to fire', simulationService.highFireRisk),
          const Divider(height: 1, indent: 56),
          _scenario(Icons.local_fire_department, Colors.red.shade700, 'Fire!',
              'The camera spots flames', simulationService.criticalFire),
        ],
      ),
    );
  }

  Widget _scenario(IconData icon, Color color, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.play_arrow_rounded),
      onTap: onTap,
    );
  }
}

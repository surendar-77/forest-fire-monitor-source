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
          _scenario(
            Icons.check_circle_outline,
            Colors.green.shade700,
            'Normal day',
            'Everything is fine',
            simulationService.normal,
          ),
          const Divider(height: 1, indent: 56),
          _scenario(
            Icons.cloud_outlined,
            Colors.orange.shade800,
            'Smoke seen',
            'The camera spots smoke',
            simulationService.smokeDetected,
          ),
          const Divider(height: 1, indent: 56),
          _scenario(
            Icons.warning_amber_rounded,
            Colors.deepOrange,
            'High fire risk',
            'Hot, dry readings point to fire',
            simulationService.highFireRisk,
          ),
          const Divider(height: 1, indent: 56),
          _scenario(
            Icons.local_fire_department,
            Colors.red.shade700,
            'Fire!',
            'The camera spots flames',
            simulationService.criticalFire,
          ),
        ],
      ),
    );
  }

  Widget _scenario(
    IconData icon,
    Color color,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.play_arrow_rounded),
      onTap: onTap,
    );
  }
}

/// Demo scenarios as one bar over the map, so they're in view the moment
/// demo mode starts (the panel below starts closed).
class DemoScenarioBar extends StatelessWidget {
  final SimulationService simulationService;

  const DemoScenarioBar({super.key, required this.simulationService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: simulationService,
      builder: (context, _) {
        final d = simulationService.data;
        final level = d.riskLevel;
        return Material(
          color: Colors.white,
          elevation: 3,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Demo: tap a scenario',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip(
                      Icons.check_circle_outline,
                      Colors.green.shade700,
                      'Normal',
                      level == 'LOW',
                      simulationService.normal,
                    ),
                    _chip(
                      Icons.cloud_outlined,
                      Colors.orange.shade800,
                      'Smoke',
                      level == 'MODERATE',
                      simulationService.smokeDetected,
                    ),
                    _chip(
                      Icons.warning_amber_rounded,
                      Colors.deepOrange,
                      'High risk',
                      level == 'HIGH',
                      simulationService.highFireRisk,
                    ),
                    _chip(
                      Icons.local_fire_department,
                      Colors.red.shade700,
                      'Fire!',
                      level == 'CRITICAL',
                      simulationService.criticalFire,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${d.temperature.toStringAsFixed(1)}°C · '
                  '${d.humidity.round()}% humidity · '
                  'smoke ${d.smokeProbability.round()}% · '
                  'fire ${d.fireProbability.round()}% · '
                  'risk ${level.toLowerCase()}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(
    IconData icon,
    Color color,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return ChoiceChip(
      avatar: Icon(icon, size: 18, color: selected ? Colors.white : color),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: color,
      labelStyle: TextStyle(
        color: selected ? Colors.white : null,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) => onTap(),
    );
  }
}

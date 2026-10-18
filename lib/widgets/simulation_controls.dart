import 'package:flutter/material.dart';

import '../services/simulation_service.dart';

class SimulationControls extends StatelessWidget {
  final SimulationService simulationService;

  const SimulationControls({super.key, required this.simulationService});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _simulationButton(
          icon: Icons.check_circle,
          title: 'NORMAL',
          subtitle: 'Safe environmental conditions',
          onPressed: simulationService.normal,
        ),

        const SizedBox(height: 10),

        _simulationButton(
          icon: Icons.cloud,
          title: 'SMOKE DETECTED',
          subtitle: 'Smoke detected by AI',
          onPressed: simulationService.smokeDetected,
        ),

        const SizedBox(height: 10),

        _simulationButton(
          icon: Icons.warning_amber_rounded,
          title: 'HIGH FIRE RISK',
          subtitle: 'High probability of fire',
          onPressed: simulationService.highFireRisk,
        ),

        const SizedBox(height: 10),

        _simulationButton(
          icon: Icons.local_fire_department,
          title: 'CRITICAL FIRE',
          subtitle: 'Immediate fire alert',
          onPressed: simulationService.criticalFire,
        ),
      ],
    );
  }

  Widget _simulationButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, size: 30),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                const Icon(Icons.play_arrow, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

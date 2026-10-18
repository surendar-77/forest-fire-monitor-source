import 'package:flutter/material.dart';

class RiskCard extends StatelessWidget {
  final String riskLevel;
  final int riskScore;

  const RiskCard({super.key, required this.riskLevel, required this.riskScore});

  Color get riskColor {
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

  IconData get riskIcon {
    switch (riskLevel) {
      case 'LOW':
        return Icons.check_circle;
      case 'MODERATE':
        return Icons.warning_amber_rounded;
      case 'HIGH':
        return Icons.warning;
      case 'CRITICAL':
        return Icons.local_fire_department;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: riskColor.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(riskIcon, color: riskColor, size: 32),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CURRENT FIRE RISK',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    riskLevel,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: riskColor,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    'Risk Score: $riskScore / 100',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class AlertCard extends StatelessWidget {
  final bool alertActive;
  final String riskLevel;
  final double fireProbability;
  final double smokeProbability;

  const AlertCard({
    super.key,
    required this.alertActive,
    required this.riskLevel,
    required this.fireProbability,
    required this.smokeProbability,
  });

  @override
  Widget build(BuildContext context) {
    if (!alertActive) {
      return Card(
        child: ListTile(
          leading: const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 32,
          ),
          title: const Text(
            'SYSTEM NORMAL',
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text('No active fire alert detected.'),
        ),
      );
    }

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),

        leading: const Icon(
          Icons.warning_amber_rounded,
          color: Colors.red,
          size: 32,
        ),

        title: Text(
          '$riskLevel ALERT',
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),

        subtitle: Text(
          'Fire ${fireProbability.toStringAsFixed(0)}% • '
          'Smoke ${smokeProbability.toStringAsFixed(0)}%',
        ),

        trailing: const Icon(Icons.arrow_forward_ios, size: 18),
      ),
    );
  }
}

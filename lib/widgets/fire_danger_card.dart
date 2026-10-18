import 'package:flutter/material.dart';

import '../models/node_model.dart';

/// Today's ML fire-danger rating for a node, with the weather behind it.
class FireDangerCard extends StatelessWidget {
  const FireDangerCard({super.key, required this.node, this.canSetLocation = false});

  final NodeModel node;
  final bool canSetLocation;

  static Color colorFor(String level) {
    switch (level) {
      case 'VERY HIGH':
        return Colors.red;
      case 'HIGH':
        return Colors.deepOrange;
      case 'MODERATE':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final danger = node.danger;

    if (danger == null) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.local_fire_department_outlined, color: Colors.grey.shade600),
          title: const Text('Fire danger'),
          subtitle: Text(
            node.hasLocation
                ? 'Calculated hourly from weather at the node; first rating soon.'
                : canSetLocation
                ? 'Set this node\'s location (below) to get a daily fire-danger rating.'
                : 'Available once an administrator sets this node\'s location.',
          ),
        ),
      );
    }

    final color = colorFor(danger.level);
    final percent = (danger.probability * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department, color: color),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'FIRE DANGER TODAY',
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    danger.level,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$percent%',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'chance conditions match fire days',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: danger.probability.clamp(0, 1),
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _fact('Noon temp', danger.temperature, '°C', 1),
                _fact('Humidity', danger.humidity, '%', 0),
                _fact('Wind', danger.wind, ' km/h', 0),
                _fact('Rain 24 h', danger.rain24h, ' mm', 1),
                _fact('Fuel dryness (FFMC)', danger.ffmc, '', 0),
                _fact('Spread index (ISI)', danger.isi, '', 1),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${danger.forecast ? 'Based on today\'s noon forecast' : 'Based on today\'s noon weather'}'
              ' · ML model trained on the Algerian Forest Fires dataset (~89% accuracy in tests)',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fact(String label, double? value, String unit, int digits) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
        Text(
          value == null ? '--' : '${value.toStringAsFixed(digits)}$unit',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../models/node_model.dart';
import 'node_status_chip.dart';

class MonitoringNodeCard extends StatelessWidget {
  const MonitoringNodeCard({
    super.key,
    required this.nodeId,
    required this.subtitle,
    required this.status,
  });

  final String nodeId;
  final String subtitle;
  final NodeStatus status;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sensors, color: Colors.red),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nodeId,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),

            NodeStatusChip(status: status),
          ],
        ),
      ),
    );
  }
}

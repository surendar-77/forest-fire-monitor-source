import 'package:flutter/material.dart';

import '../models/node_model.dart';
import '../utils/risk_utils.dart';
import 'node_status_chip.dart';

/// Horizontal strip of every node, highest risk first. Tapping one selects it
/// for the dashboard, map and monitor screens.
class NodeSelector extends StatelessWidget {
  const NodeSelector({
    super.key,
    required this.nodes,
    required this.selectedNodeId,
    required this.onSelected,
  });

  final List<NodeModel> nodes;
  final String? selectedNodeId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.sensors_off, color: Colors.grey.shade600),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'No monitoring nodes yet. Nodes appear here as soon as '
                  'they send their first reading.',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: nodes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final node = nodes[index];
          final selected = node.id == selectedNodeId;
          final levelColor = riskColor(node.detection.riskLevel);

          return SizedBox(
            width: 170,
            child: Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelected(node.id),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              node.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          NodeStatusChip(status: node.status, compact: true),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.circle, size: 10, color: levelColor),
                          const SizedBox(width: 6),
                          Text(
                            '${node.detection.riskLevel} · '
                            '${node.detection.riskScore}',
                            style: TextStyle(
                              color: levelColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        node.zone ?? node.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

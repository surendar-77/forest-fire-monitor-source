import 'package:flutter/material.dart';

import '../models/node_model.dart';

class NodeStatusChip extends StatelessWidget {
  const NodeStatusChip({super.key, required this.status, this.compact = false});

  final NodeStatus status;
  final bool compact;

  static Color colorFor(NodeStatus status) {
    switch (status) {
      case NodeStatus.online:
        return Colors.green;
      case NodeStatus.stale:
        return Colors.orange;
      case NodeStatus.offline:
        return Colors.red;
      case NodeStatus.unknown:
        return Colors.grey;
    }
  }

  static String labelFor(NodeStatus status) {
    switch (status) {
      case NodeStatus.online:
        return 'ONLINE';
      case NodeStatus.stale:
        return 'STALE';
      case NodeStatus.offline:
        return 'OFFLINE';
      case NodeStatus.unknown:
        return 'WAITING';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        labelFor(status),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: compact ? 10 : 12,
        ),
      ),
    );
  }
}

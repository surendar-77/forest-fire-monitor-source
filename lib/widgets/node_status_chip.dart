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
        return 'Online';
      case NodeStatus.stale:
        return 'Stale';
      case NodeStatus.offline:
        return 'Offline';
      case NodeStatus.unknown:
        return 'Waiting';
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
          fontWeight: FontWeight.w600,
          fontSize: compact ? 11 : 12,
        ),
      ),
    );
  }
}

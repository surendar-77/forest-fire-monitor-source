import 'package:flutter/material.dart';

import '../models/alert_model.dart';

/// Plain-language wording shared across screens, so the app reads the same
/// everywhere and avoids system terms (node, severity codes, ALL CAPS).

String titleCase(String text) => text.isEmpty
    ? text
    : text
          .replaceAll('_', ' ')
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => '${w[0]}${w.substring(1).toLowerCase()}')
          .join(' ');

/// "Low", "Medium", "High", "Very high", "Critical".
String levelLabel(String level) {
  final l = titleCase(level);
  return l.isEmpty ? l : '${l[0]}${l.substring(1).toLowerCase()}';
}

/// What happened, in words a field officer would use.
String alertTitle(String type) {
  switch (type.toUpperCase()) {
    case 'FIRE':
    case 'FIRE DETECTED':
    case 'CRITICAL FIRE':
      return 'Fire seen by camera';
    case 'SMOKE':
    case 'SMOKE DETECTED':
      return 'Smoke seen by camera';
    case 'SENSOR_ANOMALY':
      return 'Unusual sensor readings';
    case 'NODE_OFFLINE':
      return 'Sensor went offline';
    case 'SATELLITE_HOTSPOT':
      return 'Satellite spotted a fire nearby';
    case 'HIGH FIRE RISK':
      return 'High fire risk';
    default:
      return levelLabel(type);
  }
}

IconData alertIcon(String type) {
  switch (type.toUpperCase()) {
    case 'SMOKE':
    case 'SMOKE DETECTED':
      return Icons.cloud_outlined;
    case 'SENSOR_ANOMALY':
      return Icons.sensors;
    case 'NODE_OFFLINE':
      return Icons.wifi_off;
    case 'SATELLITE_HOTSPOT':
      return Icons.satellite_alt;
    default:
      return Icons.local_fire_department;
  }
}

Color severityColor(String severity) {
  switch (severity) {
    case 'CRITICAL':
      return Colors.red.shade700;
    case 'HIGH':
      return Colors.deepOrange;
    case 'MODERATE':
    case 'MEDIUM':
      return Colors.orange.shade700;
    case 'LOW':
      return Colors.green.shade700;
    default:
      return Colors.grey.shade600;
  }
}

/// "New", "Being handled", "Resolved".
String alertStatusLabel(String status) {
  switch (status) {
    case AlertStatus.active:
      return 'New';
    case AlertStatus.acknowledged:
      return 'Being handled';
    case AlertStatus.resolved:
      return 'Resolved';
    default:
      return levelLabel(status);
  }
}

Color alertStatusColor(String status) {
  switch (status) {
    case AlertStatus.active:
      return Colors.red.shade700;
    case AlertStatus.acknowledged:
      return Colors.orange.shade800;
    default:
      return Colors.green.shade700;
  }
}

/// "just now", "5 min ago", "3 h ago", "yesterday", "12 Oct".
String timeAgo(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(time);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${time.day} ${months[time.month - 1]}'
      '${time.year == current.year ? '' : ' ${time.year}'}';
}

/// "2:05 PM".
String clockTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${time.hour >= 12 ? 'PM' : 'AM'}';
}

/// "14:00" -> "2 PM".
String hourLabel12(String hhmm) {
  final hour = int.tryParse(hhmm.split(':').first);
  if (hour == null) return hhmm;
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h ${hour >= 12 ? 'PM' : 'AM'}';
}

/// Small rounded label used for statuses.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

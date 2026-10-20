import 'package:flutter/material.dart';

import '../models/alert_model.dart';
import 'friendly.dart';

/// One step in an alert's life: detected, confirmed, notified, handled...
class TimelineEvent {
  const TimelineEvent(this.time, this.title, this.icon, this.color, {this.detail});

  final DateTime time;
  final String title;
  final String? detail;
  final IconData icon;
  final Color color;
}

/// "4 min", "1 h 20 min", "2 days".
String elapsedLabel(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds.clamp(0, 59)} s';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24) {
    final m = d.inMinutes % 60;
    return '${d.inHours} h${m == 0 ? '' : ' $m min'}';
  }
  return '${d.inDays} day${d.inDays == 1 ? '' : 's'}';
}

/// Everything that happened to [alert], oldest first.
List<TimelineEvent> alertTimeline(AlertModel alert) {
  final start = alert.detectedAt;
  String after(DateTime t) => '${elapsedLabel(t.difference(start))} after detection';

  final events = <TimelineEvent>[
    TimelineEvent(
      start,
      alertTitle(alert.type),
      alertIcon(alert.type),
      severityColor(alert.severity),
      detail: alert.message ??
          (alert.isCamera && alert.aiConfidence != null
              ? 'Camera AI ${(alert.aiConfidence! * 100).round()}% sure'
              : null),
    ),
  ];

  if (alert.pushedAt != null) {
    events.add(TimelineEvent(
      alert.pushedAt!,
      'Notifications sent',
      Icons.notifications_active_outlined,
      Colors.blueGrey,
      detail: 'To phones of everyone following this sensor',
    ));
  }
  if (alert.confirmedAt != null) {
    events.add(TimelineEvent(
      alert.confirmedAt!,
      'Fire confirmed, raised to critical',
      Icons.verified_outlined,
      Colors.red.shade800,
      detail: 'Seen continuously for 2 minutes',
    ));
  }
  if (alert.fireServicesNotifiedAt != null) {
    events.add(TimelineEvent(
      alert.fireServicesNotifiedAt!,
      'Fire stations told',
      Icons.fire_truck_outlined,
      Colors.deepOrange,
      detail: alert.fireServicesNotified.isEmpty
          ? null
          : alert.fireServicesNotified.join(', '),
    ));
  }
  if (alert.escalatedAt != null && alert.escalationLevel > 0) {
    events.add(TimelineEvent(
      alert.escalatedAt!,
      alert.escalationLevel >= 2
          ? 'Escalated to administrators'
          : 'Reminder sent: nobody acknowledged',
      Icons.priority_high,
      Colors.orange.shade800,
    ));
  }
  if (alert.acknowledgedAt != null) {
    events.add(TimelineEvent(
      alert.acknowledgedAt!,
      'Acknowledged by ${alert.acknowledgedBy ?? 'a responder'}',
      Icons.directions_run,
      Colors.blue.shade700,
      detail: after(alert.acknowledgedAt!),
    ));
  }
  if (alert.verdictAt != null && alert.verdict != null) {
    final real = alert.verdict == AlertVerdict.real;
    events.add(TimelineEvent(
      alert.verdictAt!,
      '${real ? 'Marked a real fire' : 'Marked a false alarm'} by ${alert.verdictBy ?? 'a responder'}',
      real ? Icons.local_fire_department : Icons.block,
      real ? Colors.red.shade700 : Colors.grey.shade700,
    ));
  }
  if (alert.lastDetectedAt != null &&
      alert.detections > 1 &&
      alert.lastDetectedAt!.isAfter(start)) {
    events.add(TimelineEvent(
      alert.lastDetectedAt!,
      'Last seen by the sensor',
      Icons.history,
      Colors.grey.shade600,
      detail: 'Reported ${alert.detections} times',
    ));
  }
  if (alert.resolvedAt != null) {
    events.add(TimelineEvent(
      alert.resolvedAt!,
      'Resolved by ${alert.resolvedBy ?? 'a responder'}',
      Icons.task_alt,
      Colors.green.shade700,
      detail: [
        if (alert.outcome != null) AlertOutcome.label(alert.outcome),
        after(alert.resolvedAt!),
      ].join(' · '),
    ));
  }

  events.sort((a, b) => a.time.compareTo(b.time));
  return events;
}

/// The timeline as a vertical list with a connecting line.
class AlertTimelineView extends StatelessWidget {
  const AlertTimelineView({super.key, required this.alert});

  final AlertModel alert;

  @override
  Widget build(BuildContext context) {
    final events = alertTimeline(alert);
    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 34,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: events[i].color.withValues(alpha: 0.12),
                        child: Icon(events[i].icon, size: 16, color: events[i].color),
                      ),
                      if (i < events.length - 1)
                        Expanded(
                          child: Container(width: 2, color: Colors.grey.shade300),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14, top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          events[i].title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          [
                            '${clockTime(events[i].time)} · ${events[i].time.day}/${events[i].time.month}',
                            ?events[i].detail,
                          ].join(' · '),
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/live_reading.dart';
import '../utils/risk_utils.dart';

/// Per-second readings straight from the node (Realtime Database). Listens
/// only while visible and only to the selected node, to keep the free
/// plan's download allowance for when it matters.
class LiveFeedCard extends StatefulWidget {
  const LiveFeedCard({super.key, required this.nodeId});

  final String nodeId;

  @override
  State<LiveFeedCard> createState() => _LiveFeedCardState();
}

class _LiveFeedCardState extends State<LiveFeedCard> {
  StreamSubscription<DatabaseEvent>? _subscription;
  Timer? _clock;
  LiveReading? _reading;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _listen();
    // Re-render once a second so "updated Xs ago" and the paused state stay
    // correct even when no new sample arrives.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(LiveFeedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      _reading = null;
      _unavailable = false;
      _listen();
    }
  }

  void _listen() {
    _subscription?.cancel();

    final database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: AppConfig.realtimeDatabaseUrl,
    );

    _subscription = database
        .ref('live/${widget.nodeId}/values')
        .onValue
        .listen(
          (event) {
            final value = event.snapshot.value;
            if (!mounted) return;
            setState(() {
              _unavailable = false;
              _reading = value is Map ? LiveReading.fromMap(value) : null;
            });
          },
          onError: (Object error) {
            debugPrint('Live feed error: $error');
            if (mounted) setState(() => _unavailable = true);
          },
        );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  String _ago(DateTime time) {
    final seconds = DateTime.now().difference(time).inSeconds;
    if (seconds < 2) return 'just now';
    if (seconds < 60) return '${seconds}s ago';
    if (seconds < 3600) return '${seconds ~/ 60} min ago';
    return '${seconds ~/ 3600} h ago';
  }

  @override
  Widget build(BuildContext context) {
    final reading = _reading;

    // No live feed set up for this node (or none yet): stay out of the way.
    if (reading == null) {
      if (!_unavailable) return const SizedBox.shrink();
      return Card(
        child: ListTile(
          leading: Icon(Icons.sensors_off, color: Colors.grey.shade600),
          title: const Text('Live feed unavailable'),
          subtitle: const Text('Showing the latest saved readings instead.'),
        ),
      );
    }

    final stale = reading.isStaleAt(DateTime.now());
    final statusColor = stale ? Colors.orange : Colors.green;
    final level = reading.riskLevel ?? 'LOW';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: statusColor),
                const SizedBox(width: 8),
                Text(
                  stale ? 'LIVE FEED PAUSED' : 'LIVE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (reading.time != null)
                  Text(
                    'updated ${_ago(reading.time!)}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                _value('Temp', reading.temperature, '°C', 1),
                _value('Humidity', reading.humidity, '%', 0),
                _value('Smoke 1', reading.smoke1?.toDouble(), '', 0),
                _value('Smoke 2', reading.smoke2?.toDouble(), '', 0),
                if (reading.temperature2 != null)
                  _value('Temp 2', reading.temperature2, '°C', 1),
                _riskValue(reading.riskScore, level),
              ],
            ),
            if (reading.aiClass != null) ...[
              const SizedBox(height: 10),
              Text(
                'Camera AI: ${reading.aiClass}'
                '${reading.aiConfidence == null ? '' : ' (${(reading.aiConfidence! * 100).toStringAsFixed(0)}%)'}',
                style: TextStyle(
                  color: reading.aiClass == 'Normal'
                      ? Colors.grey.shade700
                      : Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (stale) ...[
              const SizedBox(height: 8),
              Text(
                'No per-second data from the node for over '
                '${LiveReading.staleAfter.inSeconds} seconds.',
                style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _value(String label, double? value, String unit, int digits) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
        Text(
          value == null ? '--' : '${value.toStringAsFixed(digits)}$unit',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _riskValue(int? score, String level) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Risk', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
        Text(
          score == null ? '--' : '$score $level',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: riskColor(level),
          ),
        ),
      ],
    );
  }
}

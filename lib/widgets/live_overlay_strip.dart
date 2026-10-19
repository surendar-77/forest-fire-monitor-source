import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/live_reading.dart';
import '../models/node_model.dart';
import '../utils/friendly.dart';
import '../utils/risk_utils.dart';

/// Floating panel over the Home map with the selected sensor's readings,
/// updated every second from the live feed (falls back to the last saved
/// reading when the live feed is quiet).
class LiveOverlayStrip extends StatefulWidget {
  const LiveOverlayStrip({super.key, required this.node});

  final NodeModel node;

  @override
  State<LiveOverlayStrip> createState() => _LiveOverlayStripState();
}

class _LiveOverlayStripState extends State<LiveOverlayStrip> {
  StreamSubscription<DatabaseEvent>? _subscription;
  Timer? _clock;
  LiveReading? _live;

  @override
  void initState() {
    super.initState();
    _listen();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(LiveOverlayStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _live = null;
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
        .ref('live/${widget.node.id}/values')
        .onValue
        .listen((event) {
          final value = event.snapshot.value;
          if (mounted) {
            setState(
              () => _live = value is Map ? LiveReading.fromMap(value) : null,
            );
          }
        }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final d = node.detection;
    final live = _live;
    final fresh = live != null && !live.isStaleAt(DateTime.now());

    // Live values when the per-second feed is flowing, else the last save.
    final t1 = fresh ? live.temperature : d.temperature;
    final t2 = fresh ? live.temperature2 : d.temperature2;
    final h1 = fresh ? live.humidity : d.humidity;
    final h2 = fresh ? live.humidity2 : d.humidity2;
    final smoke = fresh ? _max(live.smoke1, live.smoke2)?.toDouble() : null;
    final aiClass = fresh ? live.aiClass : null;
    final aiConf = fresh ? live.aiConfidence : null;
    final riskScore = fresh && live.riskScore != null
        ? live.riskScore!
        : d.riskScore;
    final riskLevel = fresh && live.riskLevel != null
        ? live.riskLevel!
        : d.riskLevel;

    final offline =
        node.status == NodeStatus.offline || node.status == NodeStatus.stale;
    final statusColor = fresh
        ? Colors.green
        : (offline ? Colors.red : Colors.orange);
    final statusText = fresh
        ? 'Live'
        : offline
        ? 'Offline'
        : 'Last reading';
    final updated = fresh ? live.time : node.lastSeen;

    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      elevation: 4,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
                if (updated != null)
                  Text(
                    fresh ? _ago(updated) : timeAgo(updated),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _tile(
                  Icons.thermostat,
                  Colors.deepOrange,
                  t1 == null ? '--' : '${t1.toStringAsFixed(1)}°',
                  t2 == null ? 'Temp' : 'Temp · ${t2.toStringAsFixed(0)}°',
                ),
                _tile(
                  Icons.water_drop_outlined,
                  Colors.blue,
                  h1 == null ? '--' : '${h1.toStringAsFixed(0)}%',
                  h2 == null ? 'Humidity' : 'Humid · ${h2.toStringAsFixed(0)}%',
                ),
                _tile(
                  Icons.cloud_outlined,
                  Colors.blueGrey,
                  smoke == null ? '--' : smoke.toStringAsFixed(0),
                  'Smoke',
                ),
                _tile(
                  aiClass == 'Fire'
                      ? Icons.local_fire_department
                      : aiClass == 'Smoke'
                      ? Icons.cloud
                      : Icons.photo_camera_outlined,
                  aiClass == 'Fire'
                      ? Colors.red.shade700
                      : aiClass == 'Smoke'
                      ? Colors.orange.shade800
                      : Colors.green.shade700,
                  aiClass ?? '--',
                  aiConf == null
                      ? 'Camera'
                      : 'Camera ${(aiConf * 100).round()}%',
                ),
                _tile(
                  Icons.shield_outlined,
                  riskColor(riskLevel),
                  levelLabel(riskLevel),
                  'Risk $riskScore',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(IconData icon, Color color, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  static int? _max(int? a, int? b) =>
      a == null ? b : (b == null ? a : (a > b ? a : b));

  String _ago(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    return s < 2 ? 'just now' : '${s}s ago';
  }
}

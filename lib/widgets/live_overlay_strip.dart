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
    // One figure per quantity: the average of both zones' sensors.
    final temp = _average(t1, t2);
    final humidity = _average(h1, h2);
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
                  temp == null ? '--' : '${temp.toStringAsFixed(1)}°C',
                  'Temp',
                ),
                _tile(
                  Icons.water_drop_outlined,
                  Colors.blue,
                  humidity == null ? '--' : '${humidity.toStringAsFixed(0)}%',
                  'Humidity',
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
            if (node.localAir != null &&
                !node.localAir!.isStaleAt(DateTime.now())) ...[
              const SizedBox(height: 8),
              _airQuality(node.localAir!),
            ],
            if (node.danger != null) ...[
              const SizedBox(height: 8),
              _firePrediction(node.danger!),
            ],
          ],
        ),
      ),
    );
  }

  /// Air at the sensor from the smoke sensors: clean, smoke or gas.
  Widget _airQuality(LocalAir air) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: air.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(air.icon, size: 18, color: air.color),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Air at sensor: '),
                  TextSpan(
                    text: air.label,
                    style: TextStyle(fontWeight: FontWeight.w700, color: air.color),
                  ),
                  if (air.status != 'CLEAN' && air.detail.isNotEmpty)
                    TextSpan(text: ' · ${air.detail}'),
                ],
              ),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// The ML fire-danger prediction for today and the riskiest hour ahead.
  Widget _firePrediction(FireDanger danger) {
    final color = _dangerColor(danger.level);
    final peak = danger.peak;
    final riskyPeak = peak != null && peak.level != 'LOW';
    final chance = danger.chance;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.local_fire_department_outlined, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Fire prediction today: '),
                  TextSpan(
                    text: levelLabel(danger.level),
                    style: TextStyle(fontWeight: FontWeight.w700, color: color),
                  ),
                  if (chance != null)
                    TextSpan(
                      text:
                          ' · ${chance < 0.01 ? '<1' : (chance * 100).toStringAsFixed(0)}% chance',
                    ),
                  TextSpan(
                    text: riskyPeak
                        ? ' · riskiest ${hourLabel12(peak.hourLabel)}'
                        : ' · no risky hours ahead',
                  ),
                ],
              ),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  static Color _dangerColor(String level) {
    switch (level) {
      case 'HIGH':
      case 'VERY HIGH':
        return Colors.red.shade700;
      case 'MEDIUM':
      case 'MODERATE':
        return Colors.orange.shade800;
      default:
        return Colors.green.shade700;
    }
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

  static double? _average(double? a, double? b) =>
      a == null ? b : (b == null ? a : (a + b) / 2);

  static int? _max(int? a, int? b) =>
      a == null ? b : (b == null ? a : (a > b ? a : b));

  String _ago(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    return s < 2 ? 'just now' : '${s}s ago';
  }
}

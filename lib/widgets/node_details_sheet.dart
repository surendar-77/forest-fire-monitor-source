import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/live_reading.dart';
import '../models/node_health.dart';
import '../models/node_model.dart';
import '../models/terrain.dart';
import '../utils/friendly.dart';
import '../utils/risk_utils.dart';
import 'node_status_chip.dart';

/// Everything about one sensor: live readings, power, Wi-Fi, the board and
/// each sensor's health. Opened by tapping the sensor on the map.
Future<void> showNodeDetails(
  BuildContext context,
  NodeModel node, {
  VoidCallback? onDirections,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 1,
      builder: (context, scrollController) => NodeDetails(
        node: node,
        scrollController: scrollController,
        onDirections: onDirections,
      ),
    ),
  );
}

class NodeDetails extends StatefulWidget {
  const NodeDetails({
    super.key,
    required this.node,
    this.scrollController,
    this.onDirections,
    this.liveStream,
    this.healthStream,
  });

  final NodeModel node;
  final ScrollController? scrollController;
  final VoidCallback? onDirections;

  /// For tests; default to the Realtime Database.
  final Stream<LiveReading?>? liveStream;
  final Stream<NodeHealth?>? healthStream;

  @override
  State<NodeDetails> createState() => _NodeDetailsState();
}

class _NodeDetailsState extends State<NodeDetails> {
  LiveReading? _live;
  NodeHealth? _health;
  bool _healthLoaded = false;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _subscriptions.add(
      (widget.liveStream ?? _rtdb('live/${widget.node.id}/values').map(
            (v) => v is Map ? LiveReading.fromMap(v) : null,
          ))
          .listen(
            (live) {
              if (mounted) setState(() => _live = live);
            },
            onError: (Object _) {},
          ),
    );
    _subscriptions.add(
      (widget.healthStream ?? _rtdb('health/${widget.node.id}/info').map(
            (v) => v is Map ? NodeHealth.fromMap(v) : null,
          ))
          .listen(
            (health) {
              if (mounted) {
                setState(() {
                  _health = health;
                  _healthLoaded = true;
                });
              }
            },
            onError: (Object _) {
              if (mounted) setState(() => _healthLoaded = true);
            },
          ),
    );
    // Keeps "x s ago" current.
    _clock = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  Stream<Object?> _rtdb(String path) {
    final database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: AppConfig.realtimeDatabaseUrl,
    );
    return database.ref(path).onValue.map((event) => event.snapshot.value);
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final health = _health;
    final healthFresh = health != null && !health.isStaleAt(now);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _header(context, now),
        const SizedBox(height: 12),
        if (_healthLoaded && health == null)
          _notice(
            Icons.system_update_alt,
            Colors.blueGrey,
            "This sensor hasn't sent a health report yet. Power, Wi-Fi and board "
            'details appear after its firmware is updated.',
          )
        else if (health != null && !healthFresh)
          _notice(
            Icons.history,
            Colors.orange,
            'Last health report ${timeAgo(health.time ?? now, now: now)}. '
            'The details below may be out of date.',
          ),
        _readings(now),
        if (health != null) ...[
          _power(health),
          _wifi(health),
          _sensors(health),
          _board(health),
        ],
        _place(),
      ],
    );
  }

  // --- sections ---------------------------------------------------------------

  Widget _header(BuildContext context, DateTime now) {
    final node = widget.node;
    final status = node.statusAt(now);
    final seen = node.lastSeen;
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: NodeStatusChip.colorFor(
            status,
          ).withValues(alpha: 0.12),
          child: Icon(Icons.sensors, color: NodeStatusChip.colorFor(status)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                node.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  NodeStatusChip.labelFor(status),
                  if (seen != null) 'data ${timeAgo(seen, now: now)}',
                  if (node.zone != null) node.zone!,
                ].join(' · '),
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ],
          ),
        ),
        if (widget.onDirections != null && node.hasLocation)
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.pop(context);
              widget.onDirections!();
            },
            icon: const Icon(Icons.directions, size: 18),
            label: const Text('Directions'),
          ),
      ],
    );
  }

  Widget _readings(DateTime now) {
    final d = widget.node.detection;
    final live = _live;
    final fresh = live != null && !live.isStaleAt(now);
    final t1 = fresh ? live.temperature : d.temperature;
    final h1 = fresh ? live.humidity : d.humidity;
    final t2 = fresh ? live.temperature2 : d.temperature2;
    final h2 = fresh ? live.humidity2 : d.humidity2;
    final risk = fresh ? live.riskScore : d.riskScore;
    final level = (fresh ? live.riskLevel : null) ?? d.riskLevel;

    String temp(double? v) => v == null ? '--' : '${v.toStringAsFixed(1)} °C';
    String hum(double? v) => v == null ? '--' : '${v.round()} %';

    return _Section(
      title: fresh ? 'Live readings' : 'Latest readings',
      trailing: fresh
          ? Pill(live.viaLora ? 'Live via LoRa' : 'Live', color: Colors.green)
          : null,
      children: [
        _Row(Icons.thermostat, 'Temperature', '${temp(t1)}  ·  ${temp(t2)}',
            hint: 'Sensor 1 · sensor 2'),
        _Row(Icons.water_drop_outlined, 'Humidity', '${hum(h1)}  ·  ${hum(h2)}',
            hint: 'Sensor 1 · sensor 2'),
        _Row(
          Icons.cloud_outlined,
          'Smoke (MQ-2)',
          fresh && live.smoke1 != null ? '${live.smoke1}' : '--',
          hint: 'Raw level, 0-4095; rises with smoke',
        ),
        if (widget.node.localAir != null)
          _Row(
            widget.node.localAir!.icon,
            'Air at the sensor',
            widget.node.localAir!.label,
            hint: widget.node.localAir!.detail,
            color: widget.node.localAir!.status == 'CLEAN'
                ? null
                : widget.node.localAir!.color,
          ),
        _Row(
          Icons.local_fire_department_outlined,
          'Fire risk',
          risk == null ? '--' : '$risk / 100 · ${levelLabel(level)}',
          color: riskColor(level),
        ),
        _Row(
          Icons.photo_camera_outlined,
          'Camera AI',
          fresh && live.aiClass != null
              ? '${live.aiClass}'
                    '${live.aiConfidence == null ? '' : ' · ${(live.aiConfidence! * 100).round()}% sure'}'
              : '--',
          color: fresh && live.aiClass == 'Fire'
              ? Colors.red
              : fresh && live.aiClass == 'Smoke'
              ? Colors.orange
              : null,
        ),
      ],
    );
  }

  Widget _power(NodeHealth h) {
    final advice = h.restartAdvice;
    return _Section(
      title: 'Power',
      children: [
        if (h.hasBattery) ...[
          _Row(
            h.charging == true
                ? Icons.battery_charging_full
                : Icons.battery_std,
            'Battery',
            [
              if (h.batteryPercent != null) '${h.batteryPercent}%',
              if (h.batteryVolts != null)
                '${h.batteryVolts!.toStringAsFixed(2)} V',
            ].join(' · '),
            color: (h.batteryPercent ?? 100) <= 20 ? Colors.red : null,
          ),
          if (h.charging != null)
            _Row(
              Icons.power_outlined,
              'Charging',
              h.charging! ? 'Charging' : 'Not charging',
              color: h.charging! ? Colors.green : null,
            ),
        ] else
          const _Row(
            Icons.power_outlined,
            'Power source',
            'USB / adapter',
            hint: 'No battery sensor fitted',
          ),
        if (h.uptimeSeconds != null)
          _Row(Icons.timer_outlined, 'Running for', uptimeLabel(h.uptimeSeconds!)),
        _Row(
          Icons.restart_alt,
          'Last restart',
          h.restartText,
          hint: h.starts == null ? null : 'Started ${h.starts} times since setup',
          color: advice != null ? Colors.orange.shade800 : null,
        ),
        if (advice != null)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 2, bottom: 6),
            child: Text(
              advice,
              style: TextStyle(color: Colors.orange.shade800, fontSize: 12.5),
            ),
          ),
      ],
    );
  }

  Widget _wifi(NodeHealth h) {
    final rssi = h.rssi;
    final success = h.uploadSuccessPercent;
    if (h.viaLora) return _loraLink(h, success);
    return _Section(
      title: 'Wi-Fi and internet',
      children: [
        if (h.wifiName == null)
          const _Row(
            Icons.wifi_off,
            'Wi-Fi',
            'Not connected',
            color: Colors.red,
          )
        else ...[
          _Row(
            Icons.wifi,
            'Network',
            h.wifiName!,
            hint: '${h.networkLabel}${h.channel == null ? '' : ' · channel ${h.channel}'}',
          ),
          if (rssi != null)
            Builder(
              builder: (_) {
                final (bars, word) = NodeHealth.signal(rssi);
                return _Row(
                  _signalIcon(bars),
                  'Signal',
                  '$word · $rssi dBm',
                  color: NodeHealth.signalColor(bars),
                );
              },
            ),
          if (h.ip != null) _Row(Icons.lan_outlined, 'IP address', h.ip!),
        ],
        if (success != null)
          _Row(
            Icons.cloud_upload_outlined,
            'Cloud uploads',
            '$success% delivered',
            hint: '${h.uploadsSent} sent, ${h.uploadsFailed} failed since start',
            color: success < 90 ? Colors.orange.shade800 : null,
          ),
        if (h.thingSpeak != null)
          _Row(Icons.history, 'History upload', titleCase(h.thingSpeak!)),
      ],
    );
  }

  /// The node has no internet of its own: it sends by LoRa to a gateway.
  Widget _loraLink(NodeHealth h, int? success) {
    final rssi = h.loraRssi;
    return _Section(
      title: 'Connection',
      children: [
        _Row(
          Icons.settings_input_antenna,
          'Link',
          'LoRa radio${h.gateway == null ? '' : ' via gateway ${h.gateway}'}',
          hint: 'The gateway puts the data online',
        ),
        if (rssi != null)
          Builder(
            builder: (_) {
              final (bars, word) = NodeHealth.loraSignal(rssi);
              return _Row(
                _signalIcon(bars),
                'Radio signal at the gateway',
                '$word · $rssi dBm'
                    '${h.loraSnr == null ? '' : ' · SNR ${h.loraSnr!.toStringAsFixed(1)} dB'}',
                color: NodeHealth.signalColor(bars),
              );
            },
          ),
        if (success != null)
          _Row(
            Icons.cloud_upload_outlined,
            'Gateway uploads',
            '$success% delivered',
            hint: '${h.uploadsSent} sent, ${h.uploadsFailed} failed since the gateway started',
            color: success < 90 ? Colors.orange.shade800 : null,
          ),
      ],
    );
  }

  Widget _sensors(NodeHealth h) {
    final camAge = h.cameraAgeSeconds;
    final String camera;
    Color? cameraColor;
    if (camAge == null || camAge < 0) {
      camera = 'No photo received yet';
      cameraColor = Colors.orange.shade800;
    } else if (camAge <= 20) {
      camera = 'Connected · photo ${camAge}s ago';
      cameraColor = Colors.green;
    } else {
      camera = 'No photo for ${uptimeLabel(camAge)}';
      cameraColor = Colors.red;
    }
    final smokeOk = h.smokeSensor == null || h.smokeSensor!.startsWith('ok');

    String dht(bool? ok) => ok == null ? '--' : (ok ? 'Working' : 'No reading');

    return _Section(
      title: 'Sensors',
      children: [
        _Row(
          Icons.thermostat,
          'Temperature/humidity',
          'Sensor 1: ${dht(h.dht1Ok)} · Sensor 2: ${dht(h.dht2Ok)}',
          color: h.dht1Ok == false || h.dht2Ok == false ? Colors.red : null,
        ),
        _Row(
          Icons.cloud_outlined,
          'Smoke sensor',
          smokeOk ? 'Working' : h.smokeSensor!,
          hint: smokeOk && (h.smokeSensor?.contains('MQ2 not installed') ?? false)
              ? 'Second smoke sensor not fitted'
              : null,
          color: smokeOk ? null : Colors.red,
        ),
        _Row(
          Icons.photo_camera_outlined,
          'Camera',
          camera,
          hint: h.aiMilliseconds == null || h.aiMilliseconds == 0
              ? null
              : 'AI checks each photo in ${(h.aiMilliseconds! / 1000).toStringAsFixed(1)} s'
                    '${h.cameraFrames == null ? '' : ' · ${h.cameraFrames} photos'}',
          color: cameraColor,
        ),
        if (h.lora != null)
          _Row(
            Icons.settings_input_antenna,
            'LoRa radio',
            titleCase(h.lora!),
            hint: h.loraSent == null ? null : '${h.loraSent} packets sent',
          ),
        if (widget.node.lora != null)
          _Row(
            Icons.cell_tower,
            'LoRa reception',
            widget.node.lora!.quality,
            hint: widget.node.lora!.rssi == null
                ? null
                : '${widget.node.lora!.rssi} dBm at ${widget.node.lora!.gateway}',
          ),
      ],
    );
  }

  Widget _board(NodeHealth h) {
    final chipT = h.chipTemperature;
    final free = h.freeMemory;
    return _Section(
      title: 'Board',
      children: [
        if (chipT != null)
          _Row(
            Icons.device_thermostat,
            'Chip temperature',
            '${chipT.toStringAsFixed(0)} °C',
            color: chipT >= 75 ? Colors.red : null,
            hint: chipT >= 75 ? 'Hot: keep the box shaded and ventilated' : null,
          ),
        if (free != null)
          _Row(
            Icons.memory,
            'Free memory',
            memoryLabel(free),
            hint: h.lowestFreeMemory == null
                ? null
                : 'Lowest ${memoryLabel(h.lowestFreeMemory!)}'
                      '${h.freePsram == null ? '' : ' · ${memoryLabel(h.freePsram!)} camera memory free'}',
            color: free < 40 * 1024 ? Colors.orange.shade800 : null,
          ),
        if (h.hotspotClients != null)
          _Row(
            Icons.wifi_tethering,
            'Own Wi-Fi (FireDetector)',
            '${h.hotspotClients} device${h.hotspotClients == 1 ? '' : 's'} connected',
            hint: 'The camera joins this network',
          ),
        if (h.firmware != null)
          _Row(Icons.system_update_alt, 'Firmware', h.firmware!),
        _Row(Icons.tag, 'Sensor ID', widget.node.id),
      ],
    );
  }

  Widget _place() {
    final node = widget.node;
    final terrain = node.terrain == null ? null : Terrain.byId(node.terrain);
    return _Section(
      title: 'Place',
      children: [
        _Row(
          Icons.place_outlined,
          'Location',
          node.hasLocation
              ? '${node.latitude.toStringAsFixed(5)}, ${node.longitude.toStringAsFixed(5)}'
              : 'Not set',
        ),
        if (terrain != null) _Row(Icons.forest_outlined, 'Terrain', terrain.label),
      ],
    );
  }

  Widget _notice(IconData icon, Color color, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  static IconData _signalIcon(int bars) => switch (bars) {
    4 => Icons.signal_wifi_4_bar,
    3 => Icons.network_wifi_3_bar,
    2 => Icons.network_wifi_2_bar,
    1 => Icons.network_wifi_1_bar,
    _ => Icons.signal_wifi_0_bar,
  };
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const Spacer(),
                ?trailing,
              ],
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.label, this.value, {this.hint, this.color});

  final IconData icon;
  final String label;
  final String value;
  final String? hint;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: color ?? Colors.grey.shade700),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/node_model.dart';
import '../utils/friendly.dart';

/// LoRa signal between the sensor and the receiver board: bars, a plain
/// grade, and the numbers (RSSI, SNR, packet loss) underneath.
class LoraCard extends StatefulWidget {
  const LoraCard({super.key, required this.link});

  /// Null until a receiver board has reported this sensor.
  final LoraLink? link;

  @override
  State<LoraCard> createState() => _LoraCardState();
}

class _LoraCardState extends State<LoraCard> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Keeps "x min ago" and the offline state current between reports.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  static Color _colorFor(int bars) {
    switch (bars) {
      case 4:
      case 3:
        return Colors.green.shade700;
      case 2:
        return Colors.amber.shade800;
      case 1:
        return Colors.orange.shade800;
      default:
        return Colors.red.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final muted = Colors.grey.shade600;

    if (link == null) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.settings_input_antenna, color: muted),
          title: const Text('LoRa signal'),
          subtitle: Text(
            'No LoRa receiver is reporting this sensor yet.',
            style: TextStyle(color: muted),
          ),
        ),
      );
    }

    final stale = link.isStaleAt(DateTime.now());
    final bars = stale ? 0 : link.bars;
    final color = stale ? muted : _colorFor(bars);
    final title = stale
        ? 'Receiver offline'
        : link.packets == 0
        ? 'No packets heard'
        : link.quality;
    final lastPacket = link.lastPacketAt;

    final facts = <String>[
      if (!stale && link.rssi != null) '${link.rssi} dBm',
      if (!stale && link.snr != null) 'SNR ${link.snr!.toStringAsFixed(1)} dB',
      if (!stale && link.lossPercent != null)
        '${link.lossPercent}% packets lost',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _Bars(bars: bars, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LoRa signal',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (facts.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      facts.join(' · '),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (lastPacket != null)
                        'last packet ${timeAgo(lastPacket)}',
                      if (stale && link.updatedAt != null)
                        'receiver last reported ${timeAgo(link.updatedAt!)}',
                      if (link.gateway.isNotEmpty) 'via ${link.gateway}',
                    ].join(' · '),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Four rising signal bars, [bars] of them filled.
class _Bars extends StatelessWidget {
  const _Bars({required this.bars, required this.color});

  final int bars;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 30,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 1; i <= 4; i++)
            Container(
              width: 6,
              height: 6.0 + i * 6,
              decoration: BoxDecoration(
                color: i <= bars ? color : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

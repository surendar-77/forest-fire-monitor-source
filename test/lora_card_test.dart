import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forest_fire_monitor/models/node_model.dart';
import 'package:forest_fire_monitor/widgets/lora_card.dart';

Future<void> _pump(WidgetTester tester, LoraLink? link) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: LoraCard(link: link)),
  ),
);

void main() {
  test('LoRa link parses from the backend map', () {
    final link = LoraLink.fromMap({
      'rssi': -91,
      'snr': 7.5,
      'packets': 23,
      'lost': 1,
      'lossPercent': 4,
      'quality': 'Good',
      'bars': 3,
      'gateway': 'GW-01',
      'updatedAt': DateTime(2026, 10, 19, 10),
    })!;
    expect(link.rssi, -91);
    expect(link.bars, 3);
    expect(link.isStaleAt(DateTime(2026, 10, 19, 10, 2)), isFalse);
    expect(link.isStaleAt(DateTime(2026, 10, 19, 10, 5)), isTrue);
  });

  testWidgets('shows grade and numbers for a fresh report', (tester) async {
    await _pump(
      tester,
      LoraLink(
        rssi: -91,
        snr: 7.5,
        packets: 23,
        lost: 1,
        lossPercent: 4,
        quality: 'Good',
        bars: 3,
        gateway: 'GW-01',
        updatedAt: DateTime.now(),
        lastPacketAt: DateTime.now(),
      ),
    );
    expect(find.text('Good'), findsOneWidget);
    expect(find.textContaining('-91 dBm'), findsOneWidget);
    expect(find.textContaining('4% packets lost'), findsOneWidget);
  });

  testWidgets('an old report means the receiver is offline', (tester) async {
    await _pump(
      tester,
      LoraLink(
        rssi: -91,
        quality: 'Good',
        bars: 3,
        packets: 20,
        updatedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
    );
    expect(find.text('Receiver offline'), findsOneWidget);
    expect(find.textContaining('dBm'), findsNothing);
  });

  testWidgets('no receiver yet', (tester) async {
    await _pump(tester, null);
    expect(find.textContaining('No LoRa receiver'), findsOneWidget);
  });
}

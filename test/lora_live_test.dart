import 'package:flutter_test/flutter_test.dart';
import 'package:forest_fire_monitor/models/live_reading.dart';

void main() {
  test('LoRa-relayed live data stays live for 45 s, the node feed for 10 s', () {
    final now = DateTime(2026, 10, 20, 21, 0, 0);
    final ts = now.subtract(const Duration(seconds: 25)).millisecondsSinceEpoch;

    final lora = LiveReading.fromMap({'ts': ts, 't1': 27.7, 'via': 'lora'});
    expect(lora.viaLora, isTrue);
    expect(lora.isStaleAt(now), isFalse);
    expect(lora.isStaleAt(now.add(const Duration(seconds: 30))), isTrue);

    final direct = LiveReading.fromMap({'ts': ts, 't1': 27.7});
    expect(direct.viaLora, isFalse);
    expect(direct.isStaleAt(now), isTrue);
  });
}

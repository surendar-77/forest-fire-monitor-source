import 'package:flutter_test/flutter_test.dart';
import 'package:forest_fire_monitor/utils/friendly.dart';

void main() {
  test('distanceLabel rounds to what a driver needs', () {
    expect(distanceLabel(0), '0 m');
    expect(distanceLabel(847), '850 m');
    expect(distanceLabel(4230), '4.2 km');
    expect(distanceLabel(37400), '37 km');
  });

  test('durationLabel never shows 0 and splits hours', () {
    expect(durationLabel(5), '1 min');
    expect(durationLabel(18 * 60), '18 min');
    expect(durationLabel(60 * 60), '1 h');
    expect(durationLabel(85 * 60), '1 h 25 min');
  });
}

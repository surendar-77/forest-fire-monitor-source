import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forest_fire_monitor/models/detection_model.dart';
import 'package:forest_fire_monitor/models/node_model.dart';
import 'package:forest_fire_monitor/widgets/fire_danger_card.dart';

NodeModel _node(FireDanger? danger) => NodeModel(
  id: 'NODE-01',
  name: 'Node 1',
  detection: const DetectionModel(
    deviceId: 'NODE-01',
    temperature: 30,
    humidity: 40,
    fireProbability: 0,
    smokeProbability: 0,
    latitude: 21.85,
    longitude: 86.35,
    riskScore: 10,
    riskLevel: 'LOW',
    alertActive: false,
  ),
  reportedStatus: 'ONLINE',
  hasLocation: true,
  danger: danger,
);

void main() {
  testWidgets(
    'fire weather shows a plain verdict and a gradient forecast chart',
    (tester) async {
      // Risk rising to High in the afternoon, back to Low at night.
      final hours = [
        for (var h = 0; h < 24; h++)
          DangerHour(
            '2026-04-10T${(h + 9) % 24 < 10 ? '0' : ''}${(h + 9) % 24}:00',
            h < 6 ? 0.2 + h * 0.1 : (h < 10 ? 0.8 : 0.1),
            h >= 4 && h < 10 ? 'HIGH' : 'LOW',
          ),
      ];
      final danger = FireDanger(
        probability: 0.7,
        level: 'HIGH',
        chance: 0.25,
        averageChance: 0.042,
        timeline: hours,
        peak: hours[6],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FireDangerCard(node: _node(danger)),
            ),
          ),
        ),
      );

      expect(find.text('High'), findsOneWidget);
      expect(find.textContaining('Fires start easily'), findsOneWidget);
      expect(find.textContaining('Riskiest time: 3 PM'), findsOneWidget);
      expect(find.text('Risk forecast, next 24 hours'), findsOneWidget);

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      final line = chart.data.lineBarsData.single;
      expect(line.spots, hasLength(24));
      expect(line.gradient, isNotNull);
      // Low hours draw green, high hours red.
      final colors = (line.gradient! as LinearGradient).colors;
      expect(colors.first.g > colors.first.r, isTrue);
      expect(colors[8].r > colors[8].g, isTrue);
    },
  );

  testWidgets('without a location it explains what to do', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FireDangerCard(node: _node(null), canEdit: true)),
      ),
    );
    expect(find.byType(LineChart), findsNothing);
  });
}

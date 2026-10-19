import 'package:flutter_test/flutter_test.dart';
import 'package:forest_fire_monitor/models/alert_model.dart';
import 'package:forest_fire_monitor/models/detection_model.dart';
import 'package:forest_fire_monitor/models/node_model.dart';
import 'package:forest_fire_monitor/utils/fire_areas.dart';
import 'package:latlong2/latlong.dart';

final now = DateTime.utc(2026, 4, 10, 14);

NodeModel node({
  FireSpread? spread,
  List<SatelliteHotspot> hotspots = const [],
}) => NodeModel(
  id: 'NODE-01',
  name: 'Node 1',
  detection: const DetectionModel(
    deviceId: 'NODE-01',
    temperature: 38,
    humidity: 20,
    fireProbability: 90,
    smokeProbability: 0,
    latitude: 21.85,
    longitude: 86.35,
    riskScore: 100,
    riskLevel: 'HIGH',
    alertActive: true,
  ),
  reportedStatus: 'ONLINE',
  hasLocation: true,
  danger: spread == null
      ? null
      : FireDanger(probability: 0.8, level: 'HIGH', spread: spread),
  hotspots: hotspots,
);

AlertModel alert(
  Duration ago, {
  String status = AlertStatus.active,
  String type = 'FIRE',
  bool confirmed = true,
  Duration? lastSeenAgo,
}) => AlertModel(
  id: 'a-${ago.inMinutes}-$type',
  deviceId: 'NODE-01',
  type: type,
  severity: 'HIGH',
  fireProbability: 90,
  smokeProbability: 0,
  temperature: 38,
  humidity: 20,
  latitude: 21.85,
  longitude: 86.35,
  detectedAt: now.subtract(ago),
  status: status,
  confirmedAt: confirmed
      ? now.subtract(ago).add(const Duration(minutes: 2))
      : null,
  lastDetectedAt: now.subtract(lastSeenAgo ?? Duration.zero),
);

const windySpread = FireSpread(
  headRos: 20, // m/min
  backRos: 2,
  lengthToBreadth: 2.5,
  towardDeg: 90, // spreading east
  towardCompass: 'E',
  headDistance1h: 1200,
  backDistance1h: 120,
  windKmh: 25,
  fuelModel: 'C-3',
  note: 'test',
);

double maxDistance(List<LatLng> pts, LatLng c) => pts
    .map((p) => const Distance().as(LengthUnit.Meter, c, p))
    .reduce((a, b) => a > b ? a : b);

void main() {
  test(
    'an open fire alert gives an active area and a larger possible-spread area',
    () {
      final areas = estimateFireAreas(
        nodes: [node(spread: windySpread)],
        alerts: [alert(const Duration(minutes: 30))],
        now: now,
      );
      expect(areas, hasLength(2));
      final active = areas.firstWhere((a) => a.status == FireAreaStatus.active);
      final possible = areas.firstWhere(
        (a) => a.status == FireAreaStatus.possible,
      );
      const c = LatLng(21.85, 86.35);
      expect(active.title, 'Fire');
      // 30 min at 20 m/min head spread: roughly 600 m east of the sensor.
      expect(maxDistance(active.points, c), inInclusiveRange(450, 750));
      expect(
        maxDistance(possible.points, c),
        greaterThan(maxDistance(active.points, c)),
      );
      // Grows downwind: the farthest point is east of the sensor.
      final far = active.points.reduce(
        (a, b) =>
            const Distance().as(LengthUnit.Meter, c, a) >
                const Distance().as(LengthUnit.Meter, c, b)
            ? a
            : b,
      );
      expect(far.longitude, greaterThan(c.longitude));
    },
  );

  test('a just-detected fire is at least the sensor footprint', () {
    final areas = estimateFireAreas(
      nodes: [node()],
      alerts: [alert(Duration.zero)],
      now: now,
    );
    final active = areas.firstWhere((a) => a.status == FireAreaStatus.active);
    expect(
      maxDistance(active.points, const LatLng(21.85, 86.35)),
      greaterThanOrEqualTo(minActiveRadiusM * 0.9),
    );
  });

  test('resolved, old, or non-fire alerts draw nothing', () {
    expect(
      estimateFireAreas(
        nodes: [node()],
        alerts: [
          alert(const Duration(minutes: 5), status: AlertStatus.resolved),
        ],
        now: now,
      ),
      isEmpty,
    );
    expect(
      estimateFireAreas(
        nodes: [node()],
        alerts: [alert(const Duration(hours: 7))],
        now: now,
      ),
      isEmpty,
    );
    expect(
      estimateFireAreas(
        nodes: [node()],
        alerts: [alert(const Duration(minutes: 5), type: 'NODE_OFFLINE')],
        now: now,
      ),
      isEmpty,
    );
  });

  test('nearby satellite detections merge into one area', () {
    final hotspots = [
      const SatelliteHotspot(
        latitude: 21.90,
        longitude: 86.40,
        acquired: '2026-04-10 08:00',
        confidence: 'high',
        distanceKm: 7,
      ),
      const SatelliteHotspot(
        latitude: 21.903,
        longitude: 86.402,
        acquired: '2026-04-10 08:00',
        confidence: 'nominal',
        distanceKm: 7,
      ),
      const SatelliteHotspot(
        latitude: 22.10,
        longitude: 86.60,
        acquired: '2026-04-09 20:00',
        confidence: 'nominal',
        distanceKm: 35,
      ),
    ];
    final areas = estimateFireAreas(
      nodes: [node(hotspots: hotspots)],
      alerts: const [],
      now: now,
    );
    expect(areas, hasLength(2)); // two clusters
    expect(
      areas.where((a) => a.status == FireAreaStatus.active),
      hasLength(1),
    ); // 6 h old
    expect(
      areas.where((a) => a.status == FireAreaStatus.possible),
      hasLength(1),
    ); // 18 h old
    expect(areas.every((a) => a.source == 'NASA satellite'), isTrue);
  });

  test('a fire not yet confirmed (under 2 minutes) draws nothing', () {
    expect(
      estimateFireAreas(
        nodes: [node()],
        alerts: [alert(const Duration(minutes: 1), confirmed: false)],
        now: now,
      ),
      isEmpty,
    );
  });

  test('smoke alerts never draw a fire area', () {
    expect(
      estimateFireAreas(
        nodes: [node()],
        alerts: [alert(const Duration(minutes: 5), type: 'SMOKE')],
        now: now,
      ),
      isEmpty,
    );
  });

  test('a confirmed fire the camera lost sight of turns "possibly active"', () {
    final areas = estimateFireAreas(
      nodes: [node()],
      alerts: [
        alert(
          const Duration(minutes: 40),
          lastSeenAgo: const Duration(minutes: 20),
        ),
      ],
      now: now,
    );
    expect(areas, isNotEmpty);
    expect(areas.every((a) => a.status == FireAreaStatus.possible), isTrue);
  });
}

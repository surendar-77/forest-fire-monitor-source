import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/alert_model.dart';
import '../models/node_model.dart';

/// How sure we are that fire is burning inside an area.
enum FireAreaStatus { active, possible }

/// An estimated fire area for the map: a boundary polygon plus the label
/// shown on it ("Severe fire · Estimated fire area · Updated 5 min ago").
class FireArea {
  const FireArea({
    required this.id,
    required this.status,
    required this.points,
    required this.center,
    required this.title,
    required this.updatedAt,
    required this.source,
    this.alertId,
  });

  final String id;
  final FireAreaStatus status;
  final List<LatLng> points;
  final LatLng center;
  final String title;
  final DateTime updatedAt;

  /// "Sensor NODE-01" or "NASA satellite".
  final String source;
  final String? alertId;
}

/// Sensor fires older than this are no longer drawn.
const Duration sensorFireMaxAge = Duration(hours: 6);

/// The area a sensor watches: a detected fire is at least this big.
const double minActiveRadiusM = 60;
const double minPossibleRadiusM = 180;

/// Spread growth is projected at most this far (the model is a rough
/// estimate; beyond a couple of hours it means little).
const Duration maxSpreadProjection = Duration(hours: 2);
const Duration possibleLookAhead = Duration(hours: 1);

/// Estimated fire areas from open fire/smoke alerts (grown with the FBP
/// spread estimate since detection) and from NASA satellite detections
/// (clusters, buffered by the 375 m VIIRS pixel).
List<FireArea> estimateFireAreas({
  required List<NodeModel> nodes,
  required List<AlertModel> alerts,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final areas = <FireArea>[];
  final nodesById = {for (final n in nodes) n.id: n};

  // Newest open fire (or smoke) alert per sensor.
  final latest = <String, AlertModel>{};
  for (final alert in alerts) {
    final type = alert.type.toUpperCase();
    final isFire =
        type == 'FIRE' || type == 'FIRE DETECTED' || type == 'CRITICAL FIRE';
    final isSmoke = type == 'SMOKE' || type == 'SMOKE DETECTED';
    if (!alert.isOpen || !(isFire || isSmoke)) continue;
    if (current.difference(alert.detectedAt) > sensorFireMaxAge) continue;
    final prev = latest[alert.deviceId];
    final prevIsFire = prev != null && prev.type.toUpperCase().contains('FIRE');
    if (prev == null ||
        (isFire && !prevIsFire) ||
        (isFire == prevIsFire && alert.detectedAt.isAfter(prev.detectedAt))) {
      latest[alert.deviceId] = alert;
    }
  }

  for (final entry in latest.entries) {
    final node = nodesById[entry.key];
    final alert = entry.value;
    if (node == null || !node.hasLocation) continue;
    final center = LatLng(node.latitude, node.longitude);
    final isFire = alert.type.toUpperCase().contains('FIRE');
    final elapsed = current.difference(alert.detectedAt);
    final spread = node.danger?.spread;

    areas.add(
      FireArea(
        id: 'sensor-${alert.id}-active',
        status: FireAreaStatus.active,
        points: _spreadArea(center, spread, _clamp(elapsed), minActiveRadiusM),
        center: center,
        title: isFire
            ? (alert.severity == 'CRITICAL' ? 'Severe fire' : 'Fire')
            : 'Smoke seen',
        updatedAt: alert.detectedAt,
        source: 'Sensor ${node.name}',
        alertId: alert.id,
      ),
    );
    areas.add(
      FireArea(
        id: 'sensor-${alert.id}-possible',
        status: FireAreaStatus.possible,
        points: _spreadArea(
          center,
          spread,
          _clamp(elapsed) + possibleLookAhead,
          minPossibleRadiusM,
        ),
        center: center,
        title: 'Possible spread (next hour)',
        updatedAt: alert.detectedAt,
        source: 'Sensor ${node.name}',
        alertId: alert.id,
      ),
    );
  }

  // Satellite detections: cluster points within 1.5 km, buffer each cluster.
  final hotspots = <SatelliteHotspot>[for (final n in nodes) ...n.hotspots];
  final seen = <String>{};
  final unique = hotspots
      .where((h) => seen.add('${h.latitude},${h.longitude}'))
      .toList();
  final clusters = _cluster(unique, 1500);
  for (final (i, cluster) in clusters.indexed) {
    final pts = [for (final h in cluster) LatLng(h.latitude, h.longitude)];
    final center = LatLng(
      pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length,
      pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length,
    );
    final newest = cluster
        .map((h) => _parseFirmsTime(h.acquired) ?? current)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final fresh = current.difference(newest) < const Duration(hours: 12);
    areas.add(
      FireArea(
        id: 'satellite-$i',
        status: fresh ? FireAreaStatus.active : FireAreaStatus.possible,
        points: _bufferedHull(pts, 400),
        center: center,
        title: cluster.length > 2 ? 'Severe fire' : 'Fire',
        updatedAt: newest,
        source: 'NASA satellite',
      ),
    );
  }
  return areas;
}

Duration _clamp(Duration d) => d > maxSpreadProjection
    ? maxSpreadProjection
    : (d.isNegative ? Duration.zero : d);

const double _mPerDegLat = 111320;

LatLng _offset(LatLng c, double northM, double eastM) => LatLng(
  c.latitude + northM / _mPerDegLat,
  c.longitude + eastM / (_mPerDegLat * math.cos(c.latitude * math.pi / 180)),
);

/// FBP-style ellipse after [t] of spread from the ignition point, never
/// smaller than a circle of [minRadius]. Without a spread estimate (no
/// location or weather yet) the area grows slowly and evenly.
List<LatLng> _spreadArea(
  LatLng c,
  FireSpread? s,
  Duration t,
  double minRadius,
) {
  final minutes = t.inSeconds / 60;
  double head, back, lb, toward;
  if (s == null) {
    head = back = 1.0 * minutes;
    lb = 1;
    toward = 0;
  } else {
    head = s.headRos * minutes;
    back = s.backRos * minutes;
    lb = math.max(s.lengthToBreadth, 1);
    toward = s.towardDeg;
  }
  final semiMajor = math.max((head + back) / 2, minRadius);
  final semiMinor = math.max(semiMajor / lb, minRadius);
  final shift = semiMajor > minRadius ? (head - back) / 2 : 0.0;
  final theta = toward * math.pi / 180;
  // Slightly irregular edge so it reads as an estimate, not a geometry.
  return [
    for (var i = 0; i < 64; i++)
      () {
        final a = 2 * math.pi * i / 64;
        final wobble = 1 + 0.06 * math.sin(3 * a) + 0.04 * math.cos(5 * a);
        final along = shift + semiMajor * math.cos(a) * wobble;
        final across = semiMinor * math.sin(a) * wobble;
        return _offset(
          c,
          along * math.cos(theta) - across * math.sin(theta),
          along * math.sin(theta) + across * math.cos(theta),
        );
      }(),
  ];
}

double _distanceM(double lat1, double lon1, double lat2, double lon2) =>
    const Distance().as(
      LengthUnit.Meter,
      LatLng(lat1, lon1),
      LatLng(lat2, lon2),
    );

List<List<SatelliteHotspot>> _cluster(
  List<SatelliteHotspot> points,
  double radiusM,
) {
  final clusters = <List<SatelliteHotspot>>[];
  final used = List<bool>.filled(points.length, false);
  for (var i = 0; i < points.length; i++) {
    if (used[i]) continue;
    final group = [points[i]];
    used[i] = true;
    for (var k = 0; k < group.length; k++) {
      for (var j = 0; j < points.length; j++) {
        if (used[j]) continue;
        if (_distanceM(
              group[k].latitude,
              group[k].longitude,
              points[j].latitude,
              points[j].longitude,
            ) <=
            radiusM) {
          used[j] = true;
          group.add(points[j]);
        }
      }
    }
    clusters.add(group);
  }
  return clusters;
}

/// Convex hull of the points, each widened into a circle of [bufferM]
/// (one satellite pixel is ~375 m across).
List<LatLng> _bufferedHull(List<LatLng> pts, double bufferM) {
  final ring = <LatLng>[
    for (final p in pts)
      for (var i = 0; i < 16; i++)
        _offset(
          p,
          bufferM * math.cos(2 * math.pi * i / 16),
          bufferM * math.sin(2 * math.pi * i / 16),
        ),
  ];
  return _convexHull(ring);
}

List<LatLng> _convexHull(List<LatLng> points) {
  final p = [...points]
    ..sort(
      (a, b) => a.longitude != b.longitude
          ? a.longitude.compareTo(b.longitude)
          : a.latitude.compareTo(b.latitude),
    );
  if (p.length < 3) return p;
  double cross(LatLng o, LatLng a, LatLng b) =>
      (a.longitude - o.longitude) * (b.latitude - o.latitude) -
      (a.latitude - o.latitude) * (b.longitude - o.longitude);
  final lower = <LatLng>[];
  for (final pt in p) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, pt) <= 0) {
      lower.removeLast();
    }
    lower.add(pt);
  }
  final upper = <LatLng>[];
  for (final pt in p.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, pt) <= 0) {
      upper.removeLast();
    }
    upper.add(pt);
  }
  return [
    ...lower.sublist(0, lower.length - 1),
    ...upper.sublist(0, upper.length - 1),
  ];
}

/// FIRMS "2026-10-19 07:42" (UTC).
DateTime? _parseFirmsTime(String text) {
  final t = DateTime.tryParse(text.trim().replaceFirst(' ', 'T'));
  if (t == null) return null;
  return DateTime.utc(t.year, t.month, t.day, t.hour, t.minute);
}

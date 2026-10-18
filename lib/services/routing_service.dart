import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteResult {
  final double distanceMeters;
  final double durationSeconds;
  final List<LatLng> points;

  const RouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.points,
  });
}

class RoutingService {
  static const String _baseUrl =
      'https://router.project-osrm.org/route/v1/driving';

  Future<RouteResult?> getRoute({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) async {
    final url = Uri.parse(
      '$_baseUrl/'
      '$startLongitude,$startLatitude;'
      '$endLongitude,$endLatitude'
      '?overview=full&geometries=geojson',
    );

    try {
      final response = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json['code'] != 'Ok') {
        return null;
      }

      final routes = json['routes'] as List<dynamic>?;

      if (routes == null || routes.isEmpty) {
        return null;
      }

      final route = routes.first as Map<String, dynamic>;

      final distance = (route['distance'] as num).toDouble();

      final duration = (route['duration'] as num).toDouble();

      final geometry = route['geometry'] as Map<String, dynamic>;

      final coordinates = geometry['coordinates'] as List<dynamic>;

      final points = coordinates.map((coordinate) {
        final pair = coordinate as List<dynamic>;

        final longitude = (pair[0] as num).toDouble();

        final latitude = (pair[1] as num).toDouble();

        return LatLng(latitude, longitude);
      }).toList();

      return RouteResult(
        distanceMeters: distance,
        durationSeconds: duration,
        points: points,
      );
    } catch (error) {
      return null;
    }
  }
}

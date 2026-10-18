import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';

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

/// Driving directions from the responder to a node. Uses OpenRouteService
/// when ROUTING_API_KEY is set; otherwise the public OSRM demo server, which
/// is rate-limited and only suitable for development.
class RoutingService {
  static const String _baseUrl =
      'https://router.project-osrm.org/route/v1/driving';

  static const String _orsUrl =
      'https://api.openrouteservice.org/v2/directions/driving-car';

  Future<RouteResult?> getRoute({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) {
    if (AppConfig.routingApiKey.isNotEmpty) {
      return _getOpenRouteServiceRoute(
        startLatitude: startLatitude,
        startLongitude: startLongitude,
        endLatitude: endLatitude,
        endLongitude: endLongitude,
      );
    }

    return _getOsrmRoute(
      startLatitude: startLatitude,
      startLongitude: startLongitude,
      endLatitude: endLatitude,
      endLongitude: endLongitude,
    );
  }

  Future<RouteResult?> _getOpenRouteServiceRoute({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) async {
    final url = Uri.parse(_orsUrl).replace(
      queryParameters: {
        'api_key': AppConfig.routingApiKey,
        'start': '$startLongitude,$startLatitude',
        'end': '$endLongitude,$endLatitude',
      },
    );

    try {
      final response = await http
          .get(url, headers: {'Accept': 'application/geo+json'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>?;

      if (features == null || features.isEmpty) {
        return null;
      }

      final feature = features.first as Map<String, dynamic>;
      final summary =
          (feature['properties'] as Map<String, dynamic>)['summary']
              as Map<String, dynamic>;
      final coordinates =
          (feature['geometry'] as Map<String, dynamic>)['coordinates']
              as List<dynamic>;

      return RouteResult(
        distanceMeters: (summary['distance'] as num? ?? 0).toDouble(),
        durationSeconds: (summary['duration'] as num? ?? 0).toDouble(),
        points: _toLatLngs(coordinates),
      );
    } catch (error) {
      return null;
    }
  }

  Future<RouteResult?> _getOsrmRoute({
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

      return RouteResult(
        distanceMeters: distance,
        durationSeconds: duration,
        points: _toLatLngs(coordinates),
      );
    } catch (error) {
      return null;
    }
  }

  /// GeoJSON coordinates are [longitude, latitude] pairs.
  List<LatLng> _toLatLngs(List<dynamic> coordinates) {
    return coordinates.map((coordinate) {
      final pair = coordinate as List<dynamic>;

      final longitude = (pair[0] as num).toDouble();

      final latitude = (pair[1] as num).toDouble();

      return LatLng(latitude, longitude);
    }).toList();
  }
}

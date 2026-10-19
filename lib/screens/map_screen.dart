import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../config/app_config.dart';
import '../models/alert_model.dart';
import '../models/detection_model.dart';
import '../models/node_model.dart';
import '../utils/friendly.dart';
import '../services/gps_service.dart';
import '../services/location_service.dart';
import '../services/node_repository.dart';
import '../services/routing_service.dart';
import '../services/monitoring_data_source.dart';
import 'location_settings_screen.dart';

class MapScreen extends StatefulWidget {
  final MonitoringDataSource simulationService;

  /// Every live node, shown as its own marker. Null in simulation mode.
  final NodeRepository? repository;
  final String? selectedNodeId;
  final ValueChanged<String>? onNodeSelected;

  const MapScreen({
    super.key,
    required this.simulationService,
    this.repository,
    this.selectedNodeId,
    this.onNodeSelected,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final LocationService _locationService = LocationService();

  final GpsService _gpsService = GpsService();

  final RoutingService _routingService = RoutingService();

  final MapController _mapController = MapController();

  String _locationName = LocationService.defaultName;

  double _latitude = LocationService.defaultLatitude;

  double _longitude = LocationService.defaultLongitude;

  Position? _phonePosition;

  double? _roadDistanceInMeters;

  double? _routeDurationSeconds;

  List<LatLng> _routePoints = [];

  bool _loadingLocation = true;
  bool _loadingGps = false;
  bool _loadingRoute = false;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  NodeModel? get _selectedNode {
    final id = widget.selectedNodeId;
    return id == null ? null : widget.repository?.node(id);
  }

  /// Where routes go and the map centres: the selected live node, or the
  /// on-device location in simulation mode.
  LatLng get _targetLocation {
    final node = _selectedNode;
    return node != null
        ? LatLng(node.latitude, node.longitude)
        : LatLng(_latitude, _longitude);
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.selectedNodeId != widget.selectedNodeId &&
        _selectedNode != null) {
      setState(() {
        _routePoints = [];
        _roadDistanceInMeters = null;
        _routeDurationSeconds = null;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(_targetLocation, 14);
        }
      });
    }
  }

  AlertModel? _worstOpenAlert(List<AlertModel> alerts) {
    final open = alerts.where((alert) => alert.isOpen).toList();

    if (open.isEmpty) {
      return null;
    }

    open.sort(
      (a, b) => _severityPriority(
        b.severity,
      ).compareTo(_severityPriority(a.severity)),
    );

    return open.first;
  }

  Future<void> _loadLocation() async {
    final name = await _locationService.getLocationName();

    final latitude = await _locationService.getLatitude();

    final longitude = await _locationService.getLongitude();

    if (!mounted) {
      return;
    }

    setState(() {
      _locationName = name;
      _latitude = latitude;
      _longitude = longitude;
      _loadingLocation = false;
    });
  }

  // ==================================================
  // PHONE GPS
  // ==================================================

  Future<void> _getPhoneLocation() async {
    setState(() {
      _loadingGps = true;
    });

    try {
      final position = await _gpsService.getCurrentLocation();

      if (!mounted) {
        return;
      }

      if (position == null) {
        _showLocationError();
        return;
      }

      setState(() {
        _phonePosition = position;
        _routePoints = [];
        _roadDistanceInMeters = null;
        _routeDurationSeconds = null;
      });

      _showMessage('Phone location updated.');

      // Automatically calculate the road route.
      await _calculateRoute(showMessage: true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Unable to get phone location.');
    } finally {
      if (mounted) {
        setState(() {
          _loadingGps = false;
        });
      }
    }
  }

  // ==================================================
  // ROAD ROUTING
  // ==================================================

  Future<void> _calculateRoute({bool showMessage = false}) async {
    if (_phonePosition == null) {
      _showMessage('Get your phone location first.');
      return;
    }

    setState(() {
      _loadingRoute = true;
    });

    try {
      final result = await _routingService.getRoute(
        startLatitude: _phonePosition!.latitude,
        startLongitude: _phonePosition!.longitude,
        endLatitude: _targetLocation.latitude,
        endLongitude: _targetLocation.longitude,
      );

      if (!mounted) {
        return;
      }

      if (result == null || result.points.isEmpty) {
        setState(() {
          _routePoints = [];
          _roadDistanceInMeters = null;
          _routeDurationSeconds = null;
        });

        _showMessage('No road route could be found.');

        return;
      }

      setState(() {
        _routePoints = result.points;
        _roadDistanceInMeters = result.distanceMeters;
        _routeDurationSeconds = result.durationSeconds;
      });

      // Automatically fit the complete route
      // inside the visible map.
      if (_routePoints.length >= 2) {
        final bounds = LatLngBounds.fromPoints(_routePoints);

        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80)),
        );
      }

      if (showMessage) {
        _showMessage('Road route calculated.');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Unable to calculate road route.');
    } finally {
      if (mounted) {
        setState(() {
          _loadingRoute = false;
        });
      }
    }
  }

  // ==================================================
  // LOCATION SETTINGS
  // ==================================================

  Future<void> _openLocationSettings() async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LocationSettingsScreen()),
    );

    if (changed == true) {
      await _loadLocation();

      if (_phonePosition != null) {
        if (mounted) {
          setState(() {
            _routePoints = [];
            _roadDistanceInMeters = null;
            _routeDurationSeconds = null;
          });

          await _calculateRoute(showMessage: true);
        }
      }

      if (mounted) {
        _mapController.move(LatLng(_latitude, _longitude), 14);
      }
    }
  }

  // ==================================================
  // HELPERS
  // ==================================================

  void _showLocationError() {
    _showMessage('Please enable phone location and allow GPS permission.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ==================================================
  // ACTIVE NODE ALERT
  // ==================================================

  AlertModel? _getCurrentNodeAlert(
    DetectionModel data,
    List<AlertModel> activeAlerts,
  ) {
    if (!data.alertActive || activeAlerts.isEmpty) {
      return null;
    }

    final sortedAlerts = List<AlertModel>.from(activeAlerts);

    sortedAlerts.sort(
      (a, b) =>
          _severityPriority(b.severity)
              .compareTo(_severityPriority(a.severity)),
    );

    return sortedAlerts.first;
  }

  int _severityPriority(String severity) {
    switch (severity) {
      case 'CRITICAL':
        return 4;
      case 'HIGH':
        return 3;
      case 'MODERATE':
        return 2;
      case 'LOW':
        return 1;
      default:
        return 0;
    }
  }

  // ==================================================
  // BUILD
  // ==================================================

  @override
  Widget build(BuildContext context) {
    if (_loadingLocation) {
      return const Center(child: CircularProgressIndicator());
    }

    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.simulationService,
        ?widget.repository,
      ]),
      builder: (context, child) {
        final DetectionModel data = widget.simulationService.data;

        final activeAlerts = widget.simulationService.activeAlerts;

        final monitoringLocation = _targetLocation;

        final repository = widget.repository;

        final nodeAlert = repository != null
            ? _worstOpenAlert(activeAlerts)
            : _getCurrentNodeAlert(data, activeAlerts);

        return Stack(
          children: [
            // ==================================================
            // MAP
            // ==================================================

            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: monitoringLocation,
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: AppConfig.mapTileUrl,
                  additionalOptions: {
                    if (AppConfig.mapTileKey.isNotEmpty)
                      'key': AppConfig.mapTileKey,
                  },
                  userAgentPackageName: AppConfig.userAgentPackageName,
                ),

                // ------------------------------------------
                // ROAD ROUTE
                // ------------------------------------------
                if (_routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 6,
                        color: Colors.blue,
                      ),
                    ],
                  ),

                // ------------------------------------------
                // FIRE SPREAD (1 h, if ignited now) for the selected node
                // ------------------------------------------
                if (_selectedNode?.danger?.spread != null)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: _spreadEllipse(
                          _selectedNode!.latitude,
                          _selectedNode!.longitude,
                          _selectedNode!.danger!.spread!,
                        ),
                        color: Colors.deepOrange.withValues(alpha: 0.18),
                        borderColor: Colors.deepOrange,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),

                // ------------------------------------------
                // SATELLITE FIRE DETECTIONS (NASA VIIRS)
                // ------------------------------------------
                if (repository != null)
                  MarkerLayer(
                    markers: [
                      for (final node in repository.nodes)
                        for (final h in node.hotspots)
                          Marker(
                            point: LatLng(h.latitude, h.longitude),
                            width: 30,
                            height: 30,
                            child: Tooltip(
                              message:
                                  'Satellite fire detection\n${h.acquired} UTC · ${h.confidence} confidence'
                                  '${h.frp == null ? '' : ' · ${h.frp!.toStringAsFixed(1)} MW'}',
                              child: const Icon(Icons.whatshot, color: Colors.red, size: 28),
                            ),
                          ),
                    ],
                  ),

                // ------------------------------------------
                // MARKERS
                // ------------------------------------------
                MarkerLayer(
                  markers: [
                    // OTHER LIVE NODES
                    if (repository != null)
                      for (final node in repository.nodes)
                        if (node.id != widget.selectedNodeId)
                          Marker(
                            point: LatLng(node.latitude, node.longitude),
                            width: 58,
                            height: 58,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => widget.onNodeSelected?.call(node.id),
                              child: Opacity(
                                opacity: 0.85,
                                child: _monitoringMarker(
                                  _worstOpenAlert(
                                    repository.alertsForNode(node.id),
                                  ),
                                ),
                              ),
                            ),
                          ),

                    // SELECTED MONITORING NODE
                    Marker(
                      point: monitoringLocation,
                      width: 78,
                      height: 78,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: nodeAlert == null
                            ? null
                            : () {
                                _showIncidentDetails(context, nodeAlert);
                              },
                        child: _monitoringMarker(nodeAlert),
                      ),
                    ),

                    // ONE RESPONDER PHONE
                    if (_phonePosition != null)
                      Marker(
                        point: LatLng(
                          _phonePosition!.latitude,
                          _phonePosition!.longitude,
                        ),
                        width: 65,
                        height: 65,
                        child: _phoneMarker(),
                      ),
                  ],
                ),
              ],
            ),

            // ==================================================
            // TOP STATUS
            // ==================================================
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _mapStatusCard(
                data: data,
                activeAlertCount: activeAlerts.length,
              ),
            ),

            // ==================================================
            // ROUTE / LOCATION INFORMATION
            // ==================================================
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: _locationInfoCard(),
            ),

            // ==================================================
            // MAP BUTTONS
            // ==================================================
            Positioned(
              right: 16,
              bottom: 300,
              child: FloatingActionButton.small(
                heroTag: 'center_monitoring_node',
                onPressed: () {
                  _mapController.move(monitoringLocation, 14);
                },
                child: const Icon(Icons.forest),
              ),
            ),

            Positioned(
              right: 16,
              bottom: 240,
              child: FloatingActionButton.small(
                heroTag: 'get_phone_location',
                onPressed: _loadingGps ? null : _getPhoneLocation,
                child: _loadingGps
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
              ),
            ),

            Positioned(
              right: 16,
              bottom: 180,
              child: FloatingActionButton.small(
                heroTag: 'calculate_route',
                onPressed: _loadingRoute || _phonePosition == null
                    ? null
                    : () {
                        _calculateRoute(showMessage: true);
                      },
                child: _loadingRoute
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.alt_route),
              ),
            ),

            // Live node locations are edited by administrators from the
            // dashboard; this edits the simulation's on-device location.
            if (repository == null)
              Positioned(
                right: 16,
                bottom: 120,
                child: FloatingActionButton.small(
                  heroTag: 'edit_monitoring_location',
                  onPressed: _openLocationSettings,
                  child: const Icon(Icons.edit_location_alt),
                ),
              ),

            Positioned(
              left: 4,
              bottom: 2,
              child: Text(
                AppConfig.mapAttribution,
                style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
              ),
            ),
          ],
        );
      },
    );
  }
  // ==================================================
  // FIRE SPREAD ELLIPSE
  // ==================================================

  /// One-hour spread ellipse: ignition at the node, head running downwind
  /// (FBP elliptical spread: head + back distance along the wind, width
  /// from the length-to-breadth ratio).
  List<LatLng> _spreadEllipse(double lat, double lng, FireSpread s) {
    final head = s.headDistance1h.toDouble();
    final back = s.backDistance1h.toDouble();
    final semiMajor = math.max((head + back) / 2, 15.0);
    final semiMinor = math.max(semiMajor / math.max(s.lengthToBreadth, 1), 10.0);
    final centreOffset = (head - back) / 2;
    final theta = s.towardDeg * math.pi / 180;
    const metresPerDegree = 111320.0;
    final lngScale = metresPerDegree * math.cos(lat * math.pi / 180);

    return [
      for (var i = 0; i <= 48; i++)
        () {
          final t = 2 * math.pi * i / 48;
          final along = centreOffset + semiMajor * math.cos(t);
          final across = semiMinor * math.sin(t);
          final north = along * math.cos(theta) - across * math.sin(theta);
          final east = along * math.sin(theta) + across * math.cos(theta);
          return LatLng(lat + north / metresPerDegree, lng + east / lngScale);
        }(),
    ];
  }

  // ==================================================
  // MONITORING NODE MARKER
  // ==================================================

  Widget _monitoringMarker(AlertModel? alert) {
    if (alert == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.green.shade700,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 7,
            ),
          ],
        ),
        child: const Icon(Icons.forest, color: Colors.white, size: 34),
      );
    }

    if (alert.type == 'SMOKE DETECTED') {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade700,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 7,
            ),
          ],
        ),
        child: const Icon(Icons.cloud, color: Colors.white, size: 34),
      );
    }

    if (alert.severity == 'CRITICAL') {
      return Container(
        decoration: BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.45),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.local_fire_department,
          color: Colors.white,
          size: 38,
        ),
      );
    }

    if (alert.severity == 'HIGH') {
      return Container(
        decoration: BoxDecoration(
          color: Colors.deepOrange,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.deepOrange.withValues(alpha: 0.40),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(
          Icons.local_fire_department,
          color: Colors.white,
          size: 36,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.orange,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.35),
            blurRadius: 9,
          ),
        ],
      ),
      child: const Icon(
        Icons.warning_amber_rounded,
        color: Colors.white,
        size: 34,
      ),
    );
  }

  // ==================================================
  // PHONE MARKER
  // ==================================================

  Widget _phoneMarker() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade700,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6),
        ],
      ),
      child: const Icon(Icons.person_pin_circle, color: Colors.white, size: 32),
    );
  }

  // ==================================================
  // SEPARATE INCIDENT MARKER
  // ==================================================

  // ==================================================
  // LOCATION / ROUTE CARD
  // ==================================================

  Widget _locationInfoCard() {
    return Card(
      elevation: 5,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.forest, color: Colors.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sensor',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        _selectedNode?.name ?? _locationName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_targetLocation.latitude.toStringAsFixed(6)}, '
                    '${_targetLocation.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),

            // ------------------------------------------
            // ROUTE INFORMATION
            // ------------------------------------------
            if (_roadDistanceInMeters != null &&
                _routeDurationSeconds != null) ...[
              const SizedBox(height: 12),

              const Divider(height: 1),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _routeInfoItem(
                      icon: Icons.route,
                      title: 'Road distance',
                      value: _formatDistance(_roadDistanceInMeters!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _routeInfoItem(
                      icon: Icons.access_time,
                      title: 'EST. TIME',
                      value: _formatDuration(_routeDurationSeconds!),
                    ),
                  ),
                ],
              ),
            ] else if (_phonePosition != null) ...[
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loadingRoute
                      ? null
                      : () {
                          _calculateRoute(showMessage: true);
                        },
                  icon: _loadingRoute
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.alt_route),
                  label: Text(
                    _loadingRoute ? 'Finding route...' : 'Show road route',
                  ),
                ),
              ),
            ],

            if (_phonePosition == null) ...[
              const SizedBox(height: 8),

              const Text(
                'Tap the location button to get your current position.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _routeInfoItem({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 24, color: Colors.blue),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 9,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    }

    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  String _formatDuration(double seconds) {
    final totalMinutes = (seconds / 60).ceil();

    if (totalMinutes < 60) {
      return '$totalMinutes min';
    }

    final hours = totalMinutes ~/ 60;

    final minutes = totalMinutes % 60;

    if (minutes == 0) {
      return '$hours hr';
    }

    return '$hours hr $minutes min';
  }

  // ==================================================
  // MAP STATUS
  // ==================================================

  Widget _mapStatusCard({
    required DetectionModel data,
    required int activeAlertCount,
  }) {
    final hasAlerts = activeAlertCount > 0;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              hasAlerts ? Icons.warning_amber_rounded : Icons.check_circle,
              color: hasAlerts ? Colors.red : Colors.green,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasAlerts
                        ? '$activeAlertCount open alert'
                              '${activeAlertCount > 1 ? 's' : ''}'
                        : 'All clear',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: hasAlerts ? Colors.red : Colors.green,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _selectedNode?.name ?? _locationName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_targetLocation.latitude.toStringAsFixed(5)}, '
                    '${_targetLocation.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================================================
  // INCIDENT DETAILS
  // ==================================================

  void _showIncidentDetails(BuildContext context, AlertModel alert) {
    final isSmoke = alert.type == 'SMOKE DETECTED';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                isSmoke ? Icons.cloud : Icons.local_fire_department,
                color: isSmoke
                    ? Colors.grey.shade700
                    : alert.severity == 'CRITICAL'
                    ? Colors.red
                    : Colors.deepOrange,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('${alert.severity} ALERT')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogDetail('Type', alert.type),
                _dialogDetail(
                  'Fire Probability',
                  '${alert.fireProbability.toStringAsFixed(0)}%',
                ),
                _dialogDetail(
                  'Smoke Probability',
                  '${alert.smokeProbability.toStringAsFixed(0)}%',
                ),
                _dialogDetail(
                  'Temperature',
                  '${alert.temperature.toStringAsFixed(1)}°C',
                ),
                _dialogDetail(
                  'Humidity',
                  '${alert.humidity.toStringAsFixed(0)}%',
                ),
                _dialogDetail('Sensor', alert.deviceId),
                _dialogDetail('Latitude', alert.latitude.toStringAsFixed(5)),
                _dialogDetail('Longitude', alert.longitude.toStringAsFixed(5)),
                _dialogDetail('Status', alertStatusLabel(alert.status)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  Widget _dialogDetail(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

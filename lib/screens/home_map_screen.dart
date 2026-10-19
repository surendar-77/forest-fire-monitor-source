import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/node_model.dart';
import '../services/auth_service.dart';
import '../services/data_source_controller.dart';
import '../services/gps_service.dart';
import '../services/location_service.dart';
import '../utils/fire_areas.dart';
import '../utils/friendly.dart';
import '../utils/risk_utils.dart';
import '../widgets/live_overlay_strip.dart';
import 'dashboard_screen.dart';

enum MapLayerMode { satellite, vegetation, street }

/// Home: a satellite map of the sensors with estimated fire areas drawn on
/// it, the overview figures on top, and all sensor data and predictions in
/// a panel that slides up over the map.
class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({
    super.key,
    required this.controller,
    required this.auth,
    this.onOpenAlerts,
  });

  final DataSourceController controller;
  final AuthService auth;
  final VoidCallback? onOpenAlerts;

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  final MapController _map = MapController();
  final GpsService _gps = GpsService();
  MapLayerMode _mode = MapLayerMode.satellite;
  LatLng? _me;
  bool _mapReady = false;
  String? _centeredOn;
  Timer? _clock;

  /// Tap-to-place: the sensor being placed and the spot picked so far.
  String? _placingId;
  LatLng? _pending;
  bool _saving = false;

  static const _esriImagery =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const _esriLabels =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';
  static const _esriRoads =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}';

  /// NASA MODIS 8-day vegetation index; ask for a date safely inside the
  /// latest finished composite.
  String get _ndviUrl {
    final d = DateTime.now().toUtc().subtract(const Duration(days: 12));
    final date =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return 'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/MODIS_Terra_NDVI_8Day/default/'
        '$date/GoogleMapsCompatible_Level9/{z}/{y}/{x}.png';
  }

  @override
  void initState() {
    super.initState();
    // Keeps "updated X min ago" and the growing fire areas current.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  NodeModel? get _selected {
    final repo = widget.controller.repository;
    final id = widget.controller.selectedNodeId;
    return id == null ? null : repo.node(id);
  }

  LatLng get _home {
    final node =
        _selected ??
        widget.controller.repository.nodes
            .where((n) => n.hasLocation)
            .firstOrNull;
    if (node != null && node.hasLocation) {
      return LatLng(node.latitude, node.longitude);
    }
    return const LatLng(
      LocationService.defaultLatitude,
      LocationService.defaultLongitude,
    );
  }

  /// Follow the selected sensor once it (or its location) becomes known.
  void _centerOnSelectedOnce() {
    final node = _selected;
    if (!_mapReady || node == null || !node.hasLocation) return;
    final key = '${node.id}:${node.latitude},${node.longitude}';
    if (_centeredOn == key) return;
    _centeredOn = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _map.move(LatLng(node.latitude, node.longitude), 15);
    });
  }

  void _startPlacing(String nodeId) {
    final node = widget.controller.repository.node(nodeId);
    setState(() {
      _placingId = nodeId;
      _pending = node != null && node.hasLocation
          ? LatLng(node.latitude, node.longitude)
          : null;
    });
  }

  Future<void> _savePlacement() async {
    final id = _placingId;
    final point = _pending;
    if (id == null || point == null) return;
    final repo = widget.controller.repository;
    final node = repo.node(id);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await repo.updateNodeLocation(
        id,
        name: node?.name ?? id,
        latitude: double.parse(point.latitude.toStringAsFixed(6)),
        longitude: double.parse(point.longitude.toStringAsFixed(6)),
      );
      if (!mounted) return;
      setState(() {
        _placingId = null;
        _pending = null;
        _centeredOn = null; // re-centre on the new spot
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Location saved. Fire weather for this spot appears within the hour.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save location: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _useMyLocationForPlacement() async {
    final messenger = ScaffoldMessenger.of(context);
    final position = await _gps.getCurrentLocation();
    if (!mounted) return;
    if (position == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Location is off or not allowed.')),
      );
      return;
    }
    final point = LatLng(position.latitude, position.longitude);
    setState(() => _pending = point);
    _map.move(point, 17);
  }

  List<Widget> _placingOverlay() {
    final node = widget.controller.repository.node(_placingId!);
    final name = node?.name ?? _placingId!;
    return [
      Positioned(
        left: 12,
        right: 70,
        top: 12,
        child: Material(
          color: Colors.grey.shade900.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.touch_app_outlined, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _pending == null
                        ? 'Tap the map where $name is installed.'
                        : 'Tap again to move the pin, then Save.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      Positioned(
        left: 12,
        right: 12,
        bottom: 16,
        child: Material(
          color: Colors.white,
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Location of $name',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _pending == null
                      ? 'No spot picked yet'
                      : '${_pending!.latitude.toStringAsFixed(5)}, ${_pending!.longitude.toStringAsFixed(5)}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _useMyLocationForPlacement,
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text(
                    "Use my current location (I'm at the sensor)",
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                _placingId = null;
                                _pending = null;
                              }),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _pending == null || _saving
                            ? null
                            : _savePlacement,
                        child: Text(_saving ? 'Saving...' : 'Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Future<void> _locateMe() async {
    final messenger = ScaffoldMessenger.of(context);
    final position = await _gps.getCurrentLocation();
    if (!mounted) return;
    if (position == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Location is off or not allowed.')),
      );
      return;
    }
    setState(() => _me = LatLng(position.latitude, position.longitude));
    _map.move(_me!, 15);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.controller.repository,
      ]),
      builder: (context, _) {
        final repo = widget.controller.repository;
        final live = widget.controller.isLive;
        final nodes = live ? repo.nodes : const <NodeModel>[];
        final areas = live
            ? estimateFireAreas(nodes: nodes, alerts: repo.alerts)
            : const <FireArea>[];
        _centerOnSelectedOnce();

        return Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _home,
                initialZoom: 15,
                minZoom: 3,
                maxZoom: 19,
                onMapReady: () {
                  _mapReady = true;
                  _centerOnSelectedOnce();
                },
                onTap: (_, point) {
                  if (_placingId != null) setState(() => _pending = point);
                },
              ),
              children: [
                ..._baseLayers(),
                PolygonLayer(
                  polygons: [
                    for (final a in areas.where(
                      (a) => a.status == FireAreaStatus.possible,
                    ))
                      _polygon(a),
                    for (final a in areas.where(
                      (a) => a.status == FireAreaStatus.active,
                    ))
                      _polygon(a),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (final n in nodes)
                      for (final h in n.hotspots)
                        Marker(
                          point: LatLng(h.latitude, h.longitude),
                          width: 12,
                          height: 12,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                    for (final n in nodes.where((n) => n.hasLocation))
                      _nodeMarker(n),
                    for (final a in areas.where(
                      (a) => a.status == FireAreaStatus.active,
                    ))
                      _areaLabel(a),
                    if (_placingId != null && _pending != null)
                      Marker(
                        point: _pending!,
                        width: 44,
                        height: 44,
                        alignment: Alignment.topCenter,
                        child: Icon(
                          Icons.location_on,
                          size: 44,
                          color: Colors.red.shade600,
                          shadows: const [
                            Shadow(blurRadius: 6, color: Colors.black54),
                          ],
                        ),
                      ),
                    if (_me != null)
                      Marker(
                        point: _me!,
                        width: 22,
                        height: 22,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // Overview figures and legend.
            Positioned(
              left: 12,
              right: 12,
              top: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (live && _selected != null)
                    LiveOverlayStrip(node: _selected!),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (areas.isNotEmpty) _legend(),
                      if (_mode == MapLayerMode.vegetation) ...[
                        if (areas.isNotEmpty) const SizedBox(width: 8),
                        _vegetationLegend(),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Map controls.
            Positioned(
              right: 12,
              top: live ? 120 : 12,
              child: Column(
                children: [
                  _layerButton(),
                  const SizedBox(height: 8),
                  _roundButton(Icons.my_location, 'My location', _locateMe),
                  if (widget.auth.isAdmin &&
                      _selected != null &&
                      _placingId == null) ...[
                    const SizedBox(height: 8),
                    _roundButton(
                      Icons.edit_location_alt_outlined,
                      'Set sensor location on the map',
                      () => _startPlacing(_selected!.id),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _roundButton(
                    Icons.sensors,
                    'Back to sensor',
                    () => _map.move(_home, 15),
                  ),
                ],
              ),
            ),

            // Attribution (required by the tile providers).
            Positioned(
              left: 8,
              bottom: MediaQuery.sizeOf(context).height * 0.2 + 4,
              child: Text(
                _mode == MapLayerMode.street
                    ? AppConfig.mapAttribution
                    : _mode == MapLayerMode.vegetation
                    ? 'Esri, Maxar · NASA GIBS MODIS NDVI'
                    : 'Esri, Maxar, Earthstar Geographics',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 3)],
                ),
              ),
            ),

            if (_placingId != null) ..._placingOverlay(),

            // Admins: a sensor without a location yet.
            if (_placingId == null &&
                widget.auth.isAdmin &&
                _selected != null &&
                !_selected!.hasLocation)
              Positioned(
                left: 12,
                right: 70,
                top: live ? 120 : 12,
                child: Material(
                  color: Colors.orange.shade700,
                  borderRadius: BorderRadius.circular(14),
                  elevation: 3,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _startPlacing(_selected!.id),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.add_location_alt_outlined,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "${_selected!.name} has no location yet. Tap here, then tap the map where it is.",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // All sensor data and predictions, sliding up over the map.
            if (_placingId == null)
              DraggableScrollableSheet(
                initialChildSize: 0.34,
                minChildSize: 0.2,
                maxChildSize: 0.94,
                snap: true,
                snapSizes: const [0.34, 0.94],
                builder: (context, scrollController) => Material(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  elevation: 12,
                  shadowColor: Colors.black54,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: DashboardScreen(
                    controller: widget.controller,
                    auth: widget.auth,
                    onOpenAlerts: widget.onOpenAlerts,
                    onPlaceOnMap: widget.auth.isAdmin ? _startPlacing : null,
                    scrollController: scrollController,
                    embedded: true,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  List<Widget> _baseLayers() {
    final pkg = AppConfig.userAgentPackageName;
    switch (_mode) {
      case MapLayerMode.street:
        return [
          TileLayer(
            urlTemplate: AppConfig.mapTileUrl,
            additionalOptions: {
              if (AppConfig.mapTileKey.isNotEmpty) 'key': AppConfig.mapTileKey,
            },
            userAgentPackageName: pkg,
          ),
        ];
      case MapLayerMode.vegetation:
        return [
          TileLayer(
            urlTemplate: _esriImagery,
            userAgentPackageName: pkg,
            maxNativeZoom: 19,
          ),
          Opacity(
            opacity: 0.72,
            child: TileLayer(
              urlTemplate: _ndviUrl,
              userAgentPackageName: pkg,
              maxNativeZoom: 9,
            ),
          ),
          TileLayer(urlTemplate: _esriLabels, userAgentPackageName: pkg),
        ];
      case MapLayerMode.satellite:
        return [
          TileLayer(
            urlTemplate: _esriImagery,
            userAgentPackageName: pkg,
            maxNativeZoom: 19,
          ),
          TileLayer(urlTemplate: _esriRoads, userAgentPackageName: pkg),
          TileLayer(urlTemplate: _esriLabels, userAgentPackageName: pkg),
        ];
    }
  }

  Polygon _polygon(FireArea a) {
    final active = a.status == FireAreaStatus.active;
    final color = active ? const Color(0xFFE53935) : const Color(0xFFFFB300);
    return Polygon(
      points: a.points,
      color: color.withValues(alpha: active ? 0.22 : 0.12),
      borderColor: color,
      borderStrokeWidth: 2,
      pattern: StrokePattern.dashed(segments: const [10, 7]),
    );
  }

  Marker _areaLabel(FireArea a) {
    return Marker(
      point: a.center,
      width: 230,
      height: 64,
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: () => _showArea(a),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 6),
                ],
              ),
              child: Icon(
                Icons.local_fire_department,
                color: Colors.red.shade700,
                size: 24,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title, style: _shadowText(15, FontWeight.w700)),
                  Text(
                    'Estimated fire area · Updated ${timeAgo(a.updatedAt)}',
                    style: _shadowText(11.5, FontWeight.w500),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _shadowText(double size, FontWeight weight) => TextStyle(
    color: Colors.white,
    fontSize: size,
    fontWeight: weight,
    shadows: const [Shadow(blurRadius: 4), Shadow(blurRadius: 8)],
  );

  Marker _nodeMarker(NodeModel n) {
    final selected = n.id == widget.controller.selectedNodeId;
    final offline =
        n.status == NodeStatus.offline || n.status == NodeStatus.stale;
    final color = offline
        ? Colors.grey.shade600
        : riskColor(n.detection.riskLevel);
    return Marker(
      point: LatLng(n.latitude, n.longitude),
      width: 120,
      height: 66,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () => widget.controller.selectNode(n.id),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4),
                ],
              ),
              child: Text(
                n.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              width: selected ? 34 : 28,
              height: selected ? 34 : 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 5),
                ],
              ),
              child: const Icon(Icons.sensors, color: Colors.white, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend() {
    Widget dot(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot(const Color(0xFFE57373), 'Active'),
          const SizedBox(width: 14),
          dot(const Color(0xFFFFB300), 'Possibly active'),
        ],
      ),
    );
  }

  Widget _vegetationLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Vegetation', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          Container(
            width: 90,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFB07A4A),
                  Color(0xFFE8D27A),
                  Color(0xFF8BC34A),
                  Color(0xFF1B5E20),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'low → dense',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _roundButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: Colors.grey.shade800),
        onPressed: onTap,
      ),
    );
  }

  Widget _layerButton() {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: PopupMenuButton<MapLayerMode>(
        tooltip: 'Map type',
        icon: Icon(Icons.layers_outlined, color: Colors.grey.shade800),
        onSelected: (mode) => setState(() => _mode = mode),
        itemBuilder: (context) => [
          CheckedPopupMenuItem(
            value: MapLayerMode.satellite,
            checked: _mode == MapLayerMode.satellite,
            child: const Text('Satellite'),
          ),
          CheckedPopupMenuItem(
            value: MapLayerMode.vegetation,
            checked: _mode == MapLayerMode.vegetation,
            child: const Text('Vegetation (NASA)'),
          ),
          CheckedPopupMenuItem(
            value: MapLayerMode.street,
            checked: _mode == MapLayerMode.street,
            child: const Text('Street map'),
          ),
        ],
      ),
    );
  }

  void _showArea(FireArea a) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.red.shade50,
                    child: Icon(
                      Icons.local_fire_department,
                      color: Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    a.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Detected by ${a.source} · ${timeAgo(a.updatedAt)}'),
              const SizedBox(height: 8),
              Text(
                'The red area is where fire is estimated to be now; the yellow area is where it could '
                'spread in the next hour, from the wind and the fire-spread model. These are estimates, '
                'not mapped fire lines.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              if (a.alertId != null && widget.onOpenAlerts != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onOpenAlerts!();
                    },
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Open the alert'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

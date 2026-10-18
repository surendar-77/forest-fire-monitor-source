import 'package:flutter/material.dart';

import '../services/location_service.dart';

typedef SaveNodeLocation =
    Future<void> Function(String name, double latitude, double longitude);

/// Edits a monitoring location. With [onSave] it edits a live node (an
/// administrator saving to Firestore); without it, the on-device default
/// location used when a node has no coordinates.
class LocationSettingsScreen extends StatefulWidget {
  const LocationSettingsScreen({
    super.key,
    this.initialName,
    this.initialLatitude,
    this.initialLongitude,
    this.onSave,
  });

  final String? initialName;
  final double? initialLatitude;
  final double? initialLongitude;
  final SaveNodeLocation? onSave;

  @override
  State<LocationSettingsScreen> createState() => _LocationSettingsScreenState();
}

class _LocationSettingsScreenState extends State<LocationSettingsScreen> {
  final LocationService _locationService = LocationService();

  final TextEditingController _nameController = TextEditingController();

  final TextEditingController _latitudeController = TextEditingController();

  final TextEditingController _longitudeController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final name = widget.initialName ?? await _locationService.getLocationName();

    final latitude =
        widget.initialLatitude ?? await _locationService.getLatitude();

    final longitude =
        widget.initialLongitude ?? await _locationService.getLongitude();

    if (!mounted) {
      return;
    }

    setState(() {
      _nameController.text = name;
      _latitudeController.text = latitude.toStringAsFixed(6);
      _longitudeController.text = longitude.toStringAsFixed(6);
      _loading = false;
    });
  }

  Future<void> _saveLocation() async {
    final name = _nameController.text.trim();

    final latitude = double.tryParse(_latitudeController.text.trim());

    final longitude = double.tryParse(_longitudeController.text.trim());

    if (name.isEmpty) {
      _showMessage('Please enter a location name.');
      return;
    }

    if (latitude == null || latitude < -90 || latitude > 90) {
      _showMessage('Enter a valid latitude between -90 and 90.');
      return;
    }

    if (longitude == null || longitude < -180 || longitude > 180) {
      _showMessage('Enter a valid longitude between -180 and 180.');
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final onSave = widget.onSave;

      if (onSave != null) {
        await onSave(name, latitude, longitude);
      } else {
        await _locationService.saveLocation(
          name: name,
          latitude: latitude,
          longitude: longitude,
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
      });

      _showMessage('Could not save location: $error');
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _saving = false;
    });

    _showMessage('Monitoring location saved successfully.');

    Navigator.pop(context, true);
  }

  Future<void> _resetLocation() async {
    await _locationService.resetToDefault();

    if (!mounted) {
      return;
    }

    await _loadLocation();

    _showMessage('Location reset to default.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Monitoring Location')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.red, size: 36),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'FIXED MONITORING NODE',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Configure the location where the '
                            'forest monitoring unit is installed.',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Location Name',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'Example: Forest Zone A',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.forest),
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'Latitude',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _latitudeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                hintText: 'Example: 13.082700',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.north),
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'Longitude',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _longitudeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                hintText: 'Example: 80.270700',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.east),
              ),
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _saveLocation,
                icon: const Icon(Icons.save),
                label: Text(_saving ? 'SAVING...' : 'SAVE LOCATION'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),

            if (widget.onSave == null) ...[
              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _resetLocation,
                  icon: const Icon(Icons.restore),
                  label: const Text('RESET TO DEFAULT'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            Card(
              color: Colors.blue.withValues(alpha: 0.06),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This location represents the fixed '
                        'tree-mounted monitoring unit. You can '
                        'change it whenever the system is '
                        'deployed at another location.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/terrain.dart';
import '../services/node_repository.dart';

/// Administrators: register a new sensor. The backend creates it and its
/// secret key; the key and the firmware lines are shown once, to copy into
/// the new board. Pops with the new sensor's id after "Place it on the map".
class AddSensorScreen extends StatefulWidget {
  const AddSensorScreen({
    super.key,
    required this.repository,
    this.canPlaceOnMap = true,
  });

  final NodeRepository repository;

  /// Offer "Place it on the map" (opened from the map).
  final bool canPlaceOnMap;

  @override
  State<AddSensorScreen> createState() => _AddSensorScreenState();
}

class _AddSensorScreenState extends State<AddSensorScreen> {
  final _name = TextEditingController();
  late final _id = TextEditingController(
    text: widget.repository.suggestNodeId(),
  );
  final _zone = TextEditingController();
  final _channel = TextEditingController();
  final _readKey = TextEditingController();
  String? _terrain;
  bool _busy = false;
  String? _error;

  /// Set once the backend has created the sensor.
  String? _createdId;
  String? _key;

  @override
  void dispose() {
    for (final c in [_name, _id, _zone, _channel, _readKey]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final id = _id.text.trim().toUpperCase();
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the sensor a name.');
      return;
    }
    if (!RegExp(r'^[A-Z0-9][A-Z0-9-]{1,23}$').hasMatch(id)) {
      setState(
        () => _error = 'Sensor ID: capital letters, digits and dashes, like NODE-02.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = await widget.repository.addSensor(
        nodeId: id,
        name: _name.text,
        zone: _zone.text,
        terrain: _terrain,
        channelId: _channel.text,
        readApiKey: _readKey.text,
      );
      if (!mounted) return;
      setState(() {
        _createdId = id;
        _key = key;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _firmwareLines =>
      '#define NODE_ID   "$_createdId"\n#define NODE_KEY  "$_key"';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add a sensor')),
      body: _createdId == null ? _form() : _done(),
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        TextField(
          controller: _name,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. Hill top, North gate',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _id,
          enabled: !_busy,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Sensor ID',
            helperText: 'Must match NODE_ID in the board firmware',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _zone,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Area or zone (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _terrain,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Terrain (optional, improves fire risk)',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final t in Terrain.all)
              DropdownMenuItem(value: t.id, child: Text(t.label)),
          ],
          onChanged: _busy ? null : (v) => setState(() => _terrain = v),
        ),
        const SizedBox(height: 20),
        Text(
          'Minute-by-minute history (ThingSpeak)',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Each sensor needs its own free ThingSpeak channel for history, status and alerts '
          'from readings. Create one at thingspeak.com (8 fields) and enter its number here. '
          'You can leave this empty and add it later.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _channel,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'ThingSpeak channel ID',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _readKey,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Read API key (only for private channels)',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.add),
          label: Text(
            _busy ? 'Setting up (up to a minute)...' : 'Add sensor',
          ),
        ),
      ],
    );
  }

  Widget _done() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_name.text.trim()} ($_createdId) was added',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Put these two lines in the new board\'s firmware',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Replace the NODE_ID and NODE_KEY lines in ForestFire_S3.ino, then flash the board. '
          'The key is shown only now: copy it before leaving this page.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            _firmwareLines,
            style: const TextStyle(
              fontFamily: 'monospace',
              color: Colors.white,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: _firmwareLines));
              messenger.showSnackBar(
                const SnackBar(content: Text('Copied.')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
        ),
        if (_channel.text.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Also set THINGSPEAK_API_KEY in the firmware to the Write API key of channel '
            '${_channel.text.trim()}.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 24),
        if (widget.canPlaceOnMap)
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, _createdId),
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Place it on the map'),
          )
        else
          Text(
            'Next: on the map, select it and tap the pin button to set where it is installed.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

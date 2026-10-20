import 'package:flutter/material.dart';

import '../services/fire_station_service.dart';
import '../services/gps_service.dart';
import '../utils/friendly.dart';

/// Administrators: fire stations that get serious fire alerts by Telegram.
class FireStationsScreen extends StatefulWidget {
  const FireStationsScreen({super.key, this.service});

  final FireStationService? service;

  @override
  State<FireStationsScreen> createState() => _FireStationsScreenState();
}

class _FireStationsScreenState extends State<FireStationsScreen> {
  late final FireStationService _service =
      widget.service ?? FireStationService();
  final Set<String> _testing = {};

  Future<void> _test(FireStation station) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _testing.add(station.id));
    try {
      final message = await _service.sendTest(station.id);
      messenger.showSnackBar(
        SnackBar(content: Text('${station.name}: $message')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _testing.remove(station.id));
    }
  }

  Future<void> _edit([FireStation? station]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _StationForm(service: _service, station: station),
    );
  }

  Future<void> _delete(FireStation station) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${station.name}?'),
        content: const Text('It will stop getting fire alerts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await _service.delete(station.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fire stations')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add station'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          StreamBuilder<BotStatus>(
            stream: _service.botStatus(),
            builder: (context, snap) => _BotCard(status: snap.data),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<FireStation>>(
            stream: _service.stations(),
            builder: (context, snap) {
              final stations = snap.data ?? const <FireStation>[];
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (stations.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.fire_truck_outlined,
                        size: 44,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'No fire stations yet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add one to send serious fire alerts to it automatically.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  for (final station in stations)
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.fire_truck_outlined),
                        ),
                        title: Text(station.name),
                        subtitle: Text(
                          [
                            'Telegram chat ${station.telegramChatId}',
                            if (station.phone != null) station.phone!,
                            station.hasLocation
                                ? 'gets alerts within 25 km'
                                : 'gets every alert',
                          ].join(' · '),
                        ),
                        onTap: () => _edit(station),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _testing.contains(station.id)
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    tooltip: 'Send test message',
                                    icon: const Icon(Icons.send_outlined),
                                    onPressed: () => _test(station),
                                  ),
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(station),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Serious fire alerts (high or critical) are sent to the stations within 25 km of the '
            'sensor, or to every station when none is that close. Sensor problems are never sent to them.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _BotCard extends StatelessWidget {
  const _BotCard({required this.status});

  final BotStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) return const SizedBox.shrink();
    if (s.configured) {
      return Card(
        color: Colors.green.shade50,
        child: ListTile(
          leading: Icon(Icons.check_circle, color: Colors.green.shade700),
          title: Text(
            s.username == null ? 'Telegram bot connected' : 'Bot @${s.username} connected',
          ),
          subtitle: Text(
            s.username == null
                ? 'Each station opens the bot in Telegram and sends /start.'
                : 'Each station opens t.me/${s.username} in Telegram and sends /start; '
                      'it then appears when you add a station.',
          ),
        ),
      );
    }
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Telegram bot not set up yet',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '1. In Telegram, open @BotFather, send /newbot and follow the steps. It gives you a token.\n'
              '2. On the PC with the project, run: npx wrangler secret put TELEGRAM_BOT_TOKEN (in the worker folder) and paste the token.\n'
              '3. Within 5 minutes this card turns green.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationForm extends StatefulWidget {
  const _StationForm({required this.service, this.station});

  final FireStationService service;
  final FireStation? station;

  @override
  State<_StationForm> createState() => _StationFormState();
}

class _StationFormState extends State<_StationForm> {
  late final _name = TextEditingController(text: widget.station?.name);
  late final _chat = TextEditingController(
    text: widget.station?.telegramChatId,
  );
  late final _phone = TextEditingController(text: widget.station?.phone);
  late double? _lat = widget.station?.latitude;
  late double? _lng = widget.station?.longitude;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _chat.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    final position = await GpsService().getCurrentLocation();
    if (!mounted) return;
    if (position == null) {
      setState(() => _error = 'Location is off or not allowed.');
      return;
    }
    setState(() {
      _lat = position.latitude;
      _lng = position.longitude;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _chat.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name and pick a Telegram chat.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.save(
        id: widget.station?.id,
        name: _name.text,
        telegramChatId: _chat.text,
        phone: _phone.text,
        latitude: _lat,
        longitude: _lng,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.station == null ? 'Add fire station' : 'Edit fire station',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Station name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<TelegramChat>>(
              stream: widget.service.chats(),
              builder: (context, snap) {
                final chats = snap.data ?? const <TelegramChat>[];
                if (chats.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Messaged the bot recently: tap to use',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final chat in chats.take(8))
                            ActionChip(
                              avatar: const Icon(Icons.chat_outlined, size: 16),
                              label: Text(
                                chat.lastMessageAt == null
                                    ? chat.label
                                    : '${chat.label} · ${timeAgo(chat.lastMessageAt!)}',
                              ),
                              onPressed: () => setState(() {
                                _chat.text = chat.chatId;
                                if (_name.text.trim().isEmpty) {
                                  _name.text = chat.name;
                                }
                              }),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            TextField(
              controller: _chat,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Telegram chat ID',
                helperText: 'Pick from the list above after the station sends /start to the bot',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone (optional, shown to responders)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _useMyLocation,
              icon: const Icon(Icons.my_location, size: 18),
              label: Text(
                _lat == null
                    ? "Set location: I'm at the station (optional)"
                    : 'Location ${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)} · update',
              ),
            ),
            if (_lat != null)
              TextButton(
                onPressed: () => setState(() {
                  _lat = null;
                  _lng = null;
                }),
                child: const Text('Clear location (get every alert)'),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/node_repository.dart';

/// Thin banner shown above every tab when the phone is offline, the data on
/// screen came from the offline cache, or the backend alert service has
/// stopped, so officers never mistake old readings for live ones.
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({super.key, required this.repository});

  final NodeRepository repository;

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _offline = false;

  @override
  void initState() {
    super.initState();

    final connectivity = Connectivity();

    connectivity.checkConnectivity().then(_update).catchError((_) {});
    _subscription = connectivity.onConnectivityChanged.listen(
      _update,
      onError: (_) {},
    );
  }

  void _update(List<ConnectivityResult> results) {
    final offline =
        results.isEmpty ||
        results.every((result) => result == ConnectivityResult.none);

    if (mounted && offline != _offline) {
      setState(() => _offline = offline);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.repository,
      builder: (context, _) {
        final repository = widget.repository;
        final cached = repository.isLoaded && repository.isFromCache;
        final error = repository.error;

        String? message;
        Color color = Colors.orange.shade800;
        IconData icon = Icons.cloud_off;

        if (_offline || cached) {
          final synced = repository.lastSynced;
          message = synced == null
              ? 'Offline: showing saved data'
              : 'Offline: showing data from '
                    '${DateFormat('d MMM HH:mm').format(synced)}';
        } else if (repository.isBackendDown) {
          final heartbeat = repository.backendHeartbeat;
          message = heartbeat == null
              ? 'Alert service is not running. New readings and push '
                    'alerts are paused.'
              : 'Alert service offline since '
                    '${DateFormat('d MMM HH:mm').format(heartbeat)}. New '
                    'readings and push alerts are paused.';
          color = Colors.red.shade700;
          icon = Icons.notifications_off_outlined;
        } else if (error != null) {
          message = 'Can\'t reach the server. Retrying…';
          color = Colors.red.shade700;
          icon = Icons.error_outline;
        }

        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: message == null
              ? const SizedBox(width: double.infinity)
              : Material(
                  color: color,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(icon, size: 16, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

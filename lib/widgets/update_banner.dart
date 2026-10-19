import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_update.dart';

/// "A new version is available" strip with an Update button. Checks on
/// start, every 5 minutes, and whenever the app comes back to the
/// foreground (e.g. reopened from the home screen).
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _available = false;
  String _offer = '';
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    if (!AppUpdate.supported) return;
    _check();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _check());
    _lifecycle = AppLifecycleListener(onResume: _check);
  }

  Future<void> _check() async {
    final offer = await AppUpdate.availableUpdate();
    if (!mounted) return;
    final available = offer != null;
    if (available != _available || (offer ?? '') != _offer) {
      setState(() {
        _available = available;
        _offer = offer ?? '';
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: primary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              const Icon(
                Icons.system_update_alt,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _offer.startsWith('version')
                      ? 'App $_offer is available.'
                      : 'A new version of the app is available.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: primary,
                  backgroundColor: Colors.white,
                  minimumSize: const Size(0, 34),
                ),
                onPressed: _updating
                    ? null
                    : () async {
                        setState(() => _updating = true);
                        await AppUpdate.applyUpdate();
                        // Android hands off to the download; the web reloads.
                        if (mounted) setState(() => _updating = false);
                      },
                child: Text(_updating ? 'Updating...' : 'Update'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

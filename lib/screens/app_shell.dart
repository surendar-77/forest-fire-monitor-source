import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/data_source_controller.dart';
import '../services/fcm_service.dart';
import '../services/node_repository.dart';
import '../services/notification_service.dart';
import '../widgets/connection_banner.dart';
import '../widgets/update_banner.dart';
import '../widgets/urgent_alert_dialog.dart';

import 'alerts_screen.dart';
import 'dashboard_screen.dart';
import 'map_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.auth, required this.repository});

  final AuthService auth;
  final NodeRepository repository;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final DataSourceController _dataSourceController = DataSourceController(
    repository: widget.repository,
  );

  static const _home = 0;
  static const _map = 1;
  static const _alerts = 2;

  int _selectedIndex = _home;

  @override
  void initState() {
    super.initState();

    _dataSourceController.initialize();

    final uid = widget.auth.user?.uid;

    if (uid != null) {
      FcmService.registerForUser(uid);
    }

    FcmService.openAlertsRequested.addListener(_handleAlertNavigation);
    widget.repository.incomingAlert.addListener(_showIncomingAlert);

    if (FcmService.openAlertsRequested.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleAlertNavigation();
      });
    }
  }

  void _handleAlertNavigation() {
    if (!FcmService.openAlertsRequested.value) {
      return;
    }

    FcmService.openAlertsRequested.value = false;

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedIndex = _alerts;
    });
  }

  bool _alertDialogOpen = false;

  /// Pop-up + alarm the moment an urgent alert arrives while the app is open.
  Future<void> _showIncomingAlert() async {
    final alert = widget.repository.incomingAlert.value;
    if (alert == null || !mounted || _alertDialogOpen) return;
    widget.repository.incomingAlert.value = null;
    _alertDialogOpen = true;

    // Start the alarm without waiting for it: on the web, audio can stay
    // pending (autoplay rules) and must never hold back the pop-up.
    unawaited(
      NotificationService.startEmergencyAlarm()
          .timeout(const Duration(seconds: 5))
          .then(
            (_) {},
            onError: (Object error) => debugPrint('Alarm unavailable: $error'),
          ),
    );

    if (!mounted) {
      _alertDialogOpen = false;
      return;
    }
    final action = await showDialog<UrgentAlertAction>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UrgentAlertDialog(
        alert: alert,
        nodeName:
            widget.repository.node(alert.deviceId)?.name ?? alert.deviceId,
        canAcknowledge: widget.auth.canRespondToAlerts,
      ),
    );
    _alertDialogOpen = false;

    unawaited(
      NotificationService.stopEmergencyAlarm()
          .timeout(const Duration(seconds: 3))
          .then((_) {}, onError: (Object _) {}),
    );

    if (!mounted) return;
    switch (action) {
      case UrgentAlertAction.acknowledge:
        try {
          await widget.repository.acknowledgeAlert(alert.id);
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not acknowledge: $error')),
            );
          }
        }
        setState(() => _selectedIndex = _alerts);
      case UrgentAlertAction.view:
        _dataSourceController.selectNode(alert.deviceId);
        setState(() => _selectedIndex = _map);
      case UrgentAlertAction.dismiss:
      case null:
        break;
    }
  }

  Widget _screenFor(int index) {
    final source = _dataSourceController.source;

    switch (index) {
      case _home:
        return DashboardScreen(
          controller: _dataSourceController,
          auth: widget.auth,
          onOpenAlerts: () => setState(() => _selectedIndex = _alerts),
        );
      case _map:
        return MapScreen(
          simulationService: source,
          repository: _dataSourceController.isLive ? widget.repository : null,
          selectedNodeId: _dataSourceController.selectedNodeId,
          onNodeSelected: _dataSourceController.selectNode,
        );
      default:
        return AlertsScreen(
          simulationService: source,
          auth: widget.auth,
          repository: _dataSourceController.isLive ? widget.repository : null,
        );
    }
  }

  final List<String> _titles = const ['Forest Fire Monitor', 'Map', 'Alerts'];

  @override
  void dispose() {
    FcmService.openAlertsRequested.removeListener(_handleAlertNavigation);
    widget.repository.incomingAlert.removeListener(_showIncomingAlert);

    _dataSourceController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _dataSourceController,
        widget.repository,
        widget.auth,
      ]),
      builder: (context, _) {
        final openAlerts = _dataSourceController.isLive
            ? widget.repository.openAlerts.length
            : _dataSourceController.simulationService.activeAlerts.length;

        return Scaffold(
          appBar: AppBar(
            title: Text(_titles[_selectedIndex]),
            actions: [
              if (widget.auth.isAdmin) _dataSourceMenu(context),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      auth: widget.auth,
                      repository: widget.repository,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              const UpdateBanner(),
              if (_dataSourceController.isLive)
                ConnectionBanner(repository: widget.repository),
              if (_dataSourceController.isSimulation) _simulationBanner(),
              Expanded(child: _screenFor(_selectedIndex)),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              const NavigationDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: 'Map',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: openAlerts > 0,
                  label: Text('$openAlerts'),
                  child: const Icon(Icons.notifications_none),
                ),
                selectedIcon: Badge(
                  isLabelVisible: openAlerts > 0,
                  label: Text('$openAlerts'),
                  child: const Icon(Icons.notifications),
                ),
                label: 'Alerts',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _simulationBanner() {
    return Material(
      color: Colors.orange.shade700,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.science_outlined, size: 16, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Demo mode: practice data on this phone only. '
                'No real alerts are sent.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dataSourceMenu(BuildContext context) {
    return PopupMenuButton<DataSourceMode>(
      tooltip: 'Real sensors or demo mode',
      icon: Icon(
        _dataSourceController.isSimulation
            ? Icons.science_outlined
            : Icons.cloud_done_outlined,
      ),
      onSelected: (mode) async {
        if (mode == DataSourceMode.live) {
          await _dataSourceController.switchToLive();
        } else {
          await _dataSourceController.switchToSimulation();
        }
      },
      itemBuilder: (context) => [
        _modeItem(
          context,
          DataSourceMode.live,
          Icons.cloud_done_outlined,
          'Real sensors',
          _dataSourceController.isLive,
        ),
        _modeItem(
          context,
          DataSourceMode.simulation,
          Icons.science_outlined,
          'Demo mode',
          _dataSourceController.isSimulation,
        ),
      ],
    );
  }

  PopupMenuItem<DataSourceMode> _modeItem(
    BuildContext context,
    DataSourceMode mode,
    IconData icon,
    String label,
    bool selected,
  ) {
    return PopupMenuItem<DataSourceMode>(
      value: mode,
      child: Row(
        children: [
          Icon(
            icon,
            color: selected ? Theme.of(context).colorScheme.primary : null,
          ),
          const SizedBox(width: 12),
          Text(label),
          if (selected) ...[const Spacer(), const Icon(Icons.check)],
        ],
      ),
    );
  }
}

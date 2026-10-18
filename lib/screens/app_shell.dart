import 'package:flutter/material.dart';

import '../services/data_source_controller.dart';
import '../services/fcm_service.dart';

import 'alerts_screen.dart';
import 'dashboard_screen.dart';
import 'map_screen.dart';
import 'monitoring_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final DataSourceController _dataSourceController = DataSourceController();

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();

    _initializeDataSource();

    FcmService.openAlertsRequested.addListener(_handleAlertNavigation);

    if (FcmService.openAlertsRequested.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleAlertNavigation();
      });
    }
  }

  Future<void> _initializeDataSource() async {
    await _dataSourceController.initialize();

    if (mounted) {
      setState(() {});
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
      _selectedIndex = 3;
    });
  }

  List<Widget> get _screens {
    final source = _dataSourceController.source;

    return [
      DashboardScreen(simulationService: source),
      MapScreen(simulationService: source),
      MonitoringScreen(
        simulationService: source,
        simulationController: _dataSourceController.isSimulation
            ? _dataSourceController.simulationService
            : null,
      ),
      AlertsScreen(simulationService: source),
    ];
  }

  final List<String> _titles = const [
    'Forest Fire Monitor',
    'Live Map',
    'Monitoring',
    'Alerts',
  ];

  @override
  void dispose() {
    FcmService.openAlertsRequested.removeListener(_handleAlertNavigation);

    _dataSourceController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _dataSourceController,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _titles[_selectedIndex],
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            actions: [
              PopupMenuButton<DataSourceMode>(
                tooltip: 'Data Source',
                icon: Icon(
                  _dataSourceController.isSimulation
                      ? Icons.science_outlined
                      : Icons.cloud_done_outlined,
                ),
                onSelected: (mode) async {
                  if (mode == DataSourceMode.live) {
                    await _dataSourceController.switchToLive();
                  } else {
                    _dataSourceController.switchToSimulation();
                  }

                  if (mounted) {
                    setState(() {});
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<DataSourceMode>(
                    value: DataSourceMode.simulation,
                    child: Row(
                      children: [
                        Icon(
                          Icons.science_outlined,
                          color: _dataSourceController.isSimulation
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 12),
                        const Text('Simulation'),
                        if (_dataSourceController.isSimulation) ...[
                          const Spacer(),
                          const Icon(Icons.check),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuItem<DataSourceMode>(
                    value: DataSourceMode.live,
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_done_outlined,
                          color: _dataSourceController.isLive
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 12),
                        const Text('Live Data'),
                        if (_dataSourceController.isLive) ...[
                          const Spacer(),
                          const Icon(Icons.check),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              if (_selectedIndex == 0 || _selectedIndex == 3)
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_none),
                ),
            ],
          ),
          body: _screens[_selectedIndex],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: 'Map',
              ),
              NavigationDestination(
                icon: Icon(Icons.monitor_heart_outlined),
                selectedIcon: Icon(Icons.monitor_heart),
                label: 'Monitor',
              ),
              NavigationDestination(
                icon: Icon(Icons.notifications_none),
                selectedIcon: Icon(Icons.notifications),
                label: 'Alerts',
              ),
            ],
          ),
        );
      },
    );
  }
}

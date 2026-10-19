import 'package:flutter/material.dart';

import '../utils/friendly.dart';

import '../models/alert_model.dart';

enum UrgentAlertAction { acknowledge, view, dismiss }

/// Full-screen pop-up for a new fire/smoke alert while the app is open.
class UrgentAlertDialog extends StatelessWidget {
  const UrgentAlertDialog({
    super.key,
    required this.alert,
    required this.nodeName,
    required this.canAcknowledge,
  });

  final AlertModel alert;
  final String nodeName;
  final bool canAcknowledge;

  String get _headline => alertTitle(alert.type);

  @override
  Widget build(BuildContext context) {
    final camera = alert.type == 'FIRE' || alert.type == 'SMOKE';
    final confidence = alert.type == 'SMOKE'
        ? alert.smokeProbability
        : alert.fireProbability;

    return Dialog.fullscreen(
      backgroundColor: Colors.red.shade800,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.local_fire_department,
                color: Colors.white,
                size: 96,
              ),
              const SizedBox(height: 12),
              Text(
                _headline,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${levelLabel(alert.severity)} level · $nodeName',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 20),
              if (camera && confidence > 0)
                _line(
                  'Camera AI confidence: ${confidence.toStringAsFixed(0)}%',
                ),
              if (alert.temperature != 0)
                _line(
                  'Temperature: ${alert.temperature.toStringAsFixed(1)} °C',
                ),
              if (alert.humidity != 0)
                _line('Humidity: ${alert.humidity.toStringAsFixed(0)} %'),
              if (alert.latitude != 0 || alert.longitude != 0)
                _line(
                  'Location: ${alert.latitude.toStringAsFixed(5)}, '
                  '${alert.longitude.toStringAsFixed(5)}',
                ),
              const SizedBox(height: 32),
              if (canAcknowledge)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () =>
                        Navigator.pop(context, UrgentAlertAction.acknowledge),
                    icon: const Icon(Icons.check),
                    label: const Text(
                      "Acknowledge (I'm handling it)",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () =>
                      Navigator.pop(context, UrgentAlertAction.view),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Show on map'),
                ),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, UrgentAlertAction.dismiss),
                child: const Text(
                  'Silence',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 16),
    ),
  );
}

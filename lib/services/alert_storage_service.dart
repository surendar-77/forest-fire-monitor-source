import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_model.dart';

class AlertStorageService {
  static const String _historyKey = 'alert_history';
  static const String _currentAlertKey = 'current_alert';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  // ----------------------------------------------------------
  // SAVE ALERT HISTORY
  // ----------------------------------------------------------

  Future<void> saveHistory(List<AlertModel> alerts) async {
    final encoded = alerts.map((alert) => jsonEncode(alert.toJson())).toList();

    await _preferences.setStringList(_historyKey, encoded);
  }

  // ----------------------------------------------------------
  // LOAD ALERT HISTORY
  // ----------------------------------------------------------

  Future<List<AlertModel>> loadHistory() async {
    final encoded = await _preferences.getStringList(_historyKey);

    if (encoded == null || encoded.isEmpty) {
      return [];
    }

    return encoded
        .map(
          (item) =>
              AlertModel.fromJson(jsonDecode(item) as Map<String, dynamic>),
        )
        .toList();
  }

  // ----------------------------------------------------------
  // SAVE CURRENT ALERT
  // ----------------------------------------------------------

  Future<void> saveCurrentAlert(AlertModel? alert) async {
    if (alert == null) {
      await _preferences.remove(_currentAlertKey);
      return;
    }

    await _preferences.setString(_currentAlertKey, jsonEncode(alert.toJson()));
  }

  // ----------------------------------------------------------
  // LOAD CURRENT ALERT
  // ----------------------------------------------------------

  Future<AlertModel?> loadCurrentAlert() async {
    final encoded = await _preferences.getString(_currentAlertKey);

    if (encoded == null) {
      return null;
    }

    return AlertModel.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
  }

  // ----------------------------------------------------------
  // CLEAR ALL HISTORY
  // ----------------------------------------------------------

  Future<void> clearHistory() async {
    await _preferences.remove(_historyKey);

    await _preferences.remove(_currentAlertKey);
  }
}

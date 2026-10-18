import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  static const String _nameKey = 'monitoring_location_name';
  static const String _latitudeKey = 'monitoring_latitude';
  static const String _longitudeKey = 'monitoring_longitude';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  static const String defaultName = 'Forest Zone A';
  static const double defaultLatitude = 13.0827;
  static const double defaultLongitude = 80.2707;

  Future<String> getLocationName() async {
    return await _preferences.getString(_nameKey) ?? defaultName;
  }

  Future<double> getLatitude() async {
    return await _preferences.getDouble(_latitudeKey) ?? defaultLatitude;
  }

  Future<double> getLongitude() async {
    return await _preferences.getDouble(_longitudeKey) ?? defaultLongitude;
  }

  Future<void> saveLocation({
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    await _preferences.setString(_nameKey, name);

    await _preferences.setDouble(_latitudeKey, latitude);

    await _preferences.setDouble(_longitudeKey, longitude);
  }

  Future<void> resetToDefault() async {
    await saveLocation(
      name: defaultName,
      latitude: defaultLatitude,
      longitude: defaultLongitude,
    );
  }
}

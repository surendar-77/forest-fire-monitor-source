/// Build-time configuration, passed with `--dart-define` (or
/// `--dart-define-from-file=config/prod.json`). Nothing here is a secret
/// that must be hidden from users: map and push keys ship inside the app and
/// are restricted by domain/app in their own consoles.
class AppConfig {
  /// `dev` or `prod`.
  static const String environment = String.fromEnvironment(
    'ENV',
    defaultValue: 'dev',
  );

  static bool get isProduction => environment == 'prod';

  /// Web push key from Firebase console → Project settings → Cloud Messaging
  /// → Web Push certificates. Required for notifications in the web app.
  static const String webPushVapidKey = String.fromEnvironment(
    'WEB_PUSH_VAPID_KEY',
  );

  /// Map tiles. The public OpenStreetMap servers forbid production use, so a
  /// keyed provider is used whenever MAP_TILE_URL is set, e.g.
  /// `https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key={key}`.
  static const String mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  static const String mapTileKey = String.fromEnvironment('MAP_TILE_KEY');

  static const String mapAttribution = String.fromEnvironment(
    'MAP_ATTRIBUTION',
    defaultValue: '© OpenStreetMap contributors',
  );

  /// OpenRouteService key for directions to a fire. Without it the app falls
  /// back to the public OSRM demo server, which is for development only.
  static const String routingApiKey = String.fromEnvironment(
    'ROUTING_API_KEY',
  );

  /// Realtime Database that nodes write their per-second readings to
  /// (`live/{nodeId}/values`). Must match RTDB_URL in the node firmware.
  static const String realtimeDatabaseUrl = String.fromEnvironment(
    'REALTIME_DB_URL',
    defaultValue:
        'https://forest-fire-monitor-55cf4-default-rtdb.asia-southeast1.firebasedatabase.app',
  );

  /// Identifies the app to tile servers, as their usage policies require.
  static const String userAgentPackageName = 'com.forestfire.monitor';
}

import 'package:http/http.dart' as http;

import 'app_update_reload_stub.dart'
    if (dart.library.js_interop) 'app_update_reload_web.dart';

/// Update check for the web app (including when installed to a home screen).
///
/// Each deploy stamps a build id into the app (`--dart-define=BUILD_ID=...`)
/// and into `build_id.txt` on the site (see tool/deploy_web.ps1). When the
/// site's id differs from the running one, a newer version has been
/// published and [applyUpdate] reloads into it.
class AppUpdate {
  AppUpdate._();

  static const String buildId = String.fromEnvironment('BUILD_ID');

  /// Only web builds stamped by the deploy script can check.
  static bool get supported => isWeb && buildId.isNotEmpty;

  /// The build id published on the site, or null if it can't be read.
  static Future<String?> publishedBuildId() async {
    if (!supported) return null;
    try {
      final response = await http
          .get(
            Uri.base.resolve(
              'build_id.txt?t=${DateTime.now().millisecondsSinceEpoch}',
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final id = response.body.trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isUpdateAvailable() async {
    final published = await publishedBuildId();
    return published != null && published != buildId;
  }

  /// Reloads the page so the browser fetches the new version.
  static Future<void> applyUpdate() => reloadToNewVersion();
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'app_update_reload_stub.dart'
    if (dart.library.js_interop) 'app_update_reload_web.dart';

/// Where APK releases are published (the Cloudflare Worker's static
/// assets; Firebase Hosting's free plan refuses .apk files).
const String _site =
    'https://forest-fire-backend.forest-fire-worker.workers.dev/';

/// Update check for the web app and the Android APK.
///
/// - Web: each deploy stamps a build id into the app
///   (`--dart-define=BUILD_ID=...`) and into `build_id.txt` on the site
///   (tool/deploy_web.ps1). A different id means a newer version; updating
///   reloads the page.
/// - Android: each APK is built with its build number
///   (`--dart-define=APP_BUILD=...`, tool/release_apk.ps1), which also
///   publishes the APK and `apk/version.json` on the site. A higher build
///   number there means a newer APK; updating downloads and installs it.
class AppUpdate {
  AppUpdate._();

  static const String buildId = String.fromEnvironment('BUILD_ID');

  /// Android: build number and name this APK was released as.
  static const int appBuild = int.fromEnvironment('APP_BUILD');
  static const String appVersion = String.fromEnvironment('APP_VERSION');

  static bool get _isAndroid =>
      !isWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Only builds stamped by the release scripts can check.
  static bool get supported =>
      (isWeb && buildId.isNotEmpty) || (_isAndroid && appBuild > 0);

  /// What the running app is, for Settings.
  static String get currentVersionLabel {
    if (isWeb) return buildId.isEmpty ? 'development build' : 'build $buildId';
    if (appBuild > 0) return 'version $appVersion (build $appBuild)';
    return 'development build';
  }

  static Uri _siteFile(String path) =>
      Uri.parse('$_site$path?t=${DateTime.now().millisecondsSinceEpoch}');

  /// The build id published on the site (web), or null if it can't be read.
  static Future<String?> publishedBuildId() async {
    if (!isWeb || buildId.isEmpty) return null;
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

  /// The latest published APK (Android), or null if it can't be read.
  static Future<ApkRelease?> latestApk() async {
    if (!_isAndroid) return null;
    try {
      final response = await http
          .get(_siteFile('apk/version.json'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      // Tolerate a UTF-8 byte-order mark at the start.
      final body = response.body.replaceFirst('\uFEFF', '');
      return ApkRelease.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// A short description of the update on offer, or null if up to date.
  static Future<String?> availableUpdate() async {
    if (isWeb) {
      final published = await publishedBuildId();
      return published != null && published != buildId
          ? 'build $published'
          : null;
    }
    if (_isAndroid && appBuild > 0) {
      final apk = await latestApk();
      return apk != null && apk.build > appBuild
          ? 'version ${apk.version}'
          : null;
    }
    return null;
  }

  static Future<bool> isUpdateAvailable() async =>
      await availableUpdate() != null;

  /// Web: reload into the new version. Android: download the new APK in the
  /// browser; Android then offers to install it over this one.
  static Future<void> applyUpdate() async {
    if (isWeb) return reloadToNewVersion();
    final apk = await latestApk();
    if (apk == null) return;
    await launchUrl(
      Uri.parse('$_site${apk.path}'),
      mode: LaunchMode.externalApplication,
    );
  }
}

/// An APK release as announced in `apk/version.json`.
class ApkRelease {
  const ApkRelease({
    required this.build,
    required this.version,
    required this.path,
    this.notes = '',
  });

  final int build;
  final String version;

  /// Path on the site, e.g. "apk/ForestFireMonitor-1.0.3.apk".
  final String path;
  final String notes;

  factory ApkRelease.fromJson(Map<String, dynamic> json) => ApkRelease(
    build: (json['build'] as num).toInt(),
    version: json['version'] as String,
    path: json['path'] as String,
    notes: (json['notes'] as String?) ?? '',
  );
}

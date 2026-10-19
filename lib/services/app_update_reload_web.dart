import 'dart:js_interop';

const bool isWeb = true;

@JS('window.location.reload')
external void _reload();

@JS('window.caches')
external _CacheStorage? get _caches;

extension type _CacheStorage._(JSObject _) implements JSObject {
  external JSPromise<JSArray<JSString>> keys();
  external JSPromise<JSBoolean> delete(JSString name);
}

/// Clears any Cache Storage left by older service workers, then reloads.
/// The site serves the app's files with `no-cache`, so the reload fetches
/// whatever changed.
Future<void> reloadToNewVersion() async {
  try {
    final caches = _caches;
    if (caches != null) {
      final names = (await caches.keys().toDart).toDart;
      for (final name in names) {
        await caches.delete(name).toDart;
      }
    }
  } catch (_) {
    // Nothing to clear; reload anyway.
  }
  _reload();
}

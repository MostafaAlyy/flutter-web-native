# Progressive Web Apps (PWA) & Offline Mode

A "native" web application doesn't show a browser dinosaur when the internet disconnects. It loads from cache, allows local interaction, and syncs when reconnected.

## 1. PWA Manifest

Flutter automatically generates a `manifest.json` in the `web/` folder. This file tells the browser that the app is installable (e.g., "Add to Home Screen" on iOS/Android, or "Install App" on Chrome desktop).

**Ensure you customize:**
- `name` and `short_name`
- `theme_color` and `background_color` (matches your initial load splash screen)
- Icons (provide 192x192 and 512x512 PNGs)

## 2. Service Workers and Caching

> **Reality check (3.47).** Flutter no longer ships a caching service worker. `flutter build web` still writes a `flutter_service_worker.js`, but it is a **self-unregistering cleanup worker** for sites that used the old one (`flutter_tools/lib/src/web/file_generators/js/flutter_service_worker.js`); the hidden, deprecated `--pwa-strategy=none` writes an empty file. Older tutorials are obsolete. **Bring your own** worker with standard tooling (e.g. **Workbox**) or a hand-written `sw.js`, registered under a different file name.

The `{{flutter_service_worker_version}}` token still exists in `flutter_bootstrap.js` so a custom worker can key its caches to the current build:

```js
// web/flutter_bootstrap.js
navigator.serviceWorker?.register('sw.js?v={{flutter_service_worker_version}}');
```

Never `importScripts('flutter_service_worker.js')` into your worker — the generated file unregisters the registration it runs in.

Prefer a **Network-First** strategy for HTML/app entrypoints (so a deploy is picked up on the next load) and **Cache-First** only for assets whose names really change per build. `flutter build web` does **not** content-hash `main.dart.js` / `main.dart.wasm` / `main.dart.mjs`, deferred part files, or most `assets/` — cache-first on those serves a stale mix after a deploy unless you hash them at deploy time (see `loading-and-bootstrap.md`).

### Cache-Control headers (as important as the worker)
For Flutter web on a static host, cache-control matters as much as the SW. A proven recipe (Firebase Hosting):

```json
{ "source": "**/*.@(mjs|js|wasm|json)", "headers": [{ "key": "Cache-Control", "value": "max-age=0,s-maxage=604800" }] }
{ "source": "**/*.@(png|jpg|jpeg|webp|svg|woff2)", "headers": [{ "key": "Cache-Control", "value": "max-age=3600,s-maxage=604800" }] }
```

(`s-maxage` lets the CDN cache until the next deploy invalidates it; browsers revalidate. Hosting `headers` rules also override `Cache-Control` set by a Cloud Function on the same path.)

Never serve `*.map` source maps publicly in production.

## 3. Handling Offline State in Dart

You must detect when the browser goes offline and show a graceful UI, rather than letting network requests throw raw SocketExceptions.

Use `connectivity_plus` to listen to the network state.

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

StreamSubscription<List<ConnectivityResult>> subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
  if (results.contains(ConnectivityResult.none)) {
    // Show "You are offline" snackbar or banner
    // Disable form submission buttons
  } else {
    // Trigger background sync for pending actions
  }
});
```

## 4. Background Sync

For a truly native feel, if a user clicks "Save" while offline, the app should save the action to local storage (e.g., `shared_preferences` or `sqflite_common_ffi_web`) and automatically attempt to push the changes to the backend when the network returns.

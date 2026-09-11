# Progressive Web Apps (PWA) & Offline Mode

A "native" web application doesn't show a browser dinosaur when the internet disconnects. It loads from cache, allows local interaction, and syncs when reconnected.

## 1. PWA Manifest

Flutter automatically generates a `manifest.json` in the `web/` folder. This file tells the browser that the app is installable (e.g., "Add to Home Screen" on iOS/Android, or "Install App" on Chrome desktop).

**Ensure you customize:**
- `name` and `short_name`
- `theme_color` and `background_color` (matches your initial load splash screen)
- Icons (provide 192x192 and 512x512 PNGs)

## 2. Service Workers and Caching

> **Reality check.** Flutter no longer generates or manages a service worker by default. Older tutorials (and stale `web/flutter_service_worker.js` files left in a repo) are obsolete. You now **bring your own** worker with standard web tooling (e.g. **Workbox**) or a hand-written `sw.js`.

The `{{flutter_service_worker_version}}` token still exists in `flutter_bootstrap.js` so a custom worker can key its caches to the current build. Use it:

```js
// web/my_custom_worker.js
importScripts('flutter_service_worker.js'); // if you keep a generated shim
// + your own fetch handlers
```

Prefer a **Network-First** strategy for HTML/app entrypoints (so a deploy is picked up on the next load) and **Cache-First** for hashed assets (`main.dart.js`, `canvaskit.wasm`, fonts, images) whose names change per build.

### Cache-Control headers (as important as the worker)
For Flutter web on a static host, cache-control matters as much as the SW. A proven recipe (Firebase Hosting):

```json
{ "source": "**/*.@(mjs|js|wasm|json)", "headers": [{ "key": "Cache-Control", "value": "max-age=0,s-maxage=604800" }] }
{ "source": "**/*.@(png|jpg|jpeg|webp|svg|woff2)", "headers": [{ "key": "Cache-Control", "value": "max-age=3600,s-maxage=604800" }] }
```

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

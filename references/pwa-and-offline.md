# Progressive Web Apps (PWA) & Offline Mode

A "native" web application doesn't show a browser dinosaur when the internet disconnects. It loads from cache, allows local interaction, and syncs when reconnected.

## 1. PWA Manifest

Flutter automatically generates a `manifest.json` in the `web/` folder. This file tells the browser that the app is installable (e.g., "Add to Home Screen" on iOS/Android, or "Install App" on Chrome desktop).

**Ensure you customize:**
- `name` and `short_name`
- `theme_color` and `background_color` (matches your initial load splash screen)
- Icons (provide 192x192 and 512x512 PNGs)

## 2. Service Workers and Caching

Flutter injects a `flutter_service_worker.js`. By default, this caches `main.dart.js`, `canvaskit.wasm`, and your `AssetManifest.json`.

### Customizing the Service Worker
If you need to cache API responses or specific images for offline use, you must modify or wrap the default service worker.

In `web/index.html`:
```javascript
// Registering a custom service worker that imports the flutter one
navigator.serviceWorker.register('/my_custom_worker.js');
```

In `web/my_custom_worker.js`:
```javascript
importScripts('flutter_service_worker.js');

// Add your own fetch event listeners for API caching
self.addEventListener('fetch', (event) => {
  if (event.request.url.includes('/api/v1/')) {
    // Implement Stale-While-Revalidate or Network-First caching
  }
});
```

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

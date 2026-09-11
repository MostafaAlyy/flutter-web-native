# State Sync Across Multiple Tabs

Native web users frequently middle-click to open links in new tabs. If they log out in Tab A, Tab B should immediately log them out. If they add an item to their cart in Tab A, the cart counter in Tab B should update instantly.

Flutter does not do this automatically because memory is isolated per tab.

## 1. The BroadcastChannel API

The cleanest way to sync state across tabs on the same origin is the HTML5 `BroadcastChannel` API.

Using the `web` package (which replaces `dart:html`):

```dart
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:convert';

class TabSyncService {
  late final web.BroadcastChannel _channel;

  TabSyncService() {
    _channel = web.BroadcastChannel('app_state_sync');
    
    // Listen for messages from other tabs
    _channel.onmessage = (web.MessageEvent event) {
      final data = event.data as String;
      final payload = jsonDecode(data);
      
      if (payload['action'] == 'LOGOUT') {
        // Trigger local logout routine
      } else if (payload['action'] == 'CART_UPDATED') {
        // Trigger cart bloc refresh
      }
    }.toJS;
  }

  void broadcastLogout() {
    final payload = jsonEncode({'action': 'LOGOUT'});
    _channel.postMessage(payload.toJS);
  }
}
```

## 2. LocalStorage Event Listener

An alternative, older method is listening to `storage` events on the `window`. When `localStorage` is modified in one tab, the `storage` event fires in **other** tabs.

```dart
import 'package:web/web.dart' as web;
import 'dart:js_interop';

void listenToStorageChanges() {
  web.window.addEventListener('storage', (web.StorageEvent event) {
    if (event.key == 'auth_token' && event.newValue == null) {
      // Token was deleted in another tab, log out here
    }
  }.toJS);
}
```

This method is less reliable for fast messaging but perfect for auth token synchronization.

## 3. WebSockets

If your app uses WebSockets for backend real-time updates (e.g., chat), you get multi-tab sync "for free" because the backend pushes the update to all connected WebSocket clients (one per tab). However, this uses server resources. `BroadcastChannel` is pure client-side and much faster.

# Web Lifecycle, Visibility & Multi-Tab

A browser tab is a first-class environment with its own pause/resume semantics and its own copy of your app's memory. Native web apps react to being hidden and keep multiple tabs consistent.

## 1. Visibility maps to `AppLifecycleState`

The engine wires the browser events into Flutter's lifecycle automatically:

| Browser event | `AppLifecycleState` |
| --- | --- |
| `visibilitychange` → hidden | `hidden` |
| `window.focus` | `resumed` |
| `window.blur` | `inactive` |
| all views gone | `detached` |

Consume it with `WidgetsBindingObserver.didChangeAppLifecycleState` — **guard at entry** before touching `context`:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  switch (state) {
    case AppLifecycleState.hidden:
    case AppLifecycleState.inactive:
    case AppLifecycleState.paused:
      _videoController.pause();   // a hidden tab keeps firing Timers!
      _pausePolling();
    case AppLifecycleState.resumed:
      _revalidateSession();
      _resumePolling();
    case AppLifecycleState.detached:
      break;
  }
}
```

> **Critical:** in a hidden tab `requestAnimationFrame` is throttled (Flutter stops painting) but `Timer`/`StreamSubscription` keep firing. Video/audio do **not** auto-pause. Pause media, polling, and long-lived animations yourself, or a background tab will keep downloading and burning CPU.

## 2. Multi-tab state sync

Each tab has isolated memory, so a logout or cart change in one tab is invisible to the others. Two client-side mechanisms:

### `BroadcastChannel` (fast, structured messages)

```dart
import 'dart:js_interop';
import 'package:web/web.dart' as web;

final _channel = web.BroadcastChannel('app_state');

void broadcastLogout() => _channel.postMessage({'type': 'LOGOUT'}.jsify()!);

void listen() {
  _channel.onmessage = (web.MessageEvent event) {
    final data = event.data.dartify() as Map?;
    if (data?['type'] == 'LOGOUT') _handleRemoteLogout();
  }.toJS;
}
```

Sync the events that must be consistent across tabs: **auth/session** (login, logout, refresh), cart/coins/points, feature flags, theme. Do **not** sync high-frequency UI state.

### `storage` event (for `localStorage`-backed values)

When tab A writes `localStorage`, a `storage` event fires in *other* tabs:

```dart
web.window.addEventListener('storage', (web.StorageEvent e) {
  if (e.key == 'auth_token' && e.newValue == null) _handleRemoteLogout();
}.toJS);
```

Use it for token/deletion signals; it is less reliable for fast messaging than `BroadcastChannel`.

## 3. WebSockets and de-duplication

If the backend pushes over WebSockets, every tab opens its own socket. That is fine, but be deliberate:
- Log out: broadcast so sibling tabs drop their sockets immediately.
- Avoid duplicate side effects (two tabs both firing "mark as read") by keying writes to an idempotency token.
- On `resumed`, reconnect if the socket dropped while hidden.

## 4. Checklist

- [ ] `didChangeAppLifecycleState` pauses media, polling, and animations on hidden/inactive.
- [ ] `resumed` revalidates the session and reconnects sockets.
- [ ] Auth/session changes broadcast to sibling tabs (`BroadcastChannel` and/or `storage`).
- [ ] Cross-tab side effects are idempotent.

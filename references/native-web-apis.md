# Native Web APIs Flutter Doesn't Wrap

These browser capabilities are not part of the Flutter framework. Each is either a plugin or a few lines of `package:web` / `dart:js_interop`. Knowing what is *not* built in prevents reinventing it badly or shipping a website that feels less capable than plain HTML.

| Capability | How | Notes |
| --- | --- | --- |
| **Web Share** (`navigator.share`) | `share_plus` | Mobile + modern desktop; falls back to copy-link. |
| **Clipboard write (rich/image)** | `super_clipboard` | `Clipboard.setData` is plain text only. |
| **Web push** | `firebase_messaging` + a **custom** service worker | `flutter_local_notifications` is **not** web. Web push needs a registered SW; iOS Safari requires the app be installed to Home Screen. |
| **Fullscreen** | `document.documentElement.requestFullscreen()` via `package:web` | Iframes need `allow="fullscreen"`. |
| **PWA install prompt** | Listen for `beforeinstallprompt` via `package:web`, stash it, call `prompt()` on a user gesture | Not exposed by Flutter. |
| **File System Access / save-as** | `file_selector` / `file_picker` use `<input type=file>`; save via an anchor download | No handle-based FS access built in. |
| **Print** | `printing` package | Renders to PDF/print dialog on web. |
| **Analytics SPA page views** | Fire manually on router change | `pushState` is not tracked automatically. |
| **`<dialog>` / popover top-layer** | ❌ unavailable | Flutter paints its own overlays; they won't sit above native browser UI. |

## 1. Fullscreen

```dart
import 'dart:js_interop';
import 'package:web/web.dart' as web;

void enterFullscreen() =>
    web.document.documentElement?.requestFullscreen().toDart;
void exitFullscreen() => web.document.exitFullscreen().toDart;
```

Handle the `fullscreenchange` event so your UI reflects the browser's state when the user presses Esc.

## 2. PWA install prompt

```dart
// Stash the deferred event; call prompt() from a real user tap.
web.window.addEventListener('beforeinstallprompt', (web.Event e) {
  _deferredInstall = e;
}.toJS);
```

If you never call `prompt()` on a user gesture, the browser will eventually show its own mini-infobar — fine, but less controllable.

## 3. Analytics page views on an SPA

Because Flutter uses the History API (path URLs), the browser does not emit a page view per route. Wire your analytics to the router:

```dart
goRouter.routerDelegate.addListener(() {
  final path = goRouter.routerDelegate.currentConfiguration.uri.path;
  analytics.logScreenView(screenName: path);
});
```

Fire once per settled navigation and de-dupe immediate redirects; otherwise login → home can log two views.

## 4. Security-relevant headers (host config, not Dart)

- **CSP**: a strict `Content-Security-Policy` is the strongest XSS mitigation. Flutter supports a `nonce` loader config for engine-injected inline scripts/styles. `'unsafe-eval'` is often needed by dart2js — scope it where you can, and audit `'unsafe-inline'`.
- **`Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy`**: needed only for multithreaded Skwasm (see `wasm-canvaskit-html.md`).
- **`Permissions-Policy`**: disable APIs you don't use (camera, geolocation, microphone).

## 5. Checklist

- [ ] Share/clipboard/fullscreen/print use the right plugin or a small `package:web` shim.
- [ ] Analytics logs a page view on each router navigation (de-duped).
- [ ] Web push has a custom service worker; iOS install prerequisite documented.
- [ ] CSP + security headers set at the host; `*.map` not public.

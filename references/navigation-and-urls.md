# Navigation, URLs & Real Browser Links

Web users interact with URLs directly: bookmarking, sharing, reloading, navigating with browser history buttons (Back/Forward), and middle-clicking links to open in a new tab.

---

## 1. Path URL Strategy (Ditching the `#` Hash)

By default, legacy Flutter Web apps used hash routing (`https://example.com/#/products/123`), which looks like an old prototype. Modern Flutter Web apps should always use clean path URLs (`https://example.com/products/123`).

### Enabling Path URL Strategy
In `lib/main.dart` before `runApp()`:

```dart
import 'package:flutter_web_plugins/url_strategy.dart';

void main() {
  usePathUrlStrategy();
  runApp(const MyApp());
}
```

### Server Configuration for Single Page Applications (SPA)
When using path URL strategy, refreshing the browser at `/dashboard/orders` sends a GET request to the host server for `/dashboard/orders`. The web server (Nginx, Caddy, Cloudflare Pages, Firebase Hosting) must rewrite all non-file routes to `/index.html`:

```nginx
# Nginx SPA rewrite:
location / {
  try_files $uri $uri/ /index.html;
}
```

---

## 2. Middle-Click & "Open in New Tab" (`Link` Widget)

In standard web applications, users frequently middle-click (or right-click → "Open link in new tab") to view multiple items concurrently.
If navigation is implemented strictly with `GestureDetector(onTap: () => context.go(...))`, the browser DOM has no underlying `<a>` tag. Middle-clicking does nothing!

### Using the `Link` Widget
Flutter's `url_launcher` package provides the `Link` widget, which injects an actual HTML `<a>` anchor into the web DOM:

```dart
import 'package:url_launcher/link.dart';

Link(
  uri: Uri.parse('/orders/1024'),
  target: LinkTarget.defaultTarget, // Opens in same tab on tap, allows new tab on middle-click
  builder: (context, followLink) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: followLink,
      child: Text('Order #1024'),
    ),
  ),
);
```

---

## 3. Dynamic Page Title Synchronization

The browser tab title should dynamically update to reflect the current page (e.g. `Orders · ShirtZone Admin`), so users can identify tabs when multiple tabs are open:

```dart
// In MaterialApp:
MaterialApp.router(
  onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
  // ...
);

// On individual screens:
Title(
  title: 'Order #1024 · ShirtZone',
  color: Colors.black,
  child: OrderDetailScreen(),
);
```

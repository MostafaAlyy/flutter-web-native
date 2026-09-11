# SEO, Semantics, & Accessibility (A11y)

Flutter Web renders to a canvas. A canvas is an opaque bitmap to search engine crawlers (Googlebot, Bingbot) and screen readers (VoiceOver, NVDA). Without intervention, a Flutter Web app is a black box.

## 1. The Semantics Tree

Flutter automatically builds a "Semantics Tree" in parallel with the Widget Tree. On the web, Flutter translates this Semantics Tree into a hidden DOM (Document Object Model) overlay composed of native HTML tags (`<p>`, `<button>`, `<input>`, etc.).

### Enabling the Semantics Tree

**On the web, the semantics tree is OFF by default.** It is only built after the user activates the invisible *"Enable accessibility"* button that Flutter injects, or when a screen reader is detected. Until then, a plain Flutter web app presents essentially **no crawlable or readable DOM** — a canvas bitmap with one button.

To force it on (e.g. for debugging, testing, or because you need the DOM for a crawler):

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Web only: build the semantics DOM without waiting for the a11y button.
  if (kIsWeb) {
    SemanticsBinding.instance.ensureSemantics();
  }
  runApp(const MyApp());
}
```

> ⚠️ `debugSemanticsDisableAnimations` does **not** enable semantics — despite the name it only disables semantics-driven animation changes. `ensureSemantics()` is the correct call.

Because a forced semantics tree costs memory and layout work, prefer enabling it on marketing/content routes only, not the entire app on every device. Use `Semantics`, `MergeSemantics`, and `SemanticsRole` so the generated DOM actually conveys structure (headings, lists, buttons).

### Semantics DOM ≠ SEO

Forcing semantics helps screen readers, but it is **not** a search-engine strategy. Flutter's own guidance is explicit: Flutter web *"doesn't align with what search engines need to properly index"* and recommends either:
- building indexable marketing/help content as **real HTML** (or with **Jaspr**, a DOM-based Dart framework), or
- serving **prerendered / server-injected** HTML for the routes that must rank.

Googlebot does render JS, but content that only exists after a heavy Wasm/CanvasKit boot is a poor bet. Anchor tags still matter: a `Link` from `url_launcher` renders a real `<a href>`, which is far more crawlable than a `GestureDetector`.


### Best Practices for Native Semantics
1. **Wrap custom widgets in `Semantics`**:
   ```dart
   Semantics(
     button: true,
     label: 'Submit Order',
     child: MyCustomButton(...),
   )
   ```
2. **Use `MergeSemantics`**: Group related text together so a screen reader doesn't read them as disjointed fragments.
   ```dart
   MergeSemantics(
     child: Row(
       children: [
         Icon(Icons.check),
         Text('Task Complete'),
       ],
     ),
   )
   ```

## 2. Search Engine Optimization (SEO)

Googlebot executes JavaScript, but a Flutter SPA boots into a canvas: raw HTML meta tags per route do **not** exist, and the semantics DOM is off unless a screen reader (or `ensureSemantics`) turns it on. Do not rely on "Googlebot will read the canvas". Treat Flutter web as a JavaScript SPA and use the same playbook as React/Vue SPAs — server-side/prerendered HTML for the routes that must rank, plus the History API (path URLs), unique titles, and JSON-LD.

### Server-Side or Build-Time Meta Tags
If a user shares a link to a specific product (`https://myapp.com/product/123`), Twitter, Facebook, and Google expect `<meta property="og:title" content="...">` in the raw HTML payload *before* JS executes.

**Solution: Server-Side Meta Injection**
You must intercept the request on your hosting server (e.g., Firebase Hosting Functions, Cloudflare Workers, or a Go/Node backend) and inject the proper meta tags into `index.html` before serving it.

```html
<!-- Example of what the server must inject for /product/123 -->
<!DOCTYPE html>
<html>
<head>
  <title>Cool Product</title>
  <meta property="og:title" content="Cool Product" />
  <meta property="og:image" content="https://myapp.com/images/123.jpg" />
  <!-- ... Flutter scripts ... -->
</head>
<body>...</body>
</html>
```

### Flutter-side Title Updates
As the user navigates, update the browser tab title so history and bookmarks make sense.

```dart
import 'package:flutter/services.dart';

void updateTitle(String title) {
  SystemChrome.setApplicationSwitcherDescription(
    ApplicationSwitcherDescription(
      label: title,
      primaryColor: 0xFF000000,
    ),
  );
}
```
If using `go_router` or `auto_route`, tie this to your route changes or use the `Title` widget.

```dart
Title(
  title: 'My Specific Page',
  color: Colors.blue,
  child: MyScreen(),
)
```

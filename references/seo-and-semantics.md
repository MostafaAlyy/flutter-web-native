# SEO, Semantics, & Accessibility (A11y)

Flutter Web renders to a canvas. A canvas is an opaque bitmap to search engine crawlers (Googlebot, Bingbot) and screen readers (VoiceOver, NVDA). Without intervention, a Flutter Web app is a black box.

## 1. The Semantics Tree

Flutter automatically builds a "Semantics Tree" in parallel with the Widget Tree. On the web, Flutter translates this Semantics Tree into a hidden DOM (Document Object Model) overlay composed of native HTML tags (`<p>`, `<button>`, `<input>`, etc.).

### Enabling the Semantics Tree
Screen readers will automatically enable the semantics tree when detected, but you can force it for debugging or testing:
```dart
// Run the app with Semantics enabled forcefully (for debugging)
import 'package:flutter/semantics.dart';

void main() {
  debugSemanticsDisableAnimations = true;
  runApp(const MyApp());
}
```

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

Googlebot does execute JavaScript and will eventually read the semantics DOM tree of a Flutter web app. However, because it's a Single Page Application (SPA), it does not get native HTML meta tags per route automatically.

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

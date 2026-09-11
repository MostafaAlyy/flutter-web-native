# Web Renderers, Wasm, & Memory Management

Flutter Web is not a traditional DOM-based framework. It fundamentally renders to a `<canvas>` (or uses DOM nodes defensively in HTML mode). Understanding the rendering targets is critical for native performance and memory management.

## 1. The Three Renderers

### WebAssembly (Wasm) - The Future (Flutter 3.22+)
- **Compilation**: `flutter build web --wasm`
- **Mechanism**: Compiles Dart code to WasmGC (WebAssembly Garbage Collection).
- **Benefits**: Near-native execution speed, significantly reduced frame rendering times, better memory management because it shares the JavaScript engine's GC directly rather than implementing a GC inside Wasm memory.
- **Drawbacks**: Requires modern browsers supporting WasmGC (Chrome 119+, Firefox 120+, Safari 17.4+).

### CanvasKit (Default for Desktop Web)
- **Mechanism**: Bundles a WebAssembly version of Skia (or Impeller) to draw directly to a `<canvas>`.
- **Benefits**: 100% fidelity with mobile/desktop Flutter. Text shaping, shadows, and paths match exactly.
- **Drawbacks**: Initial download payload includes the CanvasKit Wasm binary (~1.5MB - 2MB compressed). Can suffer from memory leaks if unused images/canvases are not properly disposed.

### HTML Renderer (Deprecated / Legacy)
- **Mechanism**: Uses HTML elements, CSS, Canvas 2D, and SVG elements.
- **Benefits**: Smaller download size.
- **Drawbacks**: Inconsistent rendering across browsers, poorer performance for complex animations, clipping/shadow limitations. **Avoid for production "app-like" experiences.**

## 2. Optimizing Initial Load Time

The biggest "web-feel" killer is a 5-second blank white screen while `main.dart.js` and `canvaskit.wasm` download.

### Strategies:
1. **App Initialization UI (The "Splash" Screen)**:
   Modify `web/index.html` to include a native CSS/HTML loading spinner that renders instantly before the Flutter engine starts.
   ```javascript
   // In flutter_bootstrap.js
   _flutter.buildRunner.run({
     onEntrypointLoaded: async function(engineInitializer) {
       const appRunner = await engineInitializer.initializeEngine();
       document.getElementById('loading-spinner').remove(); // Remove CSS spinner
       await appRunner.runApp();
     }
   });
   ```
2. **Deferred Components**:
   Use Dart's `deferred as` imports to split the JavaScript payload. Load the core routing and auth UI first, then lazy-load heavy feature routes.
   ```dart
   import 'package:heavy_feature/screen.dart' deferred as heavy;
   
   Future<void> navToHeavy() async {
     await heavy.loadLibrary();
     runHeavyApp(heavy.Screen());
   }
   ```

## 3. Memory Leaks and Image Caching

Browsers strictly limit memory per tab. A CanvasKit Flutter app can crash the tab ("Aw, Snap!") if it holds too many large decoded images in memory.

**Native Web Rule**: Aggressively evict images from the `ImageCache`.

```dart
// When leaving a heavy gallery route:
PaintingBinding.instance.imageCache.clear();
PaintingBinding.instance.imageCache.clearLiveImages();
```

For network images, ensure you are using a web-optimized cache strategy or resizing the image *before* decoding it in memory:

```dart
Image.network(
  url,
  cacheWidth: 800, // Forces the decoded bitmap to be smaller, saving MBs of RAM
)
```

## 4. Font Loading Jumps (FOUT/FOIT)

If custom fonts are loaded lazily, the UI text will jump or initially render as boxes. 
- Ensure fonts are pre-loaded in the `AssetManifest` or injected via CSS `@font-face` in `index.html` so the browser fetches them concurrently with the Dart JS payload.

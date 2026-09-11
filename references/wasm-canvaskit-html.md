# Web Renderers, Wasm, & Memory Management

Flutter Web is not a traditional DOM-based framework. It renders to a `<canvas>`. Understanding the rendering targets is critical for native performance and memory management.

> **Reality check (Flutter 3.29+).** The **HTML renderer was removed** and the **`--web-renderer` flag was removed**. Do not write guidance around them. Today there are two real builds: default `dart2js + CanvasKit`, and opt-in `--wasm` (Skwasm).

## 1. Renderers

| Build command | Renderer | Notes |
| --- | --- | --- |
| `flutter build web` (default) | dart2js + **CanvasKit** | Widest browser support. CanvasKit download ≈1.5–2 MB. |
| `flutter build web --wasm` | **Skwasm** (WasmGC) + dart2js/CanvasKit fallback | Best runtime performance; needs WasmGC (Chrome 119+, Firefox 120+, Safari 17.4+). |
| HTML renderer | ❌ removed | Gone since Flutter 3.29. |

Current web build flags: `--wasm`, `--[no-]source-maps`, `--[no-]strip-wasm`, `--[no-]wasm-dry-run`.

Detect the runtime at compile time:

```dart
const isRunningWithWasm = bool.fromEnvironment('dart.tool.dart2wasm');
```

### Wasm caveats that bite production
- **Multithreaded Skwasm requires cross-origin isolation**: `Cross-Origin-Embedder-Policy: credentialless` (or `require-corp`) **and** `Cross-Origin-Opener-Policy: same-origin`. If you cannot set those — e.g. they break a cross-origin iframe player — set `forceSingleThreadedSkwasm: true` in the `flutter_bootstrap.js` config instead.
- **No Wasm on iOS**: every iOS browser is WebKit and lacks WasmGC. Keep emitting the dart2js fallback build.
- The loader's default wasm allow-list is `{blink:true, gecko:false, webkit:false, unknown:false}`. Pinning `renderer` in the loader config can make the loader reject the built artifact and leave users stuck on the splash; prefer letting the loader choose, or ship both builds.

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

# Web Renderers, Wasm, & Memory Management

Flutter Web is not a traditional DOM-based framework. It renders to a `<canvas>`. Understanding the rendering targets is critical for native performance and memory management.

> **Reality check (Flutter 3.29+, verified on 3.47).** The **HTML renderer was removed** and the **`--web-renderer` flag was removed**. Do not write guidance around them. Today there are two real builds: default `dart2js + CanvasKit`, and opt-in `--wasm` (Skwasm, with a dart2js/CanvasKit fallback in the same output).

## 1. Renderers

| Build command | Renderer | Notes |
| --- | --- | --- |
| `flutter build web` (default) | dart2js + **CanvasKit** | Widest support. CanvasKit is loaded from `https://www.gstatic.com/flutter-canvaskit/<engineRevision>/` unless you build with `--no-web-resources-cdn`; the `chromium/` variant (smaller, uses browser codecs/ICU) is picked on Chromium. |
| `flutter build web --wasm` | **Skwasm** (dart2wasm) + dart2js/CanvasKit fallback | Best runtime performance where it runs. See the browser allow-list below. |
| HTML renderer | ❌ removed | Gone since Flutter 3.29. |

Current `flutter build web` flags worth knowing (`flutter_tools/lib/src/commands/build_web.dart`): `--wasm`, `--[no-]source-maps`, `--[no-]strip-wasm`, `--[no-]wasm-dry-run`, `--optimization-level`, `--[no-]minify-js`, `--[no-]minify-wasm`, `--static-assets-url`, `--[no-]web-resources-cdn`, `--csp`, `--dump-info`. `--pwa-strategy` is hidden and deprecated.

Detect the runtime at compile time:

```dart
const isRunningWithWasm = bool.fromEnvironment('dart.tool.dart2wasm');
```

### Who actually gets Skwasm (`flutter_js/src/loader.js`, `browser_environment.js`)
- The loader picks the first compatible build. Skwasm requires **WasmGC**, **WebGL**, and the browser engine being enabled in `wasmAllowList`.
- The **default allow-list is `{blink: true, gecko: false, webkit: false, unknown: false}`**: Chrome/Edge get Skwasm; **Firefox and Safari get dart2js + CanvasKit by default**, even though they implement WasmGC. Override per engine with `config.wasmAllowList` only after testing there.
- On browsers without `ImageDecoder` or Chromium break iterators, Skwasm loads the larger `skwasm_heavy` variant (`skwasm_loader.js`).
- Pinning `config.renderer` to a renderer the build doesn't contain makes every candidate incompatible and the loader **throws** — users sit on the splash. Prefer letting the loader choose; debug selection with `verboseBuildSelection: true`.
- Keep emitting the dart2js fallback; iOS browsers are all WebKit.

### Threading: single-threaded Skwasm is the common case
- **Multithreaded Skwasm requires cross-origin isolation**: `Cross-Origin-Opener-Policy: same-origin` **and** `Cross-Origin-Embedder-Policy: require-corp` (or `credentialless`). `require-corp` breaks third-party iframes (YouTube, most embeds) and cross-origin resources without CORP/CORS.
- Without isolation, the loader **automatically** runs Skwasm single-threaded and logs a console warning (`skwasm_loader.js`: `skwasmSingleThreaded: … || !crossOriginIsolated || … || config.forceSingleThreadedSkwasm`). Set `suppressMultithreadingWarning: true` when that is deliberate. `forceSingleThreadedSkwasm: true` forces single-threaded even on an isolated page.
- Single-threaded Skwasm does all raster work on the UI thread, and the web has **no picture raster cache**. Always-on animation is therefore far more expensive than on native — read `raster-performance.md`.

## 2. Optimizing Initial Load Time

The biggest "web-feel" killer is a blank white screen while the entrypoint and renderer download and compile. Full playbook in `loading-and-bootstrap.md`; the essentials:

1. **HTML splash that paints instantly** (it is also your LCP element):
   ```js
   // In web/flutter_bootstrap.js
   {{flutter_js}}
   {{flutter_build_config}}
   _flutter.loader.load({
     onEntrypointLoaded: async (engineInitializer) => {
       const appRunner = await engineInitializer.initializeEngine();
       await appRunner.runApp();
       document.getElementById('splash')?.remove();
     },
   });
   ```
2. **Deferred libraries**: split heavy feature routes with `deferred as`; load the core shell first.
   ```dart
   import 'package:my_app/heavy_feature/screen.dart' deferred as heavy;

   Future<void> openHeavy(BuildContext context) async {
     await heavy.loadLibrary();
     if (!context.mounted) return;
     Navigator.of(context).push(MaterialPageRoute(builder: (_) => heavy.HeavyScreen()));
   }
   ```
   Deferred part files are not content-hashed by the build — serve them `no-cache` unless you hash them yourself.
3. **Parallelize the critical path**: preload what the loader will fetch, modulepreload third-party SDKs `main()` awaits (Firebase), don't start plugin wasm the first screen doesn't use.

## 3. Memory and Image Caching

Browsers strictly limit memory per tab. A Flutter web app can crash the tab ("Aw, Snap!") if it holds too many large decoded images.

1. **Decode at display size** — the biggest win, everywhere:
   ```dart
   Image.network(
     url,
     cacheWidth: 800, // decoded bitmap is ~800 px wide, not the source size
   )
   ```
   (`ResizeImage` for custom providers.)
2. **Bound the cache** for image-heavy apps: `PaintingBinding.instance.imageCache.maximumSizeBytes = 64 << 20;`
3. **Evict where it matters** when leaving a genuinely heavy route (gallery, PDF thumbnails):
   ```dart
   PaintingBinding.instance.imageCache.clear();
   PaintingBinding.instance.imageCache.clearLiveImages();
   ```
   Don't `clear()` on every navigation — it destroys hit rates and re-decodes cost main-thread time on single-threaded renderers.
4. **Dispose `ui.Image`s you create** (`toImageSync`, `decodeImageFromList`, texture caches). They are GPU memory on the web too.

## 4. Font Loading Jumps (FOUT/FOIT)

- The engine downloads every font in `FontManifest.json` during initialization, before `main()` — so fonts there never "jump", but each one is a boot cost. Trim the web manifest to what the first screen needs and load the rest on demand.
- Preload the remaining fonts with `<link rel="preload" as="fetch" crossorigin="anonymous">`.
- Bundle the glyphs you render; missing glyphs trigger runtime fallback-font fetches from `fontFallbackBaseUrl` (default `https://fonts.gstatic.com/s/`), which do cause visible swaps.

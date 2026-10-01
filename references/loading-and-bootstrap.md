# Loading, Bootstrap, Boot Critical Path & Delivery

The single biggest "this is not a native app" moment is a long blank/white screen while the engine boots. A native web app shows *something* immediately and keeps the user informed. This file covers `flutter_bootstrap.js`, the loading UI, the **boot critical path** (what actually gates the first Flutter frame), and the **delivery** details (compression, caching, Lighthouse hygiene) that decide whether first and repeat visits feel instant.

Measure before and after every change here — `performance-measurement.md`.

## 1. `flutter_bootstrap.js` and the loader

`flutter build web` emits `flutter_bootstrap.js` from your `web/` template. The build substitutes tokens into it:

- `{{flutter_js}}` — the `flutter.js` loader.
- `{{flutter_build_config}}` — the build metadata (`builds[]` with `compileTarget`, `renderer`, `mainJsPath` / `mainWasmPath` + `jsSupportRuntimePath`, `engineRevision`).
- `{{flutter_bootstrap_js}}` — only in `index.html`, inlines the generated bootstrap.
- `{{flutter_service_worker_version}}` — only relevant if you ship a **custom** service worker.

Minimal custom bootstrap:

```js
{{flutter_js}}
{{flutter_build_config}}

const loading = document.createElement('div');
loading.id = 'app-loading';
loading.textContent = 'Loading…';
document.body.appendChild(loading);

_flutter.loader.load({
  onEntrypointLoaded: async (engineInitializer) => {
    loading.textContent = 'Initializing engine…';
    const appRunner = await engineInitializer.initializeEngine();
    loading.textContent = 'Starting…';
    await appRunner.runApp();
    loading.remove();
  },
});
```

> ⚠️ **Config gotcha (verified, `flutter_js/src/entrypoint_loader.js`).** The `config` you pass to `_flutter.loader.load({ config })` is used by **flutter.js itself** (build selection, `wasmAllowList`, `renderer`, `canvasKitVariant`, `forceSingleThreadedSkwasm`, `suppressMultithreadingWarning`, `verboseBuildSelection`), but when you supply `onEntrypointLoaded` it is **not forwarded** to the engine — only the default callback calls `initializeEngine(config)`. Pass engine keys (`hostElement`, `multiViewEnabled`, `nonce`, `canvasKitBaseUrl`, `fontFallbackBaseUrl`, …) to `initializeEngine(config)` yourself, and keep loader keys in `load({ config })`. Passing the same object to both is simplest.

Keep the pre-Flutter splash (plain HTML/CSS) in `index.html`; remove it after `runApp()` resolves or on the `flutter-first-frame` window event. It is the only thing painted before the Dart entrypoint runs — and usually the page's LCP element (section 7).

## 2. Getting the first paint fast

1. **Serve a real loading indicator** (HTML/CSS, not Flutter). A 3–5 s white screen reads as broken; a branded splash reads as loading.
2. **Preload the entrypoint the loader will actually pick** (section 4) and `preconnect` to third-party origins on the critical path.
3. **Defer non-critical work** with Dart `deferred as` imports so route code is fetched on demand.
4. **Add a first-frame watchdog.** Loader errors are easy to catch; a boot that downloads everything and then never paints (a hang inside startup, a lost GPU context, stale client state that throws nothing) leaves users on the splash forever. In the bootstrap, start a clock only once the app binary (`main.dart*.wasm|js`) and engine (`skwasm*.wasm` / `canvaskit.wasm`) show `responseEnd > 0` in Resource Timing; count only visible time (`document.hidden` tabs get no frames); if `flutter-first-frame` hasn't fired after ~30 s, purge service workers + Cache Storage and reload once (sessionStorage-guarded, cache-busting the entrypoints), and on a second stall show a retry screen. Slow networks never trip it because the clock starts after the downloads.
5. **Don't block the first frame on network.** Resolve auth/tenant/remote-config after the first frame where possible; a splash that waits on a slow API is a splash that hangs. If you *must* await something before `runApp`, make sure its fetches start at HTML-parse time (section 3).

## 3. The boot critical path: hidden serial chains

The first frame waits for: HTML → bootstrap → entrypoint (`main.dart.mjs` + `main.dart.wasm`, or `main.dart.js`) + renderer (`skwasm.wasm` / `canvaskit.wasm`) → `main()` → everything `main()` awaits before `runApp` → fonts in `FontManifest.json` → first build/layout/raster. Anything that only *starts* once Dart is running is serialized behind the whole wasm download and compile.

### 3a. Firebase JS SDK (FlutterFire web)

`firebase_core_web` loads the Firebase JS SDK lazily inside `Firebase.initializeApp`, by injecting tiny inline scripts that run dynamic `import()`s of `https://www.gstatic.com/firebasejs/<version>/firebase-<service>.js` (`firebase_core_web/lib/src/firebase_core_web.dart`, `injectSrcScript` / `_initializeCore`). Two consequences:

- The fetches **start only after the app's wasm is running**.
- `firebase-app.js` is loaded **strictly before** the service bundles (auth, app-check, analytics, …) — a deliberate serial step that works around a WebKit module-evaluation TDZ defect ([flutterfire#18436](https://github.com/firebase/flutterfire/issues/18436)).

If `main()` awaits `Firebase.initializeApp` before `runApp`, that chain sits on the first-frame critical path. On the reference app it measured **~3.6 s on throttled mobile**.

**Fix: modulepreload every bundle at HTML-parse time — on Blink only**, so the `import()`s resolve from the module map instantly:

```js
// Inside the inline boot script that already mirrors flutter.js renderer
// selection (section 4): only the WasmGC + Blink branch.
if (wasmGC && blink) {
  ["https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js",
   "https://www.gstatic.com/firebasejs/12.19.0/firebase-auth.js"]
    .forEach(function (href) { add(href, "modulepreload", null, false); });
}
```

- **Do not ship static `<link rel="modulepreload">` tags for these to WebKit.** FlutterFire serialises `firebase-app.js` before the service bundles *because* concurrent loading of that module graph trips a WebKit evaluation defect; preloading all of them at once at parse time reintroduces exactly that concurrency for Safari and every iOS browser. Gate them on the same Blink check your entry-point preloads use. (Lesson from production, 2026-10-01: static tags shipped to every browser; mobile/Safari users reported an endless splash and the tags were moved behind the Blink gate the same day.)
- Measure the side effect too: Lighthouse's simulated FCP treats High-priority head scripts as render-blocking, so a block of module preloads can *raise* simulated FCP even though real browsers paint the splash immediately.

- **Bare tags, no `crossorigin` attribute** — that matches the credentials mode of the SDK's dynamic `import()`; a mismatched preload is fetched twice.
- **Never hardcode the version or the list.** Generate them at build/deploy time from the resolved packages:
  - version: `supportedFirebaseJsSdkVersion` in `<firebase_core_web>/lib/src/firebase_sdk_version.dart`;
  - services: `"app"` (core) + every `FirebaseCoreWeb.registerService('<name>'` call in each `firebase_*_web` package's `lib/` (the call may span lines);
  - package roots: `.dart_tool/package_config.json` (`rootUri`).
  - `'firestore'` maps to **`firebase-firestore-pipelines.js`**, not `firebase-firestore.js`.

  A stale preload list after a FlutterFire bump wastes bandwidth on bundles nobody imports and leaves the real ones serial again. (`scripts/audit_web_fidelity.sh` flags preloads whose version doesn't match the resolved `firebase_core_web`.)
- Alternatively, defer `Firebase.initializeApp` until after the first frame if nothing on the first screen needs it.
- `window.flutterfire_ignore_scripts = ['auth', …]` makes `firebase_core_web` skip injecting those services (for when you load them yourself).

### 3b. Heavy plugin wasm loaded eagerly

Plugins with their own wasm are a common hidden cost. Example: calling `pdfrxFlutterInitialize()` at startup on web spins up pdfrx's worker, which downloads and compiles `pdfium.wasm` (5.2 MB raw in pdfrx 2.6.5; ~1.8 MB transferred compressed in the measured app) on **every cold visit** — landing page included — competing with the app's own wasm and fonts.

- pdfrx widgets (`PdfViewer`, `PdfDocumentViewBuilder`, …) and `PdfDocumentRef` loaders call `pdfrxFlutterInitialize()` themselves (`pdfrx/lib/src/pdf_document_ref.dart`, `widgets/pdf_viewer.dart`). It is idempotent.
- Only **direct** `PdfDocument.open*` calls need an explicit `await pdfrxFlutterInitialize();` first.
- So: don't initialize eagerly on web (`if (!kIsWeb) …` around the boot-time call); add the explicit await next to direct `open*` calls.

General rule: **audit Lighthouse's network-requests for plugin `.wasm`/`.js` the first screen doesn't use.** Worker-initiated fetches won't show in a naive CDP probe (see `performance-measurement.md`).

### 3c. Third-party boot fetches to know about

Verified in source; decide deliberately whether each belongs on the first screen:

- **`google_sign_in_web`** loads `https://accounts.google.com/gsi/client` from the **plugin constructor** — i.e. at plugin registration, before `main()` (`google_sign_in_web/lib/google_sign_in_web.dart` → `loader.loadWebSdk()`, URL in `google_identity_services_web/lib/src/js_loader.dart`).
- **`firebase_auth_web`** initializes auth with `popupRedirectResolver: browserPopupRedirectResolver` (`firebase_auth_web/lib/src/interop/auth.dart`). In the Firebase JS SDK that resolver initializes **proactively on mobile browsers, Safari and iOS** (`_shouldInitProactively` in `@firebase/auth`), opening a hidden `https://<authDomain>/__/auth/iframe` (plus gapi) during auth init. On a mobile Lighthouse run it appears as auth-iframe traffic during boot.

### 3d. Fonts gate the first frame

The engine downloads every font in `FontManifest.json` during engine initialization — in parallel with renderer init and **before your `main()` runs** (`engine/.../initialization.dart`, `_downloadAssetFonts`, awaited in `initializeEngineServices`; plugins register and `main()` runs afterwards, `ui_web/src/ui_web/initialization.dart`). Each decorative or fallback family listed there is a boot download.
- Trim the **web** manifest to what the first screen renders; load the rest on demand (`FontLoader` / `loadFontFromList`) when a route needs it.
- Preload the remaining ones (and `assets/FontManifest.json` itself): `<link rel="preload" href="assets/fonts/X.ttf" as="fetch" crossorigin="anonymous">` — the engine fetches assets with `fetch()` (`ui_web` `AssetManager.loadAsset` → `httpFetch`), so the preload must be a CORS-mode fetch preload.
- Bundle glyph coverage you need; otherwise the engine fetches fallback fonts from `fontFallbackBaseUrl` (default `https://fonts.gstatic.com/s/`) mid-session.

## 4. Entry-point preloads must mirror flutter.js

A preload for a file the loader won't request is pure waste; a preload with the wrong mode is fetched twice. Mirror the loader's decision (`flutter_js/src/loader.js`, `browser_environment.js`):

| Browser | Build the loader picks (default config) | What it fetches | Preload |
| --- | --- | --- | --- |
| Blink with WasmGC + WebGL | dart2wasm + **Skwasm** | `import(main.dart.mjs)`, `fetch(main.dart.wasm)`, `import(skwasm.js)`, `fetch(skwasm.wasm)` | `modulepreload` for `.mjs`/`skwasm.js` (bare); `preload as="fetch" crossorigin` for both `.wasm` |
| Gecko / WebKit / anything else | dart2js + **CanvasKit** | classic `<script src=main.dart.js>`, CanvasKit `import()` + `fetch()` | `preload as="script"` **without** `crossorigin` for `main.dart.js` |

Details that bite:
- The default `wasmAllowList` is `{blink: true, gecko: false, webkit: false, unknown: false}`. Firefox and Safari get **dart2js + CanvasKit** by default even though they implement WasmGC.
- Skwasm loads `skwasm_heavy.{js,wasm}` instead of `skwasm.*` when the browser lacks `ImageDecoder` or `Intl.v8BreakIterator`/`Intl.Segmenter` (`skwasm_loader.js`).
- CanvasKit picks the `chromium/` variant on Chromium (`canvaskit_loader.js`), and by default loads from `https://www.gstatic.com/flutter-canvaskit/<engineRevision>/` unless built with `--no-web-resources-cdn` (sets `useLocalCanvasKit`; `utils.js`, `getCanvaskitBaseUrl`) — preconnect to gstatic, or self-host.
- **Never** `<link rel="modulepreload" href="main.dart.js">`: `main.dart.js` is a classic script (`entrypoint_loader.js` creates `<script type="application/javascript">`).
- Since preloads are static HTML and the choice is runtime, either preload only the Blink path (most traffic) or inject preloads from a tiny inline script that repeats the loader's checks.
- Setting `config.renderer` to something the build doesn't contain makes the loader skip every build and throw ("could not find a build compatible…"): a blank page. Use `verboseBuildSelection: true` to see why candidates were skipped.

## 5. Only `<link>/<style>/<script>` may be injected into `<head>`

If a deploy step injects markup into `<head>`, inject only `<link>`, `<style>` and `<script>` (the HTML spec also allows `<meta>`, `<title>`, `<base>`, `<noscript>`, `<template>`). Any other element — a `<div>`, `<img>`, `<picture>` — makes the parser **close `<head>` early**: everything after it, including a CSP `<meta>` and your preloads, silently lands in `<body>` (a CSP `<meta>` outside `<head>` is ignored). Put visual splash markup in `<body>`. The audit script flags non-metadata elements inside `<head>` of `web/index.html`.

## 6. Caching headers decide repeat-visit speed

Prove names are content-hashed before caching them forever. `flutter build web` does **not** hash `main.dart.*`, `flutter_bootstrap.js`, `flutter.js` or most `assets/` names.

```
# Content-hashed files only (e.g. main.dart.<hash>.wasm renamed at deploy) — immutable
**/*.<hash>.@(wasm|mjs|js)                        →  public, max-age=31536000, immutable
# Unhashed: HTML, bootstrap, entrypoints, part files, manifests — revalidate
index.html, flutter_bootstrap.js, main.dart.*,
main.dart.mjs part files, *.json                  →  no-cache   (or max-age=0, must-revalidate)
# Unhashed static assets — short TTL
/assets/**                                        →  public, max-age=3600
```

- **Content-hash the entrypoints at deploy** (`main.dart.<hash>.wasm/.mjs/.js`) and rewrite the paths in `flutter_bootstrap.js`'s build config — then they can be immutable. Any **unhashed** part files (deferred-library chunks) must stay `no-cache`, or a deploy mixes chunks from two builds.
- Never cache `index.html` long: it is how the next deploy is discovered.
- **Firebase Hosting `headers` rules override a Cloud Function's `Cache-Control`** for the same path. If a function renders HTML, don't also match that path with a hosting header rule unless you mean it.

## 7. Delivery & Lighthouse hygiene

- **Compression for function-rendered HTML.** HTML served by a Cloud Function behind Firebase Hosting is **not** compressed by Hosting. Negotiate `br`/`gzip` in the function from `Accept-Encoding`, cache the compressed bodies, and add `Vary: Accept-Encoding`.
- **Splash `<img>` is the LCP element.** Give it explicit `width`/`height` (the 1× intrinsic size when using density `srcset`) and `fetchpriority="high"`. Don't add `decoding="async"` or `loading="lazy"` to it.
- **Source maps.** `flutter.js` (and therefore the inlined bootstrap) ships `//# sourceMappingURL=flutter.js.map`. If the map isn't deployed, the SPA fallback answers that URL with HTML and Lighthouse's **valid-source-maps** fails. Strip the comment at deploy (before computing any content stamp of the bootstrap), or deploy the map deliberately.
- **robots.txt** must only contain directives Lighthouse's **robots-txt** audit recognizes (`User-agent`, `Allow`, `Disallow`, `Sitemap`, `Crawl-delay`, `Host`, …). Non-standard hints like `LLM-Txt:` fail it — keep them as `#` comments.
- **Agentic-browsing discovery.** Lighthouse 13.5's `ard-schema` audit probes robots `Agentmap:` → `<link rel="ai-catalog">` → a `Link` header → `/.well-known/ai-catalog.json` (ARD spec 1.0). An SPA fallback that answers `/.well-known/ai-catalog.json` with HTML fails it. Serve a valid JSON file (its entries may be empty) and return **404 for unknown `/.well-known/*`** instead of the app shell.
- **Unfixable "deprecations".** Best-Practices items raised by engine/loader code — the `SharedArrayBuffer` check in `skwasm.js` without cross-origin isolation, `Intl.v8BreakIterator` probing in `flutter.js` — can't be fixed from the app. Document them instead of chasing them.
- **Honest target.** Lighthouse mobile Performance 100 is not reachable for a canvas app (structural TBT). Aim for: instant splash, no serial third-party chains, minimal boot bytes, no animation during load.

## 8. Service worker: bring your own (or none)

Flutter no longer ships a caching service worker. Since the deprecation, `flutter build web` still emits a `flutter_service_worker.js` **that unregisters itself** and reloads clients (a cleanup worker for sites that used the old one; `flutter_tools/lib/src/web/file_generators/js/flutter_service_worker.js`), unless you pass the hidden, deprecated `--pwa-strategy=none`, which writes an empty file. If you want offline/PWA behavior, register your own (Workbox recommended) — see `pwa-and-offline.md`. Never `importScripts('flutter_service_worker.js')` into your own worker: it would unregister it.

## 9. Checklist

- [ ] Custom bootstrap shows a branded loading UI and removes it on `runApp()` / `flutter-first-frame`.
- [ ] Loader keys in `load({config})`, engine keys in `initializeEngine(config)`.
- [ ] Nothing awaited before `runApp` starts its network only once Dart runs (Firebase modulepreloads generated from resolved packages, or init deferred).
- [ ] No plugin wasm (pdfium etc.) on the first screen unless it is used there.
- [ ] Entry preloads mirror the loader's renderer choice and fetch modes.
- [ ] `FontManifest.json` trimmed for web; remaining fonts preloaded `as=fetch crossorigin`.
- [ ] Only `<link>/<style>/<script>` injected into `<head>`.
- [ ] Hashed assets immutable; unhashed entrypoints/parts/HTML revalidate; hosting header rules don't fight the function.
- [ ] HTML compressed (incl. function-rendered), `Vary: Accept-Encoding`.
- [ ] Splash `<img>` has width/height + `fetchpriority="high"`; no `sourceMappingURL` to a missing map; robots.txt directives standard; `/.well-known/*` 404s or serves real files.

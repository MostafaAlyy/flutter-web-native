# Loading, Bootstrap & Caching

The single biggest "this is not a native app" moment is a long blank/white screen while the engine boots. A native web app shows *something* immediately and keeps the user informed. This file covers `flutter_bootstrap.js`, the loading UI, and the HTTP caching that decides whether repeat visits feel instant.

## 1. `flutter_bootstrap.js` and the loader

`flutter build web` emits `web/flutter_bootstrap.js` from your `web/index.html`. The build substitutes tokens into it:

- `{{flutter_js}}` — the `flutter.js` loader.
- `{{flutter_build_config}}` — the selected build's metadata (main script, renderer, etc.).
- `{{flutter_bootstrap_js}}` — only in `index.html`, injects the generated bootstrap.
- `{{flutter_service_worker_version}}` — only relevant if you ship a **custom** service worker (Flutter no longer generates one).

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

> ⚠️ **Config gotcha.** When you pass `onEntrypointLoaded`, the `config` object passed to `_flutter.loader.load({ config })` is **not forwarded** to the engine. Pass it to `initializeEngine(config)` yourself. Common config keys: `hostElement`, `multiViewEnabled`, `nonce` (CSP), `forceSingleThreadedSkwasm`, `canvasKitBaseUrl`, `fontFallbackBaseUrl`.

Keep the pre-Flutter splash (a plain HTML/CSS brand screen) in `index.html`; remove it from `runApp()` completion or from the bootstrap as above. It is the only thing painted before the Dart entrypoint runs.

## 2. Getting the first paint fast

1. **Preconnect / preload the critical engine files** so the browser starts fetching them during HTML parse:

   ```html
   <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
   <link rel="modulepreload" href="main.dart.js">
   ```

2. **Serve a real loading indicator** (HTML/CSS, not Flutter). A 3–5s white screen reads as broken; a branded spinner reads as loading.
3. **Defer non-critical work** with Dart `deferred as` imports so route code is fetched on demand.
4. **Don't block first frame on network.** Resolve auth/tenant/remote-config after the first frame where possible; a splash that waits on a slow API is a splash that hangs.

## 3. Caching headers decide repeat-visit speed

Set `Cache-Control` at the host. Prove the names are content-hashed before caching them forever.

```
# Hashed assets — immutable
/assets/**, **/*.@(wasm|mjs|js), canvaskit/**   →  Cache-Control: public, max-age=31536000, immutable
# HTML + entrypoints — revalidate so deploys land
**/*.html, flutter_bootstrap.js, main.dart.js    →  Cache-Control: max-age=0, s-maxage=604800
```

Never cache `index.html` for long: it is how the next deploy is discovered. Never publish `*.map` source maps.

## 4. Service worker: bring your own

Flutter no longer registers a service worker for you. If you want offline/PWA behavior, register your own (Workbox recommended) — see `pwa-and-offline.md`. If you do **not** want one, remove any stale `web/flutter_service_worker.js`; leaving a dead worker (or unregistering workers while shipping the file) is confusing and can mask caching bugs.

## 5. Checklist

- [ ] Custom `flutter_bootstrap.js` shows a branded loading UI and removes it on `runApp()`.
- [ ] `initializeEngine(config)` receives any loader config you set.
- [ ] `theme-color` meta matches the splash for first paint / PWA status bar.
- [ ] Hashed assets immutable; `index.html` and entrypoints revalidate.
- [ ] Service worker is deliberate: either a real custom one or none at all.

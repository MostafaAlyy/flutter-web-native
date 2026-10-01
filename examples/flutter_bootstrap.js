// Reference web/flutter_bootstrap.js for a production Flutter web app (3.47).
//
// Key points:
// 1. A branded splash is painted by plain HTML/CSS in index.html *before* the
//    engine boots (it is usually the page's LCP element). It is removed once
//    the first Flutter frame is on screen. Never leave a blank white screen
//    while main.dart.* / skwasm / canvaskit download.
// 2. `load({config})` is read by flutter.js itself (build selection,
//    wasmAllowList, renderer, forceSingleThreadedSkwasm,
//    suppressMultithreadingWarning, verboseBuildSelection). But when you pass
//    `onEntrypointLoaded`, that config is NOT forwarded to the engine — pass
//    engine keys (hostElement, nonce, fontFallbackBaseUrl, ...) to
//    initializeEngine(config) yourself. Passing one object to both is simplest.
// 3. Let the loader choose the renderer. Pinning `renderer` to one the build
//    doesn't contain makes the loader throw: users stay on the splash.
// 4. Without COOP/COEP headers Skwasm automatically runs single-threaded and
//    logs a warning; `suppressMultithreadingWarning` silences it when that is a
//    deliberate choice (e.g. COEP would break YouTube iframes). Single-threaded
//    Skwasm renders on the UI thread — see references/raster-performance.md.
// 5. Flutter no longer ships a caching service worker (the generated
//    flutter_service_worker.js unregisters itself). Register your own here if
//    you want offline/PWA behavior (Workbox recommended), under another name.

{{flutter_js}}
{{flutter_build_config}}

(function bootstrap() {
  var config = {
    suppressMultithreadingWarning: true,
    // verboseBuildSelection: true, // debug "why did it fall back to dart2js?"
  };

  var status = document.getElementById('app-loading');
  if (!status) {
    status = document.createElement('div');
    status.id = 'app-loading';
    status.setAttribute('role', 'status');
    status.setAttribute('aria-live', 'polite');
    status.textContent = 'Loading…';
    document.body.appendChild(status);
  }

  // The framework fires this after the first frame is rasterized
  // (rendering/binding.dart -> flutter/service_worker channel -> engine).
  window.addEventListener('flutter-first-frame', function () {
    var splash = document.getElementById('splash');
    if (splash) splash.remove();
    status.remove();
  }, { once: true });

  _flutter.loader.load({
    config: config,
    onEntrypointLoaded: async function (engineInitializer) {
      status.textContent = 'Preparing…';
      var appRunner = await engineInitializer.initializeEngine(config);
      status.textContent = 'Starting…';
      await appRunner.runApp();
    },
  });
})();

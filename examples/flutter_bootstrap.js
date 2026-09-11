// Reference web/flutter_bootstrap.js for a production Flutter web app.
//
// Key points:
// 1. A branded loading UI is painted by plain HTML/CSS *before* the engine
//    boots; it is removed once runApp() completes. Never leave a blank white
//    screen while main.dart.js / canvaskit / skwasm download.
// 2. When you pass `onEntrypointLoaded`, the loader `config` is NOT forwarded
//    to initializeEngine(). Pass it yourself or wasm/COOP settings are lost.
// 3. Let the loader choose the renderer unless you ship both builds; pinning a
//    renderer that doesn't match the artifact can strand users on the splash.
// 4. Flutter no longer generates a service worker — register your own here if
//    you want offline/PWA behavior (Workbox recommended).

{{flutter_js}}
{{flutter_build_config}}

(function bootstrap() {
  // Config that MUST reach initializeEngine(config) because passing
  // onEntrypointLoaded prevents the loader from forwarding it.
  var engineConfig = {
    // Set true if you cannot provide COOP/COEP headers (breaks cross-origin
    // iframes otherwise); costs some wasm performance.
    forceSingleThreadedSkwasm: true,
  };

  var loader = document.getElementById('app-loading');
  if (!loader) {
    loader = document.createElement('div');
    loader.id = 'app-loading';
    loader.setAttribute('role', 'status');
    loader.setAttribute('aria-live', 'polite');
    loader.textContent = 'Loading…';
    document.body.appendChild(loader);
  }

  _flutter.loader.load({
    config: engineConfig,
    onEntrypointLoaded: async function (engineInitializer) {
      loader.textContent = 'Preparing…';
      var appRunner = await engineInitializer.initializeEngine(engineConfig);
      loader.textContent = 'Starting…';
      await appRunner.runApp();
      loader.remove();
    },
  });
})();

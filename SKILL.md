---
name: flutter-web-native
description: >-
  Eliminates the clunky "canvas / video game" feel of Flutter Web applications and transforms
  them into fluid, native-feeling desktop and mobile web experiences. Fixes blurry rendering,
  stepped mouse-wheel jumps, mobile teardrop selection pins, mouse-drag panning that breaks text
  selection, broken right-click menus, viewport zoom lockouts, missing cursors, and background-tab
  waste. Covers WebAssembly/Skwasm deployment, CanvasKit memory limits, performance measurement
  (Lighthouse on canvas apps, headless CDP probes, A/B method), raster cost on single-threaded
  Skwasm, the boot critical path (Firebase SDK chains, eager plugin wasm, fonts, preloads),
  delivery/caching/Lighthouse hygiene, DOM semantics + accessibility, keyboard focus/shortcuts,
  PWA/offline, RTL/Arabic web chrome, cross-tab sync, web testing, and the browser APIs Flutter
  does not wrap.
---

# Flutter Web Native Fidelity — «تجربة الويب الأصلية»

You are the **Lead Web Platform Engineer for Flutter**: you make Flutter Web apps match the ergonomic, visual, and behavioral fidelity of world-class desktop web apps (Figma, Linear, Notion, GitHub) instead of feeling like a canvas running a mobile app.

By default Flutter Web treats the browser as a foreign rendering surface: it suppresses native text selection, snaps the wheel across discrete ticks, draws mobile teardrop handles under a mouse, eats right-clicks, and hides behind a blank canvas. This skill is the engineering playbook to remove all of that, plus the platform work around it (Wasm, boot critical path, raster cost, measurement, caching, a11y, lifecycle, testing).

> **Ground truth.** This edition targets **Flutter 3.29+ (verified on 3.47)**. Several widely-copied tips are now obsolete — see [Reality checks](#reality-checks-flutter-329) before applying anything. When in doubt, read the framework/engine source, not a blog post.

---

## Files in this Skill

### Interaction fidelity
- `references/viewport-and-css.md` — DPR/canvas buffer, engine-injected viewport, `visualViewport` zoom, `touch-action` tradeoffs, safe areas.
- `references/scroll-architecture.md` — app-wide page-level wheel shim (default) vs per-view smoothing, excluding mouse from `dragDevices`, clamping physics, safe scrollbar theming.
- `references/text-selection.md` — `SelectionArea`, `desktopTextSelectionHandleControls`, `SelectionContainer.disabled`, brand `textSelectionTheme`, native right-click.
- `references/trackpad-and-zoom.md` — trackpad pan/zoom and Ctrl/Cmd-wheel focal zoom for canvas stages.
- `references/cursor-and-hover.md` — system cursors, desktop tooltips, WCAG focus rings.
- `references/navigation-and-urls.md` — `PathUrlStrategy`, SPA rewrites, `Link` anchors for middle-click, document titles.
- `references/forms-and-autofill.md` — `AutofillGroup`, `finishAutofillContext`, keyboard submission.

### Platform & performance
- `references/performance-measurement.md` — reading Lighthouse on a canvas app, SwiftShader headless rig, GPU-independent metrics (ms/frame, LoAF, TTFF), A/B method, worker network, profile builds.
- `references/raster-performance.md` — single-threaded Skwasm, no web raster cache, ambient-animation cost, `toImageSync` texture caching, warm-up/scroll/media pauses.
- `references/wasm-canvaskit-html.md` — renderers and who actually gets Skwasm, threading/COOP/COEP, image memory, fonts.
- `references/loading-and-bootstrap.md` — `flutter_bootstrap.js`, boot critical path (Firebase SDK, plugin wasm, fonts), preloads that mirror flutter.js, caching, compression, Lighthouse hygiene, service-worker reality.
- `references/web-workers-and-isolates.md` — isolates don't exist on web, chunking/yielding, raw Web Worker interop.
- `references/web-lifecycle-and-multitab.md` — `visibilitychange`, pausing background work, `BroadcastChannel`/`storage` sync.
- `references/pwa-and-offline.md` — manifest, bring-your-own service worker, offline handling.
- `references/native-web-apis.md` — share, web push, fullscreen, install prompt, print, analytics page views, CSP/security headers.

### Content, a11y & i18n
- `references/seo-and-semantics.md` — semantics DOM (off by default), why semantics ≠ SEO, server-side meta, JSON-LD.
- `references/accessibility-and-keyboard.md` — `ensureSemantics`, focus traversal, shortcut parity, reduced motion.
- `references/rtl-and-arabic-web.md` — `lang`/`dir`, Arabic font bundling vs gstatic FOUT, iOS-PWA safe areas, browser chrome color.
- `references/os-integration-clipboard-dnd.md` — OS file drops (`desktop_drop`), rich clipboard (`super_clipboard`).
- `references/web-testing.md` — pointer-aware widget tests, `flutter drive` in Chrome, golden gotchas, real-browser checks.

### Drop-in assets & automation
- `examples/smooth_wheel_shim.js` — app-wide page-level wheel easing shim (recommended default).
- `examples/smooth_wheel_scroll.dart` — per-view time-based coalescing wheel scroller (stands down when the shim is active).
- `examples/smooth_scroll_controller.dart` — simpler `ScrollController` smoother (mouse-friendly; not trackpad-optimal).
- `examples/native_web_scroll_behavior.dart` — `ScrollBehavior` with mouse excluded.
- `examples/app_text_selection.dart` — platform-aware desktop selection handles.
- `examples/native_web_app_shell.dart` — shell with chrome selection shielding.
- `examples/canvas_zoom_stage.dart` — focal zoom/pan stage.
- `examples/flutter_bootstrap.js` — loading UI, `flutter-first-frame` splash removal, correct loader vs engine config.
- `examples/index.html` — reference host document (metadata-only head, entry preloads, sized LCP splash).
- `scripts/audit_web_fidelity.sh` — portable CLI scanner (comment-aware), incl. boot/delivery checks.
- `scripts/perf_probe.py` — CDP probe: TTFF, idle/scroll ms per frame, busy %, LoAF, worker-aware transfer, CPU throttling, reduced motion, repeated runs.
- `scripts/prod_serve.py` — prod-like static server (br/gzip, hashed-immutable caching, SPA fallback, optional COOP/COEP) for A/B builds.
- `scripts/install.sh` — installer for agent skill directories.

---

## The 12 Pillars of Native Web Fidelity

### 1. Host document & CSS
- **NEVER** lock zoom (`user-scalable=no` / `maximum-scale=1`). The engine injects `width=device-width, initial-scale=1.0, maximum-scale=5.0` and strips your tag; a locking tag only fails a11y audits.
- **NEVER** set `width`/`height` on `flutter-view canvas` — it breaks the DPR buffer (blur + offset hit-testing).
- **Set `lang`/`dir`** on `<html>` (the engine sets `lang` from locale but never `dir`).
- Add `theme-color` and a manifest for first paint / installability.

### 2. Text selection & browser menus
- Pass `selectionControls: desktopTextSelectionHandleControls` on web/desktop (see `examples/app_text_selection.dart`).
- **Exclude `PointerDeviceKind.mouse`** from `dragDevices` so mouse-drag selects text instead of panning.
- Wrap nav rails/toolbars/buttons in `SelectionContainer.disabled`.
- Call `BrowserContextMenu.enableContextMenu()` and make sure `index.html` has **no** blanket `contextmenu` `preventDefault`.
- Set a brand `textSelectionTheme` (highlight + handle colors).

### 3. Scroll feel
- There is **no framework wheel-smoothing hook**. App-wide default: the page-level JS shim (`examples/smooth_wheel_shim.js`) that eases trusted mouse-wheel notches below the engine. Per-view alternative: `examples/smooth_wheel_scroll.dart` — which must stand down via the page flag, not by `PointerDeviceKind` (the shim's slices carry the notch's `wheelDelta`, so they are mouse-kind like a real notch).
- Use `ClampingScrollPhysics` on desktop/web; no rubber-band.
- Never make `Scrollbar` globally `interactive`/`thumbVisibility` via `ThemeData` (assertion crash on controller-less scrollables).

### 4. Trackpad & wheel zoom
- Handle `PointerPanZoomUpdateEvent` and `PointerScrollEvent` with Ctrl/Meta; scale exponentially from the focal point (see `canvas_zoom_stage.dart`).

### 5. Cursors, hover & forms
- Any interactive element gets `SystemMouseCursors.click`; text fields get `SystemMouseCursors.text`.
- Desktop tooltips appear on hover (~400ms), not only long-press.
- `AutofillGroup` + `TextInput.finishAutofillContext()` for login/signup.

### 6. URLs & navigation
- `usePathUrlStrategy()`/`setUrlStrategy(PathUrlStrategy())`; host must rewrite unknown paths to `index.html`.
- Use `url_launcher`'s `Link` for real `<a href>` (middle-click / open-in-new-tab).
- Keep the document title in sync per route (`Title`/`onGenerateTitle` or `document.title`).

### 7. OS integration
- `desktop_drop` for OS file drops; `super_clipboard` for image/rich paste. Flutter's `Clipboard` is text-only.

### 8. Memory, rendering & raster cost
- `Image.network(..., cacheWidth:)` to bound decoded bitmaps; bound/evict `PaintingBinding.instance.imageCache` on heavy routes. Aggressive `clear()` everywhere hurts hit rates — evict where it matters.
- Default build is dart2js + CanvasKit; `--wasm` uses Skwasm **only on Blink by default** (see `wasm-canvaskit-html.md`).
- Without COOP/COEP, Skwasm is **single-threaded**, and the web has **no picture raster cache**: any animating pixel replays the whole scene on the UI thread. Budget every always-on ambient animation as a full-scene render per frame; texture-cache rigid vector motion with `toImageSync`; hold decoration still during boot warm-up, scroll and playback (`raster-performance.md`).

### 9. Concurrency
- Never block the main thread >16ms. Chunk work and `await Future.delayed(Duration.zero)`.
- **On web, `Isolate.run`/`Isolate.spawn` throw `UnsupportedError`** and `compute()` runs on the main thread. Real parallelism = a JS Web Worker (or a server).

### 10. Lifecycle, multi-tab & offline
- `didChangeAppLifecycleState` maps from `visibilitychange`/`focus`/`blur`; pause media, polling, and animations on hidden/inactive — hidden tabs keep firing Timers.
- Sync auth/session/cart across tabs with `BroadcastChannel` (or `storage` events).
- Handle connectivity with a graceful banner, not raw socket errors.

### 11. Boot critical path & delivery
- Nothing `main()` awaits before `runApp` may start its network only once Dart runs: modulepreload the Firebase JS SDK bundles **on Blink only** (version + services generated from the resolved packages; WebKit must keep FlutterFire's serial load order), or defer init past the first frame.
- Ship a first-frame watchdog: once the binaries have downloaded, a boot that never paints within ~30 s of visible time recovers (purge + reload once) instead of leaving an endless splash.
- No plugin wasm on the first screen that it doesn't use (e.g. don't call `pdfrxFlutterInitialize()` at boot on web).
- Entry preloads mirror flutter.js renderer selection and fetch modes; trim `FontManifest.json` for web; only `<link>/<style>/<script>` injected into `<head>`.
- Content-hash entrypoints for immutable caching; compress function-rendered HTML; sized `fetchpriority="high"` splash; no dangling `sourceMappingURL`; standard robots.txt; real `/.well-known/*` files or 404 (`loading-and-bootstrap.md`).

### 12. Measure, don't guess
- Lighthouse LCP on a canvas app is the HTML splash; TBT (wasm instantiate + first build) and Speed Index (never-settling animation) are the real costs. 100 is not reachable.
- In headless SwiftShader, rAF fps is meaningless: decide with main-thread ms per frame, busy % and LoAF blocking; TTFF from `flutter-first-frame`.
- Baseline from a worktree, both builds served brotli with prod cache headers, runs sequential and repeated (`performance-measurement.md`, `scripts/perf_probe.py`, `scripts/prod_serve.py`).

---

## Reality checks (Flutter 3.29+, verified on 3.47)

Copied advice that is now wrong:

| Outdated claim | Current reality |
| --- | --- |
| "Choose the HTML renderer for small apps." | HTML renderer **removed**; `--web-renderer` **removed** (3.29). Default is dart2js + CanvasKit; `--wasm` = Skwasm. |
| "Flutter generates and manages a service worker." | Flutter **no longer** does. Bring your own (Workbox) or none. |
| "Set `debugSemanticsDisableAnimations = true` to enable semantics." | Wrong API. Use `SemanticsBinding.instance.ensureSemantics()`. Web semantics is off by default. |
| "`dom semantics` is enough for SEO." | No. Flutter's own guidance: use server-rendered/HTML content or Jaspr for indexable pages. |
| "Make wheel scrolling smooth app-wide in `ScrollBehavior`." | No such hook exists; wheel and trackpad share one raw `pointerScroll` path. Ease below the engine with a page-level JS shim, or per view. |
| "Detect a JS wheel shim by filtering `PointerDeviceKind.mouse`." | The engine classifies the shim's synthetic events as `trackpad` (`pointer_binding.dart`, `_isTrackpadEvent`). Read the page flag via `dart:js_interop`. |
| "`--wasm` gives every WasmGC browser Skwasm." | Default `wasmAllowList` is Blink-only; Firefox/Safari get dart2js + CanvasKit (`flutter_js/src/browser_environment.js`). |
| "Set `forceSingleThreadedSkwasm` if you can't send COOP/COEP." | Skwasm already falls back to single-threaded without cross-origin isolation (`skwasm_loader.js`); use `suppressMultithreadingWarning` to silence the warning. |
| "`RepaintBoundary` isolates an animation's cost." | Not on web: there is no picture raster cache; every frame replays every picture (`layer/layer_tree.dart`). |
| "Isolates map to Web Workers on web." | `Isolate.spawn`/`run` throw `UnsupportedError` on dart2js and dart2wasm; `compute()` runs on the main thread. |
| "`<link rel="modulepreload" href="main.dart.js">`." | `main.dart.js` is a classic script; preload it `as="script"` (no crossorigin). Wasm path: modulepreload `.mjs`, `preload as=fetch crossorigin` for `.wasm`. |
| "Lighthouse LCP is green, so load is fast." | LCP is the HTML splash; the canvas isn't an LCP candidate. Read TBT/TTI/SI. |
| "Headless fps shows the speed-up." | SwiftShader is CPU raster: ~8 fps for everything. Use ms/frame and LoAF. |
| "Set `touch-action: pan-x pan-y pinch-zoom` on `flutter-view`." | That re-grants browser panning and fights Flutter. Opt into `pinch-zoom` only, if at all. |
| "`Link` is a Flutter framework widget." | It is from `url_launcher` and renders an `<a>` on web. |

---

## When NOT to apply (deliberate tradeoffs)

Native-fidelity is a goal, not a religion. Do **not**:
- Enable `BrowserContextMenu` on flows that intentionally protect content, or where a custom right-click menu exists.
- Grant browser `pinch-zoom` on screens with an in-app pinch surface (PDF reader, `InteractiveViewer`) — it steals the gesture.
- Force `ensureSemantics()` on every device; it costs work. Scope it to a11y/crawl-critical routes.
- Call `imageCache.clear()` on every navigation; prefer bounded caches + targeted eviction.
- Add smoothing to macOS trackpads that already deliver inertial deltas unless you gate to `PointerDeviceKind.mouse`.
- Rewrite a working platform-specific behavior (e.g. a shipped `SmoothWheelScroller`) just to match this skill. Compose with what exists.
- Disable motion because the viewport is small. Gate decorative animation on reduced-motion / user preference; schedule it around boot, scroll and playback instead.
- Promise a Lighthouse Performance score of 100 for a canvas app. Set expectations on TBT honestly.

---

## Audit & Implementation Workflow

1. **Run the audit**: `./scripts/audit_web_fidelity.sh [project]` (add `--strict` in CI). It is comment-aware and detects multiline `dragDevices`.
2. **Host document**: viewport zoom, `lang`/`dir`, `theme-color`, manifest, no canvas CSS overrides, loading UI.
3. **Interaction**: exclude mouse from `dragDevices`; desktop selection handles + `SelectionContainer.disabled`; brand `textSelectionTheme`; native context menu.
4. **Scroll/zoom**: coalescing wheel scroller; focal Ctrl/Cmd zoom where a canvas exists.
5. **Platform**: `PathUrlStrategy` + SPA rewrites; `Link` anchors; title sync; cache headers; deliberate service worker.
6. **Resilience**: lifecycle pause, offline state, cross-tab sync, image-cache bounds.
7. **Performance**: baseline first (`perf_probe.py` against a worktree build served by `prod_serve.py`); then boot critical path (Firebase preloads, plugin wasm, fonts, preloads) and raster cost (ambient animation, texture caching, scroll/media pauses); re-measure with repeated sequential runs.
8. **Verify**: `flutter analyze`, targeted tests, then a real-browser pass (see `references/web-testing.md`).
9. **Build**: `flutter build web` (and `--wasm`). Check the fallback build is emitted; use `--profile --wasm` (or `--no-strip-wasm`) when you need readable CPU profiles.

---

## Verification checklist

- [ ] `flutter analyze` clean and relevant tests pass.
- [ ] Mouse drag selects text; wheel scrolls; none of it pans by accident.
- [ ] Right-click menu behavior is intentional and documented.
- [ ] Deep link, Back/Forward, and title update correctly.
- [ ] Narrow phone / desktop / browser zoom 125–200% / dark mode / RTL all checked.
- [ ] No long tasks >50ms on the hot path in a DevTools performance trace.
- [ ] Background tab stops media/polling/animations.
- [ ] Idle page schedules no frames; ambient animation held during boot warm-up, scroll and playback (web).
- [ ] TTFF, idle/scroll ms per frame and LoAF blocking not regressed vs a worktree baseline (median of ≥3 sequential runs).
- [ ] No serial third-party chain before first frame (Firebase preloads match the resolved SDK version); no unused plugin wasm at boot.
- [ ] Lighthouse hygiene: compressed HTML, sized `fetchpriority="high"` splash, no dangling source maps, standard robots.txt, `/.well-known/*` not answered by the SPA shell.

---

## Sources

- Flutter web initialization: https://docs.flutter.dev/platform-integration/web/initialization
- WebAssembly: https://docs.flutter.dev/platform-integration/web/wasm
- Web FAQ (service workers, SEO, renderers): https://docs.flutter.dev/platform-integration/web/faq
- Web accessibility: https://docs.flutter.dev/ui/accessibility/web-accessibility
- Integration testing on web: https://docs.flutter.dev/testing/integration-tests
- Web performance profiling: https://docs.flutter.dev/perf/web-performance
- Long Animation Frames API: https://developer.chrome.com/docs/web-platform/long-animation-frames
- Chrome DevTools Protocol: https://chromedevtools.github.io/devtools-protocol/
- Engine sources cited above: `engine/src/flutter/lib/web_ui/` (engine) and `engine/src/flutter/lib/web_ui/flutter_js/src/` (loader) in the Flutter SDK checkout.

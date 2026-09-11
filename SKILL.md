---
name: flutter-web-native
description: >-
  Eliminates the clunky "canvas / video game" feel of Flutter Web applications and transforms
  them into fluid, native-feeling desktop and mobile web experiences. Fixes blurry rendering,
  stepped mouse-wheel jumps, mobile teardrop selection pins, mouse-drag panning that breaks text
  selection, broken right-click menus, viewport zoom lockouts, missing cursors, and background-tab
  waste. Covers WebAssembly/Skwasm deployment, CanvasKit memory limits, bootstrap/loading UX,
  caching headers, DOM semantics + accessibility, keyboard focus/shortcuts, PWA/offline, RTL/Arabic
  web chrome, cross-tab sync, web testing, and the browser APIs Flutter does not wrap.
---

# Flutter Web Native Fidelity — «تجربة الويب الأصلية»

You are the **Lead Web Platform Engineer for Flutter**: you make Flutter Web apps match the ergonomic, visual, and behavioral fidelity of world-class desktop web apps (Figma, Linear, Notion, GitHub) instead of feeling like a canvas running a mobile app.

By default Flutter Web treats the browser as a foreign rendering surface: it suppresses native text selection, snaps the wheel across discrete ticks, draws mobile teardrop handles under a mouse, eats right-clicks, and hides behind a blank canvas. This skill is the engineering playbook to remove all of that, plus the platform work around it (Wasm, caching, a11y, lifecycle, testing).

> **Ground truth.** This edition targets **Flutter 3.29+ (verified on 3.47)**. Several widely-copied tips are now obsolete — see [Reality checks](#reality-checks-flutter-329) before applying anything. When in doubt, read the framework/engine source, not a blog post.

---

## Files in this Skill

### Interaction fidelity
- `references/viewport-and-css.md` — DPR/canvas buffer, engine-injected viewport, `visualViewport` zoom, `touch-action` tradeoffs, safe areas.
- `references/scroll-architecture.md` — smooth wheel/trackpad scrolling, excluding mouse from `dragDevices`, clamping physics, safe scrollbar theming.
- `references/text-selection.md` — `SelectionArea`, `desktopTextSelectionHandleControls`, `SelectionContainer.disabled`, brand `textSelectionTheme`, native right-click.
- `references/trackpad-and-zoom.md` — trackpad pan/zoom and Ctrl/Cmd-wheel focal zoom for canvas stages.
- `references/cursor-and-hover.md` — system cursors, desktop tooltips, WCAG focus rings.
- `references/navigation-and-urls.md` — `PathUrlStrategy`, SPA rewrites, `Link` anchors for middle-click, document titles.
- `references/forms-and-autofill.md` — `AutofillGroup`, `finishAutofillContext`, keyboard submission.

### Platform & performance
- `references/wasm-canvaskit-html.md` — current renderers, `--wasm`/Skwasm, COOP/COEP, CanvasKit memory and image caching.
- `references/loading-and-bootstrap.md` — `flutter_bootstrap.js`, loading UI, cache headers, service-worker reality.
- `references/web-workers-and-isolates.md` — offloading work, event-loop yielding, raw Web Worker interop.
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
- `examples/smooth_wheel_scroll.dart` — recommended time-based coalescing wheel scroller (drop-in widget).
- `examples/smooth_scroll_controller.dart` — simpler `ScrollController` smoother (mouse-friendly; not trackpad-optimal).
- `examples/native_web_scroll_behavior.dart` — `ScrollBehavior` with mouse excluded.
- `examples/app_text_selection.dart` — platform-aware desktop selection handles.
- `examples/native_web_app_shell.dart` — shell with chrome selection shielding.
- `examples/canvas_zoom_stage.dart` — focal zoom/pan stage.
- `examples/flutter_bootstrap.js` — loading UI + correct `initializeEngine(config)` wiring.
- `examples/index.html` — reference host document.
- `scripts/audit_web_fidelity.sh` — portable CLI scanner (comment-aware, cross-validated).
- `scripts/install.sh` — installer for agent skill directories.

---

## The 10 Pillars of Native Web Fidelity

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
- There is **no global wheel-smoothing hook**; use a per-view coalescing scroller (`examples/smooth_wheel_scroll.dart`).
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

### 8. Memory & rendering
- `Image.network(..., cacheWidth:)` to bound decoded bitmaps; bound/evict `PaintingBinding.instance.imageCache` on heavy routes. Aggressive `clear()` everywhere hurts hit rates — evict where it matters.
- Default build is dart2js + CanvasKit; `--wasm` uses Skwasm (see `wasm-canvaskit-html.md` for COOP/COEP and browser limits).

### 9. Concurrency
- Never block the main thread >16ms. Chunk work and `await Future.delayed(Duration.zero)`, or use `Isolate.run`/`compute`.
- **On web**, isolates map to Web Workers with real startup cost — only for genuinely large work; not for tiny tasks.

### 10. Lifecycle, multi-tab & offline
- `didChangeAppLifecycleState` maps from `visibilitychange`/`focus`/`blur`; pause media, polling, and animations on hidden/inactive — hidden tabs keep firing Timers.
- Sync auth/session/cart across tabs with `BroadcastChannel` (or `storage` events).
- Handle connectivity with a graceful banner, not raw socket errors.

---

## Reality checks (Flutter 3.29+)

Copied advice that is now wrong:

| Outdated claim | Current reality |
| --- | --- |
| "Choose the HTML renderer for small apps." | HTML renderer **removed**; `--web-renderer` **removed** (3.29). Default is dart2js + CanvasKit; `--wasm` = Skwasm. |
| "Flutter generates and manages a service worker." | Flutter **no longer** does. Bring your own (Workbox) or none. |
| "Set `debugSemanticsDisableAnimations = true` to enable semantics." | Wrong API. Use `SemanticsBinding.instance.ensureSemantics()`. Web semantics is off by default. |
| "`dom semantics` is enough for SEO." | No. Flutter's own guidance: use server-rendered/HTML content or Jaspr for indexable pages. |
| "Make wheel scrolling smooth app-wide in `ScrollBehavior`." | No such hook exists; wheel and trackpad share one raw `pointerScroll` path. Intercept per view. |
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

---

## Audit & Implementation Workflow

1. **Run the audit**: `./scripts/audit_web_fidelity.sh [project]` (add `--strict` in CI). It is comment-aware and detects multiline `dragDevices`.
2. **Host document**: viewport zoom, `lang`/`dir`, `theme-color`, manifest, no canvas CSS overrides, loading UI.
3. **Interaction**: exclude mouse from `dragDevices`; desktop selection handles + `SelectionContainer.disabled`; brand `textSelectionTheme`; native context menu.
4. **Scroll/zoom**: coalescing wheel scroller; focal Ctrl/Cmd zoom where a canvas exists.
5. **Platform**: `PathUrlStrategy` + SPA rewrites; `Link` anchors; title sync; cache headers; deliberate service worker.
6. **Resilience**: lifecycle pause, offline state, cross-tab sync, image-cache bounds.
7. **Verify**: `flutter analyze`, targeted tests, then a real-browser pass (see `references/web-testing.md`).
8. **Build**: `flutter build web` (and `--wasm` if you can meet COOP/COEP/browser requirements). Check the fallback build is emitted.

---

## Verification checklist

- [ ] `flutter analyze` clean and relevant tests pass.
- [ ] Mouse drag selects text; wheel scrolls; none of it pans by accident.
- [ ] Right-click menu behavior is intentional and documented.
- [ ] Deep link, Back/Forward, and title update correctly.
- [ ] Narrow phone / desktop / browser zoom 125–200% / dark mode / RTL all checked.
- [ ] No long tasks >50ms on the hot path in a DevTools performance trace.
- [ ] Background tab stops media/polling/animations.

---

## Sources

- Flutter web initialization: https://docs.flutter.dev/platform-integration/web/initialization
- WebAssembly: https://docs.flutter.dev/platform-integration/web/wasm
- Web FAQ (service workers, SEO, renderers): https://docs.flutter.dev/platform-integration/web/faq
- Web accessibility: https://docs.flutter.dev/ui/accessibility/web-accessibility
- Integration testing on web: https://docs.flutter.dev/testing/integration-tests
- Web performance profiling: https://docs.flutter.dev/perf/web-performance

---
name: flutter-web-native
description: >-
  Eliminates the clunky "canvas / video game" feel of Flutter Web applications and transforms
  them into fluid, native-feeling desktop and mobile web experiences. Solves blurry rendering,
  stepped mouse wheel jumps, mobile teardrop pins, drag-panning conflicts with text selection,
  broken browser right-click menus, viewport zoom lockouts, trackpad pinch-zoom, and missing mouse cursors.
  Includes 100X depth advanced WebAssembly, CanvasKit memory management, SEO semantics, 
  Drag & Drop OS integration, Web Worker concurrency, multi-tab sync, and PWA capabilities.
---

# Flutter Web Native Fidelity — «تجربة الويب الأصلية»

You are the **Lead Web Platform Engineer for Flutter**: a specialist who ensures Flutter Web applications match the ergonomic, visual, and behavioral fidelity of world-class desktop web applications (like Figma, Linear, Notion, and GitHub).

By default, Flutter Web treats the browser as a foreign rendering canvas. It disables browser text selection, jumps discretely across fixed wheel ticks, renders mobile teardrop pins, eats right-clicks, and locks visual viewport zooming. This skill provides the definitive engineering playbook and production code to eliminate these flaws completely, alongside deep-dive architecture for memory management, concurrency, and OS integration.

---

## Files in this Skill

### UI & Interaction Fidelity
- `references/viewport-and-css.md` — Canvas DPR buffer calculations, visual viewport zooming, fixing Retina blurriness, `touch-action`.
- `references/scroll-architecture.md` — `SmoothScrollController`, `SmoothScrollPosition`, removing `mouse` from `dragDevices`.
- `references/text-selection.md` — `SelectionArea`, `desktopTextSelectionHandleControls`, chrome shielding, `BrowserContextMenu`.
- `references/trackpad-and-zoom.md` — Trackpad pan/zoom, `PointerScrollEvent` with Ctrl/Cmd modifier, canvas stage zooming.
- `references/cursor-and-hover.md` — System mouse cursors, desktop tooltips, WCAG focus indicators.
- `references/navigation-and-urls.md` — `usePathUrlStrategy()`, middle-click "open in new tab", document title synchronization.

### 100X Depth: Advanced Web Architecture
- `references/wasm-canvaskit-html.md` — Renderers, WebAssembly GC, initial load optimizations, ImageCache memory leaks.
- `references/os-integration-clipboard-dnd.md` — File Drag-and-drop (`desktop_drop`), rich clipboard images (`super_clipboard`), HTML injection for right-click.
- `references/web-workers-and-isolates.md` — Offloading UI-blocking tasks, Dart Isolates on Web, raw JavaScript web worker interop.
- `references/seo-and-semantics.md` — DOM Semantics Tree, screen readers, server-side meta tag injection, OpenGraph.
- `references/pwa-and-offline.md` — Manifests, Service Workers, network offline handling, background sync.
- `references/state-sync-multi-tab.md` — `BroadcastChannel` API, `localStorage` events, syncing auth and cart state across tabs.
- `references/forms-and-autofill.md` — Password manager `AutofillGroup`, Grammarly extension shielding, OS-level keyboard shortcut binding.

### Drop-in Assets & Automation
- `examples/smooth_scroll_controller.dart` — Drop-in production smooth scroll controller.
- `examples/native_web_scroll_behavior.dart` — Drop-in web scroll behavior preserving text selection.
- `examples/native_web_app_shell.dart` — Drop-in web shell with chrome selection shielding.
- `examples/canvas_zoom_stage.dart` — Drop-in interactive zoomable/pannable stage.
- `examples/index.html` — Reference `web/index.html` template.
- `scripts/audit_web_fidelity.sh` — Automated CLI scanner for detecting Flutter web anti-patterns.
- `scripts/install.sh` — Skill installer for AI agent environments.

---

## The 10 Pillars of Native Web Fidelity

### 1. The HTML/CSS Engine Layer
- **NEVER** apply CSS width or height overrides to `flutter-view canvas`.
- **ALWAYS** set `touch-action: pan-x pan-y pinch-zoom;` on `<flutter-view>`.

### 2. Text Selection & Handle Controls
- **ALWAYS** pass `selectionControls: desktopTextSelectionHandleControls` to `SelectionArea`.
- **ALWAYS** wrap navigation rails, toolbars, and buttons in `SelectionContainer.disabled`.
- **ALWAYS** enable native browser right-click menus via `BrowserContextMenu.enableContextMenu()`.

### 3. Scroll Momentum & Physics
- **NEVER** include `PointerDeviceKind.mouse` in `ScrollBehavior.dragDevices`.
- **ALWAYS** use `SmoothScrollController` / `SmoothScrollPosition` for discrete wheel inputs.
- **ALWAYS** use `ClampingScrollPhysics` on desktop web.

### 4. Trackpad & Wheel Zooming
- Handle `PointerPanZoomUpdateEvent` and `PointerScrollEvent` with Ctrl/Meta pressed.
- Scale transformations exponentially from the pointer's focal position.

### 5. Cursors, Hover & Forms
- Any interactive element must display `SystemMouseCursors.click`.
- Use `AutofillGroup` for login/signup forms and always call `TextInput.finishAutofillContext()`.

### 6. URLs & Navigation
- Enable path routing via `usePathUrlStrategy()`. Use `Link` widget for real `<a>` tags.
- Update `SystemChrome.setApplicationSwitcherDescription` with the active route title.

### 7. OS Integration: Drag, Drop, Clipboard
- Use `desktop_drop` to pipe OS-level file drops onto the canvas.
- Use `super_clipboard` to read raw image bytes pasted via Cmd+V.

### 8. Memory Management & Wasm
- Target WebAssembly GC (`--wasm`) for maximum performance and garbage collection sharing.
- Aggressively call `PaintingBinding.instance.imageCache.clear()` on CanvasKit when navigating away from heavy image views to prevent browser OOM crashes.

### 9. Concurrency & Event Loop Yielding
- Never block the main JavaScript thread for >16ms. 
- Yield heavy map/loops with `await Future.delayed(Duration.zero)` or use `Isolate.run` (Web Workers).

### 10. Multi-Tab State & Offline
- Use `BroadcastChannel` from `package:web` to instantly sync Auth and Cart state across multiple tabs.
- Hook into `Connectivity().onConnectivityChanged` to gracefully disable inputs when offline.

---

## Audit & Implementation Workflow

1. **Run the Audit**: `./scripts/audit_web_fidelity.sh [project_path]`
2. **Inspect Core Web Configurations**: Fix `index.html`, memory cache clearing, and URL paths.
3. **Audit Theme & Selection**: Add `textSelectionTheme`, `BrowserContextMenu`, and selection shielding.
4. **Configure Scroll Behavior**: Install `NativeWebScrollBehavior` and `SmoothScrollController`.
5. **Verify Advanced Capabilities**: Check drag-and-drop, autofill contexts, tab syncing, and Isolate usage.
6. **Build**: Run `flutter build web --wasm` to ensure compatibility.

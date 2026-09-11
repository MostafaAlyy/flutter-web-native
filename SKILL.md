---
name: flutter-web-native
description: >-
  Eliminates the clunky "canvas / video game" feel of Flutter Web applications and transforms
  them into fluid, native-feeling desktop and mobile web experiences. Solves blurry rendering,
  stepped mouse wheel jumps, mobile teardrop pins, drag-panning conflicts with text selection,
  broken browser right-click menus, viewport zoom lockouts, trackpad pinch-zoom, and missing mouse cursors.
---

# Flutter Web Native Fidelity — «تجربة الويب الأصلية»

You are the **Lead Web Platform Engineer for Flutter**: a specialist who ensures Flutter Web applications match the ergonomic, visual, and behavioral fidelity of world-class desktop web applications (like Figma, Linear, Notion, and GitHub).

By default, Flutter Web treats the browser as a foreign rendering canvas. It disables browser text selection, jumps discretely across fixed wheel ticks, renders mobile teardrop pins, eats right-clicks, and locks visual viewport zooming. This skill provides the definitive engineering playbook and production code to eliminate these flaws completely.

---

## Files in this Skill

- `references/viewport-and-css.md` — Canvas DPR buffer calculations, visual viewport zooming, fixing Retina blurriness, `touch-action`, removing body overflow locks.
- `references/scroll-architecture.md` — `SmoothScrollController`, `SmoothScrollPosition`, removing `mouse` from `dragDevices`, `ClampingScrollPhysics`, avoiding scrollbar assertion crashes.
- `references/text-selection.md` — `SelectionArea`, `desktopTextSelectionHandleControls`, `SelectionContainer.disabled` chrome shielding, `BrowserContextMenu.enableContextMenu()`.
- `references/trackpad-and-zoom.md` — Trackpad pan/zoom (`onPointerPanZoomUpdate`), `PointerScrollEvent` with Ctrl/Cmd modifier, canvas stage zooming, focal-point calculations.
- `references/cursor-and-hover.md` — System mouse cursors (`click`, `move`, `grab`), desktop tooltips, WCAG focus indicators vs mouse click focus.
- `references/navigation-and-urls.md` — `usePathUrlStrategy()`, middle-click "open in new tab" (`Link` widget), document title synchronization.
- `examples/smooth_scroll_controller.dart` — Drop-in production smooth scroll controller.
- `examples/native_web_scroll_behavior.dart` — Drop-in web scroll behavior preserving text selection.
- `examples/native_web_app_shell.dart` — Drop-in web shell with chrome selection shielding.
- `examples/canvas_zoom_stage.dart` — Drop-in interactive zoomable/pannable stage.
- `examples/index.html` — Reference `web/index.html` template.
- `scripts/audit_web_fidelity.sh` — Automated CLI scanner for detecting Flutter web anti-patterns.
- `scripts/install.sh` — Skill installer for AI agent environments.

---

## The 6 Pillars of Native Web Fidelity

### 1. The HTML/CSS Engine Layer (`web/index.html`)
- **NEVER** apply CSS width or height overrides to `flutter-view canvas`. Flutter dynamically computes buffer dimensions via `viewport * DPR`. Overriding canvas dimensions in CSS forces pixel distortion and offsets mouse hit-testing.
- **NEVER** use `maximum-scale=1.0` or `user-scalable=no` in `<meta name="viewport">`.
- **NEVER** put `overflow-x: hidden` or `overflow: hidden` on `html, body`. It freezes browser-level visual viewport panning.
- **ALWAYS** set `touch-action: pan-x pan-y pinch-zoom;` on `<flutter-view>`.

### 2. Text Selection & Handle Controls
- **ALWAYS** pass `selectionControls: desktopTextSelectionHandleControls` to `SelectionArea`. Never allow mobile teardrop pins to appear on desktop web.
- **ALWAYS** wrap navigation rails, top app bars, toolbars, buttons, badges, chips, and table header rows in `SelectionContainer.disabled`. Drag-selecting text must never highlight UI chrome.
- **ALWAYS** enable native browser right-click menus via `BrowserContextMenu.enableContextMenu()` on web startup so users can Copy, Inspect, and Search natively.
- **ALWAYS** theme `textSelectionTheme` with brand colors, matching cursor, and selection handles.

### 3. Scroll Momentum & Physics
- **NEVER** include `PointerDeviceKind.mouse` in `ScrollBehavior.dragDevices`. On the web, dragging a mouse must select text, **not** pan the page like a phone screen.
- **ALWAYS** use `SmoothScrollController` / `SmoothScrollPosition` for discrete wheel inputs, interpolating deltas along `Curves.easeOutCubic` over 180ms while respecting reduced-motion accessibility.
- **ALWAYS** use `ClampingScrollPhysics` on desktop web; avoid bouncy rubber-banding (`BouncingScrollPhysics`).
- **NEVER** set `thumbVisibility: true` or `interactive: true` globally in `ScrollbarThemeData` without attached controllers, as Flutter asserts in debug mode when `PrimaryScrollController` is absent.

### 4. Trackpad & Wheel Zooming
- Handle both:
  1. `PointerPanZoomUpdateEvent` (modern trackpad two-finger pinch).
  2. `PointerScrollEvent` with `HardwareKeyboard.instance.isControlPressed || isMetaPressed` (mouse `Ctrl + Wheel` and browser-synthesized trackpad zoom).
- Use exponential scaling curves: `zoomFactor = math.exp(-deltaY * sensitivity)`.
- Center scale transformations around the pointer's focal position (`event.localPosition`).

### 5. Cursors & Hover States
- Any interactive element (button, custom card, tab, clickable table row, tag) **must** display `SystemMouseCursors.click` via `MouseRegion`.
- Draggable stages must show `SystemMouseCursors.grab` and `SystemMouseCursors.grabbing`.
- Tooltips must appear on hover with ~400ms delay (`TooltipThemeData(waitDuration: Duration(milliseconds: 400))`), not long-press.

### 6. URLs, Navigation & History
- Enable path routing via `usePathUrlStrategy()` (drop `/#/`).
- Use `url_launcher`'s `Link` widget for links to inject real `<a>` tags for middle-click and "Open in new tab".
- Dynamically synchronize document title via `MaterialApp.router(onGenerateTitle: ...)` or `Title` widget.

---

## Audit & Implementation Workflow

When asked to inspect or upgrade a Flutter Web codebase:

1. **Run the Audit**:
   ```bash
   ./scripts/audit_web_fidelity.sh [project_path]
   ```
2. **Inspect `web/index.html`**:
   - Verify viewport meta tag.
   - Clean up any canvas CSS overrides.
   - Add `touch-action` and remove body overflow locks.
3. **Audit Theme & Selection**:
   - Add `textSelectionTheme` to `ThemeData`.
   - Wrap application body in `SelectionArea(selectionControls: desktopTextSelectionHandleControls)`.
   - Shield navigation and action buttons with `SelectionContainer.disabled`.
   - Call `BrowserContextMenu.enableContextMenu()` in `initState` / startup.
4. **Configure Scroll Behavior**:
   - Install `NativeWebScrollBehavior` and pass to `MaterialApp.router(scrollBehavior: ...)`.
   - Adopt `SmoothScrollController` in workbenches, main feeds, and large lists.
5. **Verify with Tests & Web Build**:
   - Run `dart format` and `flutter analyze`.
   - Run existing unit/widget test suites.
   - Run `flutter build web` to ensure zero compilation or Wasm dry-run regressions.

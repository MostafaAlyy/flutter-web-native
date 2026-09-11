# Viewport, CSS & Canvas Engine Architecture

Flutter Web renders its UI using either **Skwasm** (WebAssembly), **CanvasKit** (WebGL/Skia), or the legacy HTML renderer. Regardless of the engine, the fundamental boundary between the browser DOM and Flutter's rendering pipeline is the `<flutter-view>` host element and its nested `<canvas>`.

Misconfiguring this DOM layer is the #1 reason Flutter web apps feel like blurry, un-zoomable video games rather than native web applications.

---

## 1. The Canvas Blurriness & Coordinate Offset Bug

### The Anti-Pattern
Many developers attempt to make Flutter fill the screen by writing:

```css
/* ❌ DO NOT DO THIS */
flutter-view canvas {
  width: 100vw !important;
  min-width: 100% !important;
  height: 100vh !important;
}
```

### Why It Breaks Native Web Fidelity
1. **Dynamic Device Pixel Ratio (DPR)**: Flutter Web dynamically computes its rendering buffer dimensions as:
   $$\text{canvas.width} = \text{viewport.width} \times \text{devicePixelRatio}$$
   $$\text{canvas.height} = \text{viewport.height} \times \text{devicePixelRatio}$$
   When CSS forces `width: 100vw; height: 100vh;` on the `<canvas>` tag, the browser forcefully stretches or squashes Flutter's internal pixel buffer.
2. **Visual Blurriness**: On Retina / HiDPI screens (e.g. DPR 1.5, 2.0, or browser zoom 125%), text and crisp vector strokes become noticeably fuzzy and smeared.
3. **Hit-Testing Coordinates Shift**: The browser's physical mouse event coordinates diverge from Flutter's internal logical coordinates. Taps, clicks, and mouse hovers register several pixels off-target, especially near viewport edges.

### The Native Fix
Let Flutter manage the `<canvas>` sizing entirely. Confine CSS layout rules strictly to the host `<flutter-view>` element:

```css
/* ✅ CORRECT */
html, body {
  margin: 0;
  padding: 0;
  width: 100%;
  height: 100%;
}

flutter-view {
  width: 100%;
  height: 100%;
  touch-action: pan-x pan-y pinch-zoom;
}
```

---

## 2. Browser Visual Viewport Pinch-to-Zoom

Web users on mobile and trackpad-equipped laptops expect to pinch-to-zoom into any page to read small text or inspect details.

### Viewport Meta Tag Configuration
Never lock out zoom in `<meta name="viewport">`:

```html
<!-- ❌ ANTI-PATTERN: Disables accessibility zoom -->
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">

<!-- ✅ CORRECT: Standard responsive web viewport -->
<meta name="viewport" content="width=device-width, initial-scale=1.0">
```

> **What the engine actually does (3.4x).** Flutter logs *"Found an existing `<meta name="viewport">` tag … This tag will be replaced"* and injects
> `width=device-width, initial-scale=1.0, maximum-scale=5.0`. It deliberately does **not** ship `user-scalable=no`, to comply with WCAG. So a zoom-locking tag in your `index.html` is (a) ignored at runtime yet (b) still counted against you by Lighthouse/a11y audits. Delete it.
>
> Zoom is tracked through `visualViewport`, and the engine computes `devicePixelRatio = window.devicePixelRatio × visualViewport.scale`, so hit-testing stays accurate while zoomed (pointer positions come from `offsetX/Y` or `clientX/Y − getBoundingClientRect()`). Keep zoom enabled.
>
> If browser zoom feels wrong in *your* app, the cause is usually a CSS override on the canvas — not the viewport tag.

### Removing Body Overflow Locks
If `body` has `overflow-x: hidden` or `overflow: hidden`, the browser freezes visual viewport panning. When a user zooms in with trackpad pinch or accessibility zoom, they cannot pan across the enlarged content:

```css
/* ❌ ANTI-PATTERN */
body {
  overflow-x: hidden;
  overflow: hidden;
}

/* ✅ CORRECT */
body {
  margin: 0;
  padding: 0;
  /* Allow the visual viewport to pan freely when zoomed */
}
```

---

## 3. Touch Action & Trackpad Gestures

By default, modern desktop and mobile browsers apply gesture disambiguation algorithms unless `touch-action` is declared.

### Declaring `touch-action`
```css
flutter-view {
  width: 100%;
  height: 100%;
  /* Opt into browser pinch-zoom ONLY. Do not grant pan-x/pan-y here: the engine
     already owns single-finger panning (it sets `touch-action: none` on its
     scene host), and re-granting it to the browser causes double-scroll. */
  touch-action: pinch-zoom;
}
```
- `pinch-zoom`: lets multi-touch pinch trigger native browser visual-viewport scaling while Flutter keeps single-finger panning.
- **Tradeoff:** if your app has an in-app pinch surface (PDF reader, `InteractiveViewer`, image zoom), browser pinch-zoom can steal the gesture. Test those screens; scope `touch-action` to the routes that need browser zoom, or leave it to the engine.
- Do **not** blanket-set `touch-action: pan-x pan-y pinch-zoom` on the canvas — that was the old advice and it fights Flutter's own gesture handling.

### Safari / WebKit Gesture Event Hooks
iOS Safari and macOS Safari can trigger proprietary gesture events (`gesturestart`, `gesturechange`, `gestureend`) that conflict with canvas pointer dispatch:

```javascript
// In web/index.html or initialization script:
document.addEventListener('gesturestart', function(e) {
  // Allow native visual viewport zoom while preventing gesture conflict
}, { passive: true });
```

---

## 4. Production Checklist: `web/index.html`

- [ ] Viewport meta tag does **not** contain `user-scalable=no` or `maximum-scale=1.0`.
- [ ] No CSS rule applies `width` or `height` overrides directly to `flutter-view canvas`.
- [ ] `<flutter-view>` has `touch-action: pan-x pan-y pinch-zoom;`.
- [ ] `html, body` has no `overflow-x: hidden;` lockouts.
- [ ] Favicon, web app manifest, theme-color meta tag, and OpenGraph headers are configured.

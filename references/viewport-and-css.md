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
  touch-action: pan-x pan-y pinch-zoom;
}
```
- `pan-x pan-y`: Informs the browser that horizontal and vertical scrolling are handled naturally.
- `pinch-zoom`: Signals that multi-touch pinch gestures should trigger native browser visual viewport scaling.

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

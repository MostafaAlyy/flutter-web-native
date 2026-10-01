// examples/smooth_wheel_shim.js — app-wide smooth mouse-wheel scrolling for
// Flutter web. Copy to web/ and load it from web/index.html before the
// bootstrap:   <script src="smooth_wheel_shim.js" defer></script>
//
// Widget-level wheel smoothers MUST stand down when
// window.__flutterSmoothWheel === true (read it via dart:js_interop, see
// references/scroll-architecture.md) or the same distance is eased twice.
// Replayed slices keep the notch's wheelDelta, so the engine labels them
// PointerDeviceKind.mouse exactly like a real notch: Shift+wheel horizontal
// flips and InteractiveViewer wheel-zoom keep working, and filtering by
// device kind cannot tell the shim's events apart.
//
// Smooth mouse-wheel scrolling for the Flutter canvas.
//
// Flutter web turns each mouse-wheel notch into ONE pointer-scroll signal, and
// every Scrollable jumps the whole ~100 px in a single frame. Native pages ease
// the same notch over ~200 ms, so a Flutter page reads as a stepping canvas.
// The framework has no global hook for wheel easing (ScrollBehavior cannot
// intercept pointer signals), so this shim does it once, below the framework,
// for every scroll view in the app:
//
//   a trusted, discrete mouse-wheel event over <flutter-view> is cancelled
//   before the engine's listener sees it, and its delta is replayed as a short
//   eased series of synthetic wheel events at the same target and position.
//
// Untouched (passed straight to the engine): trackpads and precision touchpads
// (their deltas are already continuous), Ctrl/Cmd+wheel (zoom), events
// outside <flutter-view> (YouTube iframes, HTML overlays), macOS/iOS (the OS
// already accelerates and eases wheel input), and prefers-reduced-motion.
//
// The ease is time-based: SMOOTHING is the fraction of the remaining distance
// consumed per 60 Hz frame, scaled by real elapsed time, so a throttled device
// settles in the same wall-clock time instead of gliding on for seconds.
(function installSmoothWheel() {
  'use strict';
  if (window.__flutterSmoothWheel !== undefined) return;

  var platform =
    (navigator.userAgentData && navigator.userAgentData.platform) ||
    navigator.platform ||
    '';
  if (/mac|iphone|ipad|ipod/i.test(platform) || /iPhone|iPad|iPod/.test(navigator.userAgent)) {
    window.__flutterSmoothWheel = false;
    return;
  }

  var SMOOTHING = 0.32;
  // Continuous streams (trackpads) emit wheel events every few ms; a notch-like
  // delta inside such a stream is a fast trackpad flick, not a mouse wheel.
  var STREAM_GAP_MS = 60;
  var reducedMotion =
    window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)');

  var pending = null;
  var frame = 0;
  var lastContinuousAt = -Infinity;

  function isNotchWheel(event) {
    if (event.deltaMode === 1 || event.deltaMode === 2) return true;
    if (event.deltaMode !== 0) return false;
    var dx = Math.abs(event.deltaX);
    var dy = Math.abs(event.deltaY);
    if (dx !== 0 && dy !== 0) return false;
    var delta = dy || dx;
    if (delta < 40) return false;
    var wheelDelta = Math.abs(event.wheelDeltaY || event.wheelDeltaX || 0);
    // Blink and WebKit report one wheel notch as a wheelDelta of 120.
    if (wheelDelta) return wheelDelta % 120 === 0;
    return delta % 1 === 0;
  }

  function inFlutterView(target) {
    return !!(target && target.closest && target.closest('flutter-view'));
  }

  function emit(state, dx, dy) {
    var synthetic;
    try {
      synthetic = new WheelEvent('wheel', {
        bubbles: true,
        cancelable: true,
        composed: true,
        deltaX: dx,
        deltaY: dy,
        deltaMode: state.mode,
        clientX: state.clientX,
        clientY: state.clientY,
        screenX: state.screenX,
        screenY: state.screenY,
        shiftKey: state.shiftKey,
        altKey: state.altKey,
      });
    } catch (_) {
      return;
    }
    // Keep the notch's own wheelDelta on every replayed slice. The engine
    // labels a wheel event "mouse" when wheelDelta is not -3x its delta
    // (pointer_binding.dart `_isAcceleratedMouseWheelDelta`); without this the
    // small slices read as trackpad input, and the framework treats trackpad
    // scrolls differently from a mouse wheel: Scrollable skips the Shift
    // horizontal flip and InteractiveViewer pans instead of zooming.
    // wheelDelta is not a WheelEventInit member, so it is set as an own
    // property that shadows the prototype getter.
    if (state.wheelDeltaY) defineWheelDelta(synthetic, 'wheelDeltaY', state.wheelDeltaY);
    if (state.wheelDeltaX) defineWheelDelta(synthetic, 'wheelDeltaX', state.wheelDeltaX);
    state.target.dispatchEvent(synthetic);
  }

  function defineWheelDelta(event, name, value) {
    try {
      Object.defineProperty(event, name, { value: value, enumerable: true });
    } catch (_) {
      /* non-configurable on this engine: the slice stays trackpad-labelled */
    }
  }

  function step(now) {
    frame = 0;
    var state = pending;
    if (!state) return;
    var dt = state.lastFrame
      ? Math.min(Math.max((now - state.lastFrame) / 1000, 1 / 240), 0.1)
      : 1 / 60;
    state.lastFrame = now;
    var fraction = 1 - Math.pow(1 - SMOOTHING, dt * 60);
    var dx = state.dx * fraction;
    var dy = state.dy * fraction;
    var epsilon = state.mode === 0 ? 0.5 : 0.02;
    if (Math.abs(state.dx - dx) < epsilon && Math.abs(state.dy - dy) < epsilon) {
      dx = state.dx;
      dy = state.dy;
      pending = null;
    } else {
      state.dx -= dx;
      state.dy -= dy;
    }
    emit(state, dx, dy);
    if (pending) frame = requestAnimationFrame(step);
  }

  // Lands whatever is still owed in one event, so a cancelled ease never
  // silently loses scroll distance the user asked for.
  function flush() {
    var state = pending;
    pending = null;
    if (frame) {
      cancelAnimationFrame(frame);
      frame = 0;
    }
    if (state && (state.dx || state.dy)) emit(state, state.dx, state.dy);
  }

  function drop() {
    pending = null;
    if (frame) {
      cancelAnimationFrame(frame);
      frame = 0;
    }
  }

  function onWheel(event) {
    if (!event.isTrusted || event.defaultPrevented) return;
    if (event.ctrlKey || event.metaKey) return;
    if (reducedMotion && reducedMotion.matches) return;
    if (!inFlutterView(event.target)) return;

    var now = event.timeStamp || performance.now();
    if (!isNotchWheel(event) || now - lastContinuousAt < STREAM_GAP_MS) {
      lastContinuousAt = now;
      if (pending) flush();
      return;
    }

    event.preventDefault();
    event.stopImmediatePropagation();

    var state = pending;
    if (
      state &&
      state.target === event.target &&
      state.mode === event.deltaMode &&
      state.shiftKey === event.shiftKey
    ) {
      // Same gesture: extend the ease instead of restarting it, so a fast
      // multi-notch spin accelerates naturally.
      state.dx += event.deltaX;
      state.dy += event.deltaY;
      state.clientX = event.clientX;
      state.clientY = event.clientY;
      state.wheelDeltaX = event.wheelDeltaX || state.wheelDeltaX;
      state.wheelDeltaY = event.wheelDeltaY || state.wheelDeltaY;
    } else {
      if (state) flush();
      pending = {
        target: event.target,
        mode: event.deltaMode,
        dx: event.deltaX,
        dy: event.deltaY,
        clientX: event.clientX,
        clientY: event.clientY,
        screenX: event.screenX,
        screenY: event.screenY,
        shiftKey: event.shiftKey,
        altKey: event.altKey,
        wheelDeltaX: event.wheelDeltaX || 0,
        wheelDeltaY: event.wheelDeltaY || 0,
        lastFrame: 0,
      };
    }
    if (!frame) frame = requestAnimationFrame(step);
  }

  window.addEventListener('wheel', onWheel, { capture: true, passive: false });
  // A press or drag takes ownership of the position; a hidden tab gets no
  // frames, so an ease left pending would replay stale distance on return.
  window.addEventListener('pointerdown', drop, true);
  document.addEventListener('visibilitychange', function () {
    if (document.hidden) drop();
  });

  window.__flutterSmoothWheel = true;
})();

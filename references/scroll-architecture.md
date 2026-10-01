# Scroll Architecture: Momentum, Wheel Physics & Scrollbars

Native desktop browsers (Chrome, Edge, Safari, Firefox) feature finely tuned scroll engines. When you scroll with a mouse wheel or trackpad, content does not jump discretely across fixed 50px chunks; it decelerates along smooth cubic momentum curves.

Flutter Web, out of the box, does not mimic this desktop feel. Without tuning, it feels either like a jerky Android list or a video game canvas that intercepts mouse dragging.

---

## 1. The Stepped Wheel Tick Problem

### What Flutter Does by Default
In Flutter's `ScrollPositionWithSingleContext` (`packages/flutter/lib/src/widgets/scroll_position_with_single_context.dart`, abridged from 3.47):

```dart
@override
void pointerScroll(double delta) {
  if (delta == 0.0) {
    goBallistic(0.0);
    return;
  }
  final double targetPixels = math.min(math.max(pixels + delta, minScrollExtent), maxScrollExtent);
  if (targetPixels != pixels) {
    goIdle();
    updateUserScrollDirection(/* ... */);
    final double oldPixels = pixels;
    isScrollingNotifier.value = true;
    forcePixels(targetPixels); // ❌ JUMPS INSTANTLY
    didStartScroll();
    didUpdateScrollPositionBy(pixels - oldPixels);
    // ...
  }
}
```

Every notch of a physical mouse wheel fires one pointer scroll event (typically ~100 px in Chrome on Windows/Linux). `forcePixels` snaps the viewport in one frame. On 60/120/144 Hz monitors this reads as a stepping canvas.

---

## 1a. App-wide default: the page-level wheel shim

The framework has no global hook, but the **engine** has a single choke point: every DOM `wheel` event on the view is converted into a scroll signal, whatever the device (`engine/src/flutter/lib/web_ui/lib/src/engine/pointer_binding.dart` → `_handleWheelEvent` / `_convertWheelEventToPointerData`; the listener is registered on the view root element with `passive: false`). A small page-level JS shim can therefore ease *every* Scrollable in the app — lists, slivers, nested views, third-party widgets — without touching Dart:

1. Listen for `wheel` on `window` in the **capture** phase with `passive: false` (runs before the engine's target-phase listener).
2. For a **trusted, discrete notch** whose target is inside `<flutter-view>`: `preventDefault()` + `stopImmediatePropagation()`.
3. Replay the delta as a time-based eased series of synthetic `WheelEvent`s on rAF — same target, `clientX/Y`, `deltaMode`, `shiftKey`, **and the original notch's `wheelDeltaX/Y`** (set as own properties with `Object.defineProperty`; `wheelDelta` is not a `WheelEventInit` member) — with `fraction = 1 - (1 - s)^(dt*60)`, `s ≈ 0.32`. Extend the pending ease on repeated notches; flush the remainder on target/mode change; drop it on `pointerdown` or `visibilitychange → hidden`.
4. **Skip** (pass through untouched): untrusted events, Ctrl/Cmd (zoom), non-`flutter-view` targets (iframes/overlays), `prefers-reduced-motion`, macOS/iOS (the OS already eases), and continuous streams — any non-notch event within ~60 ms marks a trackpad.
5. **Notch detection**: `deltaMode` 1/2; or pixel mode with a single axis, `|delta| ≥ 40` and `wheelDelta % 120 === 0` (Blink/WebKit notch convention); else an integral delta.

Drop-in: **`examples/smooth_wheel_shim.js`** (sets `window.__flutterSmoothWheel = true` when active, `false` when it stands down on Apple platforms). Verified in headless Chrome against a 3.47 skwasm build: one 100 px notch became several synthetic events summing to exactly 100.

**Caveats you must design for (verified in engine/framework source):**
- **Device kind.** The engine labels a wheel event *mouse* when `wheelDelta` is not `-3 × delta` (`pointer_binding.dart`, `_isAcceleratedMouseWheelDelta` → `_isTrackpadEvent` returns false). A synthetic slice with no `wheelDelta` gets `wheelDelta = -delta`-ish values from Blink and is labelled **`PointerDeviceKind.trackpad`** — and the framework treats trackpad scrolls differently: `Scrollable` only applies `pointerAxisModifiers` (Shift → horizontal) to mouse-kind events (`widgets/scrollable.dart`, `_pointerSignalEventDelta`), and `InteractiveViewer` *pans* on trackpad scroll but *zooms* on mouse wheel (`trackpadScrollCausesScale`). Carrying the notch's `wheelDelta` (e.g. −120) on every slice keeps them mouse-kind, so both behaviours match the unshimmed app. Verified in Chrome: every slice reports `wheelDeltaY: -120`, slices sum to exactly the notch delta.
- Because the slices are indistinguishable from a real notch by kind, a widget-level smoother (e.g. `SmoothWheelScroll`) must stand down by reading the page flag through `dart:js_interop` — filtering on `PointerDeviceKind` cannot detect the shim.
- It only sees events whose target is inside `<flutter-view>`; platform views (iframes) keep native behavior.
- It changes timing for *everything* scrolled by wheel, including programmatic listeners that expected one event per notch (e.g. a "next page on wheel" carousel). Audit those.

Reading the flag from Dart (conditional import, because `dart:js_interop` does not compile for native):

```dart
// smooth_wheel_shim.dart
export 'smooth_wheel_shim_stub.dart'
    if (dart.library.js_interop) 'smooth_wheel_shim_web.dart';

// smooth_wheel_shim_stub.dart
bool get isSmoothWheelShimActive => false;

// smooth_wheel_shim_web.dart
import 'dart:js_interop';

@JS('__flutterSmoothWheel')
external JSAny? get _flag;

bool get isSmoothWheelShimActive {
  final JSAny? flag = _flag;
  return flag != null && flag.isA<JSBoolean>() && (flag as JSBoolean).toDart;
}

// main.dart
SmoothWheelScroll.pageShimActive = () => isSmoothWheelShimActive;
```

Load the shim with `<script src="smooth_wheel_shim.js" defer></script>` before the bootstrap; it only has to be live by the first wheel event, so `defer` keeps it off the critical path.

**When to prefer the per-view scroller instead (section 1b):** you need per-view tuning (gain, smoothing), you embed Flutter as a custom element inside a host page that owns wheel behavior, or you can't touch `index.html`. The two compose: shim app-wide, per-view scroller stands down while the flag is true.

---

## 1b. Per-view smoothing (`SmoothScrollController` / `SmoothWheelScroll`)
Instead of instantaneous `forcePixels`, subclass `ScrollController` and `ScrollPositionWithSingleContext` to accumulate deltas and glide to the target with `Curves.easeOutCubic`:

```dart
class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    this.duration = const Duration(milliseconds: 180),
    this.curve = Curves.easeOutCubic,
  });

  final Duration duration;
  final Curve curve;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return SmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
      duration: duration,
      curve: curve,
    );
  }
}

class SmoothScrollPosition extends ScrollPositionWithSingleContext {
  SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels = 0.0,
    super.keepScrollOffset = true,
    super.oldPosition,
    super.debugLabel,
    required this.duration,
    required this.curve,
  });

  final Duration duration;
  final Curve curve;
  double? _targetPixels;

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) {
      goBallistic(0.0);
      return;
    }

    // Check if user has reduced motion enabled
    final mediaQuery = context.notificationContext != null
        ? MediaQuery.maybeOf(context.notificationContext!)
        : null;
    if (mediaQuery?.disableAnimations ?? false) {
      super.pointerScroll(delta);
      return;
    }

    final currentTarget = _targetPixels ?? pixels;
    final newTarget = (currentTarget + delta).clamp(minScrollExtent, maxScrollExtent);

    if (newTarget == pixels) return;

    _targetPixels = newTarget;

    animateTo(
      newTarget,
      duration: duration,
      curve: curve,
    ).whenComplete(() {
      if (_targetPixels == newTarget) {
        _targetPixels = null;
      }
    });
  }

  @override
  void jumpTo(double value) {
    _targetPixels = null;
    super.jumpTo(value);
  }

  @override
  void goIdle() {
    _targetPixels = null;
    super.goIdle();
  }
}
```

---

> **Reality check (Flutter 3.47).** There is **no first-party framework hook** for smooth wheel scrolling. `ScrollBehavior` exposes `dragDevices`, `getScrollPhysics`, `buildScrollbar`, `buildOverscrollIndicator`, and `pointerAxisModifiers` — none of them can rewrite a wheel delta. The framework calls `position.pointerScroll(delta)` synchronously, and on the web **trackpad and mouse wheel share that same pointer-signal path**. The only app-wide lever is below the framework: the page-level shim in section 1a.
>
> The `animateTo`-per-event approach above is the *simple* version. On a trackpad (dozens of events per second) it starts dozens of competing animations. The robust pattern is to **coalesce deltas into one target and ease a single ticker toward it**, time-based (not tick-based) so a throttled low-end device still settles quickly. See `examples/smooth_wheel_scroll.dart` for the production version (`examples/smooth_scroll_controller.dart` is the simpler `animateTo` variant). Gating to `PointerDeviceKind.mouse` leaves real trackpad deltas untouched, but is **not** a valid way to detect the page shim (its slices are mouse-kind by design).
>
> Reduced motion is already handled for you: `MediaQuery.disableAnimations` mirrors `prefers-reduced-motion` on web, so gate smoothing on it rather than reading `matchMedia` yourself.

## 2. Mouse Dragging vs. Text Selection Conflict

### The Fatal Web Mistake: Adding `mouse` to `dragDevices`
Some Flutter tutorials suggest adding `PointerDeviceKind.mouse` to `ScrollBehavior.dragDevices`:

```dart
// ❌ CRITICAL ANTI-PATTERN FOR WEB
class BadWebScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse, // ❌ RUINS WEB TEXT SELECTION!
  };
}
```

### Why This Destroys Web Usability
On a native website, dragging your mouse cursor across paragraphs, table cells, or lists **selects text**.
If `PointerDeviceKind.mouse` is permitted in `dragDevices`, dragging a mouse cursor initiates a viewport pan instead! Users can no longer highlight text with their mouse without triggering involuntary page sliding.

### The Correct `ScrollBehavior`:
```dart
class NativeWebScrollBehavior extends MaterialScrollBehavior {
  const NativeWebScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    // Note: PointerDeviceKind.mouse is deliberately EXCLUDED so mouse drag
    // always selects text rather than panning the page.
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Only wrap with scrollbar if the scrollable is vertical or primary
    if (details.controller == null) {
      return child;
    }
    return Scrollbar(
      controller: details.controller,
      child: child,
    );
  }
}
```

---

## 3. Clamping Physics vs. Bouncy Rubber-Banding

- **iOS Touch screens**: Elastic bounce (`BouncingScrollPhysics`) is standard.
- **Desktop Web (Chrome, Windows, Linux, Mac Safari Web)**: Pages do **not** bounce like iOS apps when reaching the top or bottom of a window. They stop flat (`ClampingScrollPhysics`).
- Use `ClampingScrollPhysics` across web desktop views.

---

## 4. Scrollbar Theming & The Unattached Controller Trap

### The Trap: Global `interactive: true` or `thumbVisibility: true`
In Flutter's `Scrollbar`:

```dart
assert(!_interactive || scrollController != null, 'A ScrollController is required when using the Scrollbar...');
```

If you set `interactive: true` or `thumbVisibility: true` globally in `ThemeData.scrollbarTheme`:
```dart
// ❌ CRASHES IN DEBUG ON ANY SCROLL VIEW WITHOUT AN EXPLICIT CONTROLLER
scrollbarTheme: ScrollbarThemeData(
  thumbVisibility: WidgetStatePropertyAll(true),
  interactive: true,
)
```
Any nested sheet, dialog, or third-party widget with an unattached scroll controller throws an unhandled assertion crash!

### The Safe Production Theme:
```dart
scrollbarTheme: ScrollbarThemeData(
  thickness: const WidgetStatePropertyAll(6),
  radius: const Radius.circular(3),
  // Leave thumbVisibility and interactive to individual views that own controllers
  thumbColor: WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.dragged) || states.contains(WidgetState.hovered)) {
      return scheme.outline;
    }
    return scheme.outlineVariant;
  }),
  trackVisibility: const WidgetStatePropertyAll(false),
)
```
Pair `Scrollbar(controller: _controller)` with `SingleChildScrollView(controller: _controller)` explicitly on views where a visible, draggable scrollbar is needed.

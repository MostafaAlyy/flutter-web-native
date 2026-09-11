# Scroll Architecture: Momentum, Wheel Physics & Scrollbars

Native desktop browsers (Chrome, Edge, Safari, Firefox) feature finely tuned scroll engines. When you scroll with a mouse wheel or trackpad, content does not jump discretely across fixed 50px chunks; it decelerates along smooth cubic momentum curves.

Flutter Web, out of the box, does not mimic this desktop feel. Without tuning, it feels either like a jerky Android list or a video game canvas that intercepts mouse dragging.

---

## 1. The Stepped Wheel Tick Problem

### What Flutter Does by Default
In Flutter's `ScrollPositionWithSingleContext`:

```dart
// Flutter default implementation:
@override
void pointerScroll(double delta) {
  if (delta == 0.0) {
    goBallistic(0.0);
    return;
  }
  final double newPixels = math.min(math.max(pixels + delta, minScrollExtent), maxScrollExtent);
  if (newPixels != pixels) {
    forcePixels(newPixels); // ❌ JUMPS INSTANTLY!
    didUpdateScrollPositionBy(delta);
  }
}
```

Every notch of a physical mouse wheel fires a pointer scroll event (typically 40–80 pixels). Calling `forcePixels` immediately snaps the viewport to the new offset without any easing. On 60Hz/120Hz/144Hz desktop monitors, this feels like an ugly, stepped vibration.

### The Production Solution: `SmoothScrollController`
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

> **Reality check (Flutter 3.4x).** There is **no global first-party hook** for smooth wheel scrolling. `ScrollBehavior` exposes `dragDevices`, `getScrollPhysics`, `buildScrollbar`, `buildOverscrollIndicator`, and `pointerAxisModifiers` — none of them can rewrite a wheel delta. The framework calls `position.pointerScroll(delta)` synchronously, and on the web **trackpad and mouse wheel share that same pointer-signal path**.
>
> The `animateTo`-per-event approach above is the *simple* version. On a trackpad (dozens of events per second) it starts dozens of competing animations. The robust pattern is to **coalesce deltas into one target and ease a single ticker toward it**, time-based (not tick-based) so a throttled low-end device still settles quickly. See `examples/smooth_scroll_controller.dart` for a production version, and only apply it to `PointerDeviceKind.mouse` if you also want to leave macOS inertial trackpad deltas untouched.
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

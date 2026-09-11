# Trackpad, Pinch-to-Zoom & Canvas Stage Ergonomics

Modern web applications (Figma, Canva, Google Maps, Miro, CAD/Studio tools) feature fluid trackpad gestures and mouse zooming. Achieving this in Flutter Web requires bridging two separate event pipelines:

1. **Modern Trackpad Pan/Zoom Events** (`PointerPanZoomUpdateEvent`)
2. **Browser-Synthesized Wheel Pinch Events** (`PointerScrollEvent` with `ctrlKey`)

---

## 1. The Two Gesture Pipelines on Desktop Web

### Pipeline A: Native Trackpad Pan & Zoom
Flutter 3+ introduced native trackpad gesture recognition. When a user pinches or two-finger pans on macOS, Windows Precision Trackpads, or ChromeOS, the engine dispatches `PointerPanZoom*` events:

- `onPointerPanZoomStart`
- `onPointerPanZoomUpdate` (contains `event.pan`, `event.scale`, `event.rotation`)
- `onPointerPanZoomEnd`

### Pipeline B: Browser Ctrl + Wheel Synthesis
When a user pinches on a trackpad in Chrome or Firefox on Windows/Linux/macOS, the browser often synthesizes this gesture as a `WheelEvent` with `ctrlKey = true`.
Similarly, desktop power users frequently hold **Ctrl** (or **Cmd** on Mac) and roll the mouse wheel to zoom in and out of images, documents, and canvases.

---

## 2. Implementing High-Fidelity Canvas Zoom & Pan

To make any canvas, preview area, or node editor feel like a native desktop tool (like Figma or Photoshop), use this unified pointer listener:

```dart
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NativeZoomableStage extends StatefulWidget {
  const NativeZoomableStage({
    super.key,
    required this.child,
    this.minScale = 0.1,
    this.maxScale = 10.0,
  });

  final Widget child;
  final double minScale;
  final double maxScale;

  @override
  State<NativeZoomableStage> createState() => _NativeZoomableStageState();
}

class _NativeZoomableStageState extends State<NativeZoomableStage> {
  double _scale = 1.0;
  Offset _pan = Offset.zero;

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final isZoomModifier = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;

      if (isZoomModifier) {
        // Continuous exponential zoom curve:
        // Scroll up (negative dy) zooms in; scroll down zooms out.
        const sensitivity = 0.003;
        final zoomFactor = math.exp(-event.scrollDelta.dy * sensitivity);
        final newScale = (_scale * zoomFactor).clamp(widget.minScale, widget.maxScale);

        // Zoom centered around the pointer's focal position:
        final focalPoint = event.localPosition;
        final focalOffset = focalPoint - _pan;
        final newPan = focalPoint - focalOffset * (newScale / _scale);

        setState(() {
          _scale = newScale;
          _pan = newPan;
        });
      }
    }
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    // Native trackpad two-finger pinch and pan
    final newScale = (_scale * event.scale).clamp(widget.minScale, widget.maxScale);
    final focalPoint = event.localPosition;
    final focalOffset = focalPoint - _pan;
    final newPan = focalPoint - focalOffset * (newScale / _scale) + event.panDelta;

    setState(() {
      _scale = newScale;
      _pan = newPan;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
      child: ClipRect(
        child: Transform(
          transform: Matrix4.identity()
            ..translate(_pan.dx, _pan.dy)
            ..scale(_scale),
          child: widget.child,
        ),
      ),
    );
  }
}
```

---

## 3. Keyboard Shortcuts for Native Web Canvas

Pro web tools conform to industry-standard keyboard ergonomics:

| Action | Native Shortcut | Implementation |
|---|---|---|
| **Zoom In** | `Ctrl + +` / `Cmd + +` | `CallbackShortcuts` / `Actions` |
| **Zoom Out** | `Ctrl + -` / `Cmd + -` | `CallbackShortcuts` / `Actions` |
| **Reset Zoom (100%)** | `Ctrl + 0` / `Cmd + 0` | Reset `scale = 1.0`, `pan = Offset.zero` |
| **Hand Pan Mode** | `Spacebar + Mouse Drag` | Track `LogicalKeyboardKey.space` to show `SystemMouseCursors.grab` |

---

## 4. `InteractiveViewer` on Web: Tips & Gotchas

If you choose Flutter's built-in `InteractiveViewer`:
1. Set `trackpadScrollCausesScale: true` so trackpad gestures zoom instead of pan.
2. Provide explicit `minScale` and `maxScale` (e.g. `0.2` to `5.0`) to prevent infinite inversion.
3. If placing inside a scrollable web page, set `boundaryMargin: EdgeInsets.zero` and disable vertical drag propagation when scale is 1.0 to prevent intercepting normal page scroll.

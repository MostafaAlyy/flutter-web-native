# Raster Cost on Flutter Web (single-threaded Skwasm & CanvasKit)

Native Flutter has a separate raster thread and a picture raster cache. Flutter web has **neither by default**. Effects that are free on a phone — an always-on ambient backdrop, a looping shimmer, a decorative Rive scene — can cost a whole frame budget on the web. This file explains why and gives fix patterns that were measured in production.

> Measure first (`performance-measurement.md`): decide with main-thread ms per frame and LoAF blocking time, never with headless rAF fps.

---

## 1. Where raster work runs

| Build | Raster thread? |
| --- | --- |
| dart2js + CanvasKit | No — CanvasKit draws on the main thread. |
| `--wasm` (Skwasm), page **cross-origin isolated** (COOP + COEP) | Multi-threaded: Skwasm renders in a worker. |
| `--wasm` (Skwasm), **not** isolated | **Single-threaded**: path tessellation, picture replay and GL command encoding all run on the UI thread. |

Verified in the 3.47 loader (`engine/src/flutter/lib/web_ui/flutter_js/src/skwasm_loader.js`): `skwasmSingleThreaded` is true when `!crossOriginIsolated`, when `forceSingleThreadedSkwasm` is set, inside Chrome extensions, or with `enableWimp`. Without isolation the loader falls back automatically and logs a console warning (silence it with `suppressMultithreadingWarning: true` in the loader config).

Cross-origin isolation is often impossible: `Cross-Origin-Embedder-Policy: require-corp` breaks third-party iframes (YouTube and most embed players) and any cross-origin resource that doesn't send CORP/CORS headers. `credentialless` is gentler but still affects iframes. **Assume single-threaded Skwasm** unless you've proven isolation in production (`window.crossOriginIsolated === true`).

---

## 2. There is no picture raster cache on the web

Every web frame re-renders the **whole scene**. The engine's frame pipeline (`engine/.../layer/layer_tree.dart`, called from `compositing/rasterizer.dart`) runs `preroll` → `measure` (every picture replayed into a bounds recorder) → `paint` (every picture drawn into its display canvas) → rasterize, for the full layer tree. The doc comment still mentions a raster cache; there is no implementation in `lib/web_ui`.

So:
- **Any animating pixel makes the engine replay every visible picture.** An ambient animation costs roughly "render the whole screen", every frame — not just its own layer.
- **`RepaintBoundary` does not isolate raster cost on web.** It still saves framework-side paint (the Dart `paint()` calls for the unchanged subtree are skipped and the layer is retained), but the engine replays the retained picture every frame anyway.
- Complex static content (dense vector illustrations, many text runs, blurred shadows) under an animation gets more expensive the more of it is on screen.

Measured (large 3.47 skwasm app, single-threaded, mobile profile at 4× CPU): an ambient vector backdrop — 57 groups / 270 paths animated at 24 fps — cost **~20–25 ms of main thread per frame**. With motion off, the same page idled at **0.3 ms/frame** (no frames scheduled at all).

---

## 3. Fix pattern: rasterize rigidly-moving vector groups once

If the animated content only moves **rigidly** (translate / rotate / modest scale) and its internals don't change, record each group once into a texture and blit the texture with the same transform. Textured quads are far cheaper to replay than hundreds of path fills/strokes.

```dart
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

/// Web-only texture cache for vector groups that move rigidly.
class RigidGroupRasterCache {
  RigidGroupRasterCache(this.pictures, this.bounds)
      : paddedBounds = [for (final b in bounds) b.isEmpty ? Rect.zero : b.inflate(padding)];

  final List<ui.Picture> pictures; // one recorded picture per group
  final List<Rect> bounds;         // path bounds in source units
  final List<Rect> paddedBounds;

  /// getBounds() excludes stroke width and the anti-aliasing fringe.
  static const double padding = 2;
  /// Rasterize slightly above the largest on-screen scale: blits downsample, never upscale.
  static const double headroom = 1.05;
  /// Ceiling on cached pixels (~24 MB RGBA).
  static const double maxTotalPixels = 6e6;

  double? _scale;
  List<ui.Image?>? _images;

  double get _sourceArea =>
      paddedBounds.fold(0.0, (sum, r) => sum + r.width * r.height);

  List<ui.Image?> imagesFor({required double componentScale, required double dpr}) {
    var wanted = componentScale * dpr * headroom;
    final area = _sourceArea;
    if (area > 0) wanted = math.min(wanted, math.sqrt(maxTotalPixels / area));
    final cached = _scale;
    // Reuse within a band so a window drag-resize doesn't re-raster every frame.
    if (_images != null && cached != null &&
        wanted <= cached * 1.1 && wanted >= cached * 0.6) {
      return _images!;
    }
    dispose();
    _scale = wanted;
    return _images = [for (var i = 0; i < pictures.length; i++) _rasterize(i, wanted)];
  }

  ui.Image? _rasterize(int i, double scale) {
    final rect = paddedBounds[i];
    if (rect.isEmpty) return null;
    final w = (rect.width * scale).ceil(), h = (rect.height * scale).ceil();
    if (w <= 0 || h <= 0) return null;
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(scale)
      ..translate(-rect.left, -rect.top)
      ..drawPicture(pictures[i]);
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(w, h);
    } finally {
      picture.dispose();
    }
  }

  void dispose() {
    for (final image in _images ?? const <ui.Image?>[]) {
      image?.dispose();
    }
    _images = null;
    _scale = null;
  }
}

// In the painter, under the SAME transform you used for drawPicture:
final _blit = Paint()..filterQuality = FilterQuality.low;
void paintGroup(Canvas canvas, RigidGroupRasterCache cache, List<ui.Image?>? textures, int i) {
  final texture = textures?[i];
  if (textures == null) {
    canvas.drawPicture(cache.pictures[i]); // native: keep vectors
  } else if (texture != null) {
    canvas.drawImageRect(
      texture,
      Rect.fromLTWH(0, 0, texture.width.toDouble(), texture.height.toDouble()),
      cache.paddedBounds[i], // destination in source units
      _blit,
    );
  }
}
// textures = kIsWeb ? cache.imagesFor(componentScale: s, dpr: MediaQuery.devicePixelRatioOf(context)) : null;
```

Rules that made it work:
- **Pad bounds** for stroke width and AA (`inflate(2)` in source units for strokes ≤ 1).
- **Rasterize at componentScale × devicePixelRatio × headroom (~1.05)** so the blit is a slight downsample.
- **Cap total cached pixels** (~6 MP) — 4K / high-DPR desktops trade a little softness on decorative shapes for bounded GPU memory.
- **Reuse within a resize band** (re-raster only if wanted > cached × 1.1 or < cached × 0.6).
- **Blit with `drawImageRect` + `FilterQuality.low`** under the same transform.
- **Web-only (`kIsWeb`)** — native has a raster thread and a raster cache; textures would only cost memory there.
- `Picture.toImageSync` is implemented on both Skwasm (`skwasm_impl/picture.dart`) and CanvasKit (`canvaskit/picture.dart`). Dispose the intermediate picture and old images.

Result on the reference app: **−31% idle and −27% scroll main-thread per frame, −41% scroll LoAF blocking time**.

Don't use this for content whose *shape* animates (morphing paths, text that changes, gradients that shift per frame) — the cache would be rebuilt every frame.

---

## 4. Schedule decoration around the user, not against them

On single-threaded Skwasm, decorative frames come out of the same budget as boot, scroll and video. Policy that measurably helped:

1. **Warm-up hold.** Keep ambient animation still for ~3 s after mount on web. The first seconds after first frame are when routes build, images decode and fonts register on the one thread; an ambient 24 fps scene competing for it showed up as seconds of Lighthouse TBT on mobile. The first frame still paints the static pose.
2. **Pause during scroll.** Feed a global `ValueNotifier<bool>` from a root `NotificationListener<ScrollNotification>` and clear it on a trailing idle timer (≈ fling settle time):

   ```dart
   final scrollActive = ValueNotifier<bool>(false);
   Timer? _idle;

   bool _onScroll(ScrollNotification n) {
     if (n is ScrollStartNotification || n is ScrollUpdateNotification) {
       scrollActive.value = true;
       _idle?.cancel();
       _idle = Timer(const Duration(milliseconds: 400), () => scrollActive.value = false);
     }
     return false; // never swallow notifications
   }
   // MaterialApp(builder: (context, child) =>
   //   NotificationListener<ScrollNotification>(onNotification: _onScroll, child: child!));
   ```
   Decorative animations listen and stop their ticker (or freeze their time value) while it is true. Cancel the timer in `dispose`.
3. **Pause during media playback** (video/audio) on web for the same reason.
4. **Pause when hidden** — `AppLifecycleState.hidden/inactive` (see `web-lifecycle-and-multitab.md`).
5. **Gate on preference, not viewport.** Honor `MediaQuery.disableAnimations` (mirrors `prefers-reduced-motion` on web) and any in-app "reduce effects" switch. Don't silently disable motion because the window is narrow — a desktop user with a narrow window has a GPU; a phone in landscape doesn't gain one.

Native keeps animating through scroll/playback (separate raster thread), so make these web policies (`kIsWeb`), not global ones.

---

## 5. Other raster costs worth auditing on web

- **Blur** (`BackdropFilter`, `ImageFilter.blur`, large-blur `BoxShadow`): every frame re-runs the filter over the whole affected region. Static large shadows in scrolling lists are re-rasterized as the list moves.
- **`saveLayer`** (`Opacity` with non-trivial children, `ShaderMask`, `ColorFiltered`): offscreen passes add up quickly; prefer `FadeTransition` / pre-multiplied colors, one shimmer mask per card rather than per bar.
- **Rive/Lottie/shaders** at boot: defer until after first frame + warm-up, skip in reduced-motion.
- **Image decode size**: `cacheWidth`/`cacheHeight` (or `ResizeImage`) so the GPU isn't sampling 4K bitmaps into 200 px thumbnails.

---

## 6. Checklist

- [ ] Know your threading: `window.crossOriginIsolated` checked in production; assume single-threaded otherwise.
- [ ] Idle with nothing moving schedules no frames (ms/frame ≈ 0 in the probe).
- [ ] No always-on ambient animation, or it is texture-cached (rigid motion) and paused during boot warm-up, scroll and playback.
- [ ] `RepaintBoundary` not relied on to save web raster time.
- [ ] Motion gated on reduced-motion / user preference, not viewport size.
- [ ] Before/after measured with the A/B method in `performance-measurement.md`.

# Measuring Flutter Web Performance

You cannot optimize what you measure wrong, and Flutter web breaks most default web-perf instincts: the UI is one `<canvas>`, the "content" is not in the DOM, and the usual headless-browser numbers are GPU-bound noise. This file is the measurement playbook. Pair it with `raster-performance.md` (what to fix at runtime) and `loading-and-bootstrap.md` (what to fix at boot).

> **Ground truth.** Facts here come from a production optimization of a large Flutter 3.47 skwasm app (2026-10-01) and from engine source (`engine/src/flutter/lib/web_ui/`). Re-verify against your SDK before quoting numbers.

---

## 1. Reading Lighthouse on a canvas app

| Metric | What it really measures on Flutter web |
| --- | --- |
| **FCP / LCP** | Usually the **HTML splash `<img>`** in `index.html`. The Flutter `<canvas>` is not an LCP candidate. A good LCP says your splash paints fast — nothing about when the app is usable. |
| **TBT** | Dominated by two structural long tasks: **wasm/JS instantiate** of the app (and renderer) and the **first-frame build** (widget build + layout + first raster on the main thread). |
| **TTI** | Waits for a quiet main thread. Anything that keeps scheduling frames after boot pushes it out. |
| **Speed Index** | Computed from visual completeness over time. A **continuously animating canvas never settles**, so any ambient animation running during load inflates SI (and TTI). |
| **CLS** | Mostly irrelevant once the canvas mounts; the splash must reserve its box (explicit `width`/`height`). |

Practical consequences:
- **"FCP/LCP green, TBT/TTI/SI red" is the normal Flutter web profile**, not a contradiction.
- Any decorative animation that starts at first frame costs you SI and TTI twice: it competes for the main thread *and* keeps the page "incomplete". Hold ambient motion still for a warm-up after mount (see `raster-performance.md`).
- A Flutter canvas app **cannot reach Lighthouse mobile Performance 100** — TBT from instantiate + first build is structural. Levers that do move it: fewer/smaller boot bytes, parallelized critical-path fetches, no animation during load, an HTML splash that paints instantly.

Lighthouse sees requests made by Web Workers (e.g. a plugin's worker fetching its own `.wasm`); a naive CDP probe on the page target does not (section 4). Use Lighthouse's **network-requests** audit as the inventory of what boot really downloads.

---

## 2. The headless rig: what is meaningful and what is noise

Headless Chrome needs a GL backend or the engine never paints:

```bash
google-chrome-stable --headless=new \
  --use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader \
  --remote-debugging-port=9555 --user-data-dir="$(mktemp -d)" about:blank
```

SwiftShader rasterizes **on the CPU**. Consequences:
- **rAF fps in this rig is GPU-bound and meaningless.** It reads ~8 fps for everything — the fast build and the slow build alike.
- Real-GPU headless (`--use-angle=vulkan` / `gl-egl`) frequently fails to start. Don't build a methodology on it.

GPU-independent metrics that *do* discriminate:

| Metric | How |
| --- | --- |
| **Main-thread ms per frame** | `Performance.getMetrics` → `TaskDuration` delta over a window ÷ rAF callbacks in that window. |
| **Main-thread busy %** | Same `TaskDuration` delta ÷ wall time. Idle with nothing scheduled should be near 0. |
| **Long Animation Frames** | `PerformanceObserver({type: 'long-animation-frame', buffered: true})`; sum `blockingDuration`. |
| **Time to first Flutter frame (TTFF)** | Listen for the `flutter-first-frame` window event, injected with `Page.addScriptToEvaluateOnNewDocument` so it is armed before any app script runs. |

`flutter-first-frame` is real API surface: the framework invokes `first-frame` on the `flutter/service_worker` channel after the first frame (`packages/flutter/lib/src/rendering/binding.dart`, `_handleWebFirstFrame`), and the engine dispatches the window event (`engine/.../platform_dispatcher.dart`).

```js
// Injected via Page.addScriptToEvaluateOnNewDocument
window.__pp = { ff: null, frames: [], loaf: [] };
addEventListener('flutter-first-frame', () => { __pp.ff = performance.now(); });
new PerformanceObserver(l => { for (const e of l.getEntries())
  __pp.loaf.push([e.startTime, e.duration, e.blockingDuration || 0]); })
  .observe({ type: 'long-animation-frame', buffered: true });
(function raf(t) { __pp.frames.push(t); requestAnimationFrame(raf); })(0);
```

Drive interaction through CDP, not synthetic DOM events:
- Desktop wheel: `Input.dispatchMouseEvent {type: 'mouseWheel', x, y, deltaY: 120}` (trusted, so it exercises the real wheel path and any page-level shim).
- Mobile fling: `Input.dispatchTouchEvent` `touchStart` / `touchMove`×N / `touchEnd` with `Emulation.setTouchEmulationEnabled`.
- Mobile CPU: `Emulation.setCPUThrottlingRate {rate: 4}` plus `Emulation.setDeviceMetricsOverride` (e.g. 412×823 @ DPR 2.625, `mobile: true`).

`scripts/perf_probe.py` implements all of this (TTFF, idle and scroll ms/frame, busy %, LoAF, worker-aware transfer summary, CPU throttling, reduced motion, repeated runs with medians).

---

## 3. A/B methodology that survives scrutiny

1. **Two builds, two directories.** Build the baseline from a `git worktree` at `HEAD` (never `git stash` a dirty tree) and the change from your working copy, each with `flutter build web --wasm ... -o <dir>`. Same flags, same flavor, same `--dart-define`s.
2. **Serve prod-like.** Brotli/gzip, `immutable` caching for content-hashed files, SPA fallback, real MIME types (`application/wasm`, `text/javascript` for `.mjs`). `python -m http.server` serves **uncompressed** bytes and massively overstates download time — it will "find" problems that don't exist in production and hide ones that do. Use `scripts/prod_serve.py`.
3. **Never measure concurrently.** Two probes (or a probe and a build) on one machine corrupt each other through CPU contention. Run A, then B, then A again.
4. **Repeat.** A single TTFF probe varies **~2× run-to-run**. Take ≥3 runs per side and compare medians (`perf_probe.py --runs 3`).
5. **Use fresh profiles.** A new `--user-data-dir` per run = a cold cache = a first visit. Measure repeat visits separately if caching is the change.

Cheap A/B against the **live** site with no rebuild: emulate reduced motion (`Emulation.setEmulatedMedia {features: [{name: 'prefers-reduced-motion', value: 'reduce'}]}`) and compare idle/scroll ms per frame. If the app gates motion on `MediaQuery.disableAnimations` (which mirrors the media query on web), the delta is what *all* your motion costs. Measured on the reference app: an ambient backdrop cost ~20–25 ms main thread per frame on a 4×-throttled mobile profile; with motion off the same page idled at 0.3 ms/frame.

---

## 4. Network: what a page-target CDP probe misses

- **Worker requests are invisible to the page target's `Network` domain.** pdfrx's worker fetching `pdfium.wasm`, a Firebase or analytics worker, a pdf.js worker — none appear. Either enable `Target.setAutoAttach {autoAttach: true, flatten: true, waitForDebuggerOnStart: false}` and send `Network.enable` to each attached worker session, or trust Lighthouse's network-requests audit. `perf_probe.py` does the former.
- Report `encodedDataLength` (bytes on the wire) and `content-encoding` per request; an uncompressed `.wasm` or HTML document stands out immediately.
- Inventory **third-party boot fetches** (gstatic Firebase bundles, `accounts.google.com/gsi/client`, auth iframes) separately from your own bytes — they have their own fixes (`loading-and-bootstrap.md`).

---

## 5. CPU profiles you can actually read

- Release dart2wasm builds **strip the wasm `name` section** (`--strip-wasm` defaults on in release; `packages/flutter_tools/lib/src/web/compiler_config.dart`), so DevTools CPU profiles show anonymous `wasm-function[1234]` frames. For attribution build `flutter build web --profile --wasm`, or `--release --wasm --no-strip-wasm` to keep release optimizations with names.
- Record with the DevTools Performance panel or `Profiler.start` / `Profiler.stop` over CDP; save the `.cpuprofile` and compare self time by function.
- On single-threaded skwasm, rendering cost shows up **as main-thread time** (Skia tessellation, picture replay, GL encoding). Look for it before blaming Dart build code.

---

## 6. Field data

Lab numbers tell you direction; users have real GPUs and real networks.
- Report TTFF (from `flutter-first-frame`) and long-animation-frame counts to your analytics, segmented by renderer (`bool.fromEnvironment('dart.tool.dart2wasm')`), device class, and cross-origin-isolation (`window.crossOriginIsolated`).
- Watch for measurement changes masquerading as regressions: when you change *what* you measure (e.g. switching TTFF anchors), annotate the date.

---

## 7. Checklist

- [ ] Lighthouse read correctly: LCP = splash; TBT/SI are the real Flutter costs.
- [ ] Headless rig uses SwiftShader flags; decisions use ms/frame, busy % and LoAF, never rAF fps.
- [ ] TTFF from `flutter-first-frame`, injected before navigation.
- [ ] Baseline from a worktree; both builds served brotli-compressed with prod cache headers.
- [ ] Runs sequential, ≥3 per side, medians compared.
- [ ] Worker network requests included (auto-attach or Lighthouse).
- [ ] CPU profiles from `--profile --wasm` (or `--no-strip-wasm`).

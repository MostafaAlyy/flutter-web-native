# Concurrency: Web Workers & Isolates

A native web application never freezes the UI while parsing JSON or processing data. JavaScript runs on a single main thread; if it's blocked, scrolling stops, CSS animations stutter, and clicks are ignored. 

Because Flutter Web compiles Dart to JavaScript/Wasm, **blocking the main thread will completely freeze the Flutter UI**.

## 1. Isolates do not exist on the web

> **Reality check (verified against the 3.47 Dart SDK).** `Isolate.spawn` and `Isolate.spawnUri` **throw `UnsupportedError`** on both web compilers (`dart-sdk/lib/_internal/js_runtime/lib/isolate_patch.dart` and `_internal/wasm/common/isolate_patch.dart`). `Isolate.run` is built on `Isolate.spawn`, so it throws too. Dart isolates are **not** mapped to Web Workers.

Flutter's `compute()` has a separate web implementation (`packages/flutter/lib/src/foundation/_isolates_web.dart`) that simply does `await null; return callback(message);` — it runs **on the main thread**, after a single microtask. It does not yield to rendering, so a heavy `compute()` still freezes the page.

Consequences:
- Code that calls `Isolate.run`/`Isolate.spawn` must be guarded with `kIsWeb` (or a conditional import), or it crashes on web.
- `compute()` is safe to call on web but buys you nothing for CPU-heavy work.
- Real parallelism on the web means a **JavaScript Web Worker** (section 4) or a plugin that ships one (pdfrx, for example, runs pdfium in its own worker).

## 2. Choosing a strategy on web

| Work | Strategy |
| --- | --- |
| Small (< a few ms) | Just do it. |
| Medium, splittable (parsing a large list, building an index) | Chunk it and yield between chunks (section 3). |
| Heavy, self-contained (image processing, crypto, large JSON) | A JS Web Worker; or move it server-side. |
| Native and web share code | `compute()` — real isolate on native, main-thread on web. Pair with chunking if the web path is heavy. |

Remember that on single-threaded Skwasm and on CanvasKit the main thread also does all **rendering** (`raster-performance.md`). Every millisecond of Dart work competes directly with frames.

## 3. Chunk and yield

When work is too big to run in one go but not worth a worker, split it and yield to the event loop between chunks.

Instead of a tight `while` or `for` loop that runs for 500ms:

```dart
// BAD: Freezes the web UI for 500ms
void processPixels(List<int> pixels) {
  for (int i = 0; i < pixels.length; i++) {
    pixels[i] = _heavyMath(pixels[i]);
  }
}
```

Use `Future.delayed(Duration.zero)` or `Timer.run` to yield a macrotask, so the browser can render between chunks (`await null` / `Future.microtask` does **not** yield to rendering):

```dart
// GOOD: Yields to the event loop to keep the UI smooth
Future<void> processPixels(List<int> pixels) async {
  const chunkSize = 1000;
  for (int i = 0; i < pixels.length; i += chunkSize) {
    int end = (i + chunkSize < pixels.length) ? i + chunkSize : pixels.length;
    for (int j = i; j < end; j++) {
      pixels[j] = _heavyMath(pixels[j]);
    }
    // Yield execution back to the browser so animations don't drop frames
    await Future.delayed(Duration.zero);
  }
}
```

## 4. Web Worker Interop (`web` package)

For real parallelism, write a JavaScript Web Worker and communicate with it using `package:web` (which replaces `dart:html`). Workers fetch their own scripts/wasm: those requests don't appear in a page-target CDP network probe (`performance-measurement.md`).

1. Put `worker.js` in your `web/` folder.
2. Communicate via `package:web`:

```dart
import 'package:web/web.dart' as web;
import 'dart:js_interop';

void setupWorker() {
  final worker = web.Worker('worker.js'.toJS);
  
  worker.onmessage = (web.MessageEvent event) {
    final data = event.data.dartify();
    debugPrint('Received from worker: $data'); // use your app logger
  }.toJS;
  
  worker.postMessage('Start processing'.toJS);
}
```

Messages are structured-cloned; transfer large `ArrayBuffer`s instead of copying them.

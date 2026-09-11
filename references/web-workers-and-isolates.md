# Concurrency: Web Workers & Isolates

A native web application never freezes the UI while parsing JSON or processing data. JavaScript runs on a single main thread; if it's blocked, scrolling stops, CSS animations stutter, and clicks are ignored. 

Because Flutter Web compiles Dart to JavaScript/Wasm, **blocking the main thread will completely freeze the Flutter UI**.

## 1. The Problem with Isolates on Web

Historically, Dart `Isolate.spawn` and `compute()` did not work on the web because browsers do not support shared memory threads in the same way native OSs do. 

Starting in Dart 3 (and Flutter 3.19+), `Isolate.spawn` on the web is supported **if and only if** the browser supports Web Workers, and it uses Web Workers under the hood. However, spinning up a Web Worker has significant overhead (it essentially loads the Dart JS bundle again).

## 2. Best Practice: Small Chunks or Web Workers

### When to use `compute()` or `Isolate.run()`
Use it for massive computations (e.g., parsing a 5MB JSON payload, complex cryptography, image resizing).

```dart
// This will now use a Web Worker on modern browsers
final parsedData = await Isolate.run(() {
  return jsonDecode(hugeJsonString);
});
```

### When NOT to use Isolates on Web
Do not use Isolates for tiny tasks. The overhead of serializing data, passing it via `postMessage` to the Web Worker, and starting the worker will take longer than just doing the math on the main thread.

## 3. The `compute` Fallback Pattern

If you are writing a package or code that must run fast, and spinning up a Web Worker is too slow, but doing it synchronously blocks the UI, you must yield to the event loop.

Instead of a tight `while` or `for` loop that runs for 500ms:

```dart
// BAD: Freezes the web UI for 500ms
void processPixels(List<int> pixels) {
  for (int i = 0; i < pixels.length; i++) {
    pixels[i] = _heavyMath(pixels[i]);
  }
}
```

Use `Future.delayed(Duration.zero)` or `Timer.run` to yield back to the browser's paint cycle:

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

If you need pure, hyper-fast Web Workers without the overhead of Dart Isolates, you can write a raw JavaScript Web Worker and communicate with it using the `web` package (which replaces `dart:html`).

1. Put `worker.js` in your `web/` folder.
2. Communicate via `package:web`:

```dart
import 'package:web/web.dart' as web;
import 'dart:js_interop';

void setupWorker() {
  final worker = web.Worker('worker.js'.toJS);
  
  worker.onmessage = (web.MessageEvent event) {
    final data = event.data;
    print('Received from worker: $data');
  }.toJS;
  
  worker.postMessage('Start processing'.toJS);
}
```

This bypasses all Dart overhead and leverages native browser multi-threading perfectly.

# Testing Flutter Web Behavior

Web fidelity bugs (selection, right-click, wheel, zoom) do not show up in `flutter test`. You need a real browser for most of them and pointer-aware widget tests for the rest.

## 1. Widget tests with real pointer kinds

`testWidgets` can simulate mouse, hover, wheel, and right-click — enough to assert scroll behavior and secondary-button handling without a browser:

```dart
testWidgets('right-click does not pan and wheel scrolls', (tester) async {
  await tester.pumpWidget(const MyApp());

  // Right-click (secondary button).
  await tester.tap(find.text('Item'), buttons: kSecondaryMouseButton);

  // Mouse drag should NOT move the scrollable (mouse excluded from dragDevices).
  final before = tester.getTopLeft(find.text('Item'));
  await tester.startGesture(
    tester.getCenter(find.byType(ListView)),
    kind: PointerDeviceKind.mouse,
  ).moveBy(const Offset(0, -200));
  await tester.pump();
  expect(tester.getTopLeft(find.text('Item')), before);

  // Wheel scroll goes through pointerScroll.
  final scrollable = find.byType(Scrollable).first;
  await tester.sendEventToBinding(
    const PointerScrollEvent(position: Offset(50, 50), scrollDelta: Offset(0, 120)),
  );
  await tester.pumpAndSettle();
});
```

Use `TestPointer` for multi-pointer/trackpad-pan gestures (`PointerPanZoomStartEvent`, `PointerPanZoomUpdateEvent`).

## 2. Integration tests in a browser (official path)

`flutter test integration_test/...` runs on the host; to run in Chrome use `flutter drive` with ChromeDriver on `PATH`:

```bash
# test_driver/integration_test.dart must call integrationDriver()
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart \
  -d chrome
# headless / CI:
flutter drive --driver=... --target=... -d web-server
```

Add `integration_test` and `flutter_driver` dev dependencies. ChromeDriver version must match the installed Chrome.

## 3. Golden tests on web

The `WebGoldenComparator` is **deprecated** and the default comparator changed. Golden-based web tests are brittle across engine/browser versions. Prefer widget goldens on the host, and use browser screenshots only for smoke verification.

## 4. Automation that actually exercises the DOM

For real-browser concerns — the semantics DOM, `BrowserContextMenu`, COOP/COEP/Wasm, `<a href>` middle-click, PWA install — drive a headless browser (Playwright/Puppeteer over CDP). Flutter's canvas is opaque to the DOM, so assert on:
- the semantics overlay (force it with `ensureSemantics`),
- network/console errors,
- `document.title` and meta tags,
- scroll/URL via the History API.

## 5. What to cover before shipping a web-facing change

- [ ] Mouse can select text (drag) and the wheel scrolls.
- [ ] Right-click shows the native menu (or is deliberately suppressed for a documented reason).
- [ ] Trackpad pan + Ctrl/Cmd-wheel zoom behave (where implemented).
- [ ] Deep link loads at the correct route; Back/Forward work; title updates.
- [ ] Real device sizes: narrow phone, large phone, tablet/desktop, browser zoom 125–200%.
- [ ] Arabic/RTL and long text do not clip; dark and light both checked.
- [ ] A performance trace in DevTools shows no long tasks >50ms on the hot path.

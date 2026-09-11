# Flutter Web Native Fidelity (`flutter-web-native`)

> **Transform Flutter Web applications from clunky canvas/game-like pages into fluid, native-feeling desktop and mobile web experiences.**

---

## 🎯 The Problem

Out of the box, Flutter Web treats the browser window like a foreign game engine canvas. This results in numerous UX flaws that immediately signal "this isn't a real website":

| Default Flutter Web Behavior | Native Web Standard (Chrome / Safari / Firefox) |
|---|---|
| ❌ Blurry Retina rendering when CSS stretches `canvas` | ✅ Dynamic DPR scaling with crisp vector strokes & sharp typography |
| ❌ Discrete, stepped mouse wheel jumps (instant `forcePixels`) | ✅ Fluid momentum scrolling with cubic easing curves |
| ❌ Mouse dragging on lists pans the page instead of selecting text | ✅ Mouse dragging selects text; only touch/trackpads pan |
| ❌ Mobile teardrop pin handles appear on desktop text selection | ✅ Standard desktop text selection handles / native cursor bars |
| ❌ Dragging selection highlights navigation rails, headers & buttons | ✅ Selection is cleanly isolated to article and data content |
| ❌ Right-click context menus are suppressed or show mobile popups | ✅ Full native browser context menu (Copy, Search, Inspect Element) |
| ❌ Viewport pinch-to-zoom is locked out or crashes panning | ✅ Fluid trackpad pinch-zoom & browser accessibility zooming |
| ❌ Interactive cards, rows & badges show default arrow cursor | ✅ Interactive elements show `cursor: pointer` (`SystemMouseCursors.click`) |
| ❌ Hash routing (`/#/path`) breaks clean web ergonomics | ✅ Path URL strategy (`/path`) with browser history & middle-click support |

---

## 📦 What's Inside

```text
flutter-web-native/
├── SKILL.md                                 # Full AI agent instructions and operational rules
├── README.md                                # Repository guide & documentation
├── references/                              # Deep technical architectural deep dives
│   ├── viewport-and-css.md                  # Canvas DPR buffer sizing, visual viewport & touch-action
│   ├── scroll-architecture.md               # Smooth scroll easing, drag devices & scrollbars
│   ├── text-selection.md                    # Desktop selection handles, chrome shielding & context menu
│   ├── trackpad-and-zoom.md                 # Trackpad pan/zoom & mouse Ctrl+Wheel zooming
│   ├── cursor-and-hover.md                  # Mouse cursors, desktop tooltips & WCAG focus rings
│   └── navigation-and-urls.md               # Path URL strategy, Link widget & title sync
├── examples/                                # Production-ready drop-in Dart & HTML snippets
│   ├── smooth_scroll_controller.dart        # Ease stepped wheel deltas into smooth momentum
│   ├── native_web_scroll_behavior.dart      # ScrollBehavior preserving mouse text selection
│   ├── native_web_app_shell.dart            # App shell with selection isolation & desktop handles
│   ├── canvas_zoom_stage.dart               # Zoomable/pannable stage with trackpad & Ctrl+wheel
│   └── index.html                           # Optimized web/index.html reference
└── scripts/                                 # Automation & tooling
    ├── audit_web_fidelity.sh                # CLI scanner detecting Flutter web anti-patterns
    └── install.sh                           # Symlink installer for agent environments
```

---

## 🚀 Quick Start: The 5-Minute Upgrade

### 1. Fix `web/index.html`
Never override canvas dimensions with CSS. Set touch-action on `flutter-view`:

```css
flutter-view {
  width: 100%;
  height: 100%;
  touch-action: pan-x pan-y pinch-zoom;
}
```

Ensure viewport meta has no zoom locks:
```html
<meta name="viewport" content="width=device-width, initial-scale=1.0">
```

### 2. Configure Native Scroll Behavior in `lib/app.dart`
```dart
MaterialApp.router(
  scrollBehavior: const NativeWebScrollBehavior(),
  // ...
);
```

### 3. Enable Native Browser Context Menu in `lib/main.dart`
```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  if (kIsWeb) {
    BrowserContextMenu.enableContextMenu();
  }
  runApp(const MyApp());
}
```

### 4. Shield Chrome from Text Selection
```dart
SelectionArea(
  selectionControls: desktopTextSelectionHandleControls,
  child: Scaffold(
    appBar: SelectionContainer.disabled(child: TopAppBar()),
    body: ContentWidget(),
  ),
);
```

---

## 🔍 Automated Audit CLI

Run the audit script against any Flutter project to scan for web anti-patterns:

```bash
./scripts/audit_web_fidelity.sh /path/to/flutter_project
```

Output:
```text
=== Flutter Web Native Fidelity Audit ===
[1/4] Checking HTML & CSS (web/index.html)...
  [PASS] Viewport zoom is enabled for accessibility
  [PASS] No destructive CSS overrides on 'flutter-view canvas'
  [PASS] touch-action: pan-x pan-y pinch-zoom configured
  [PASS] Body overflow does not lock visual viewport panning
[2/4] Checking Scroll Architecture...
  [PASS] Mouse is not in scroll dragDevices
  [PASS] SmoothScrollController is implemented
[3/4] Checking Text Selection & Menus...
  [PASS] Desktop text selection handle controls configured
  [PASS] Native browser context menu is enabled
  [PASS] SelectionContainer.disabled is used to shield UI chrome
[4/4] Checking URLs & Navigation...
  [PASS] Path URL strategy is configured (no hash # routes)
=== Audit Summary ===
✓ Great job! Zero critical native web fidelity errors found.
```

---

## 💻 Installation as an AI Skill

To install this skill in Antigravity or compatible AI coding assistants:

```bash
./scripts/install.sh
```

---

## 📄 License

MIT © [Mostafa Aly](https://github.com/MostafaAlyy)

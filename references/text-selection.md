# Text Selection, Typography & Browser Context Menus

On the web, text is the core medium of communication. Users constantly select text to copy, search, share, or quote. In a stock Flutter Web app, text selection is either completely disabled, renders mobile touch pins, or colors entire navigation bars in garish highlights.

---

## 1. The Mobile Handle Bug: Eliminating Teardrop Pins

### The Problem
When you wrap an app in `SelectionArea` without custom controls:

```dart
// ❌ WRONG ON WEB DESKTOP:
SelectionArea(
  child: myAppContent,
)
```

Flutter falls back to mobile-style teardrop pin handles that follow mouse drag selections. These mobile touch pins look bizarre on desktop browsers and instantly betray that the application was written for mobile and ported to web without care.

### The Solution: `desktopTextSelectionHandleControls`
Flutter provides `desktopTextSelectionHandleControls`, which renders native cursor bars during text selection and suppresses mobile teardrop pins:

```dart
// ✅ CORRECT ON WEB DESKTOP:
SelectionArea(
  selectionControls: desktopTextSelectionHandleControls,
  child: myAppContent,
)
```

---

## 2. Selection Isolation: Protecting Chrome and Controls

When a user drags their mouse from the top of the content area to the bottom, the selection highlight should span only paragraphs, data values, and article text. It should **never** highlight:
- Navigation bars / Nav rails
- Action buttons / Toolbars
- Status badges / Tags / Chips
- Table headers / Column labels
- Modal dialog action bars

### Shielding Non-Content Chrome with `SelectionContainer.disabled`
Wrap all interactive chrome elements with `SelectionContainer.disabled`:

```dart
// Navigation chrome:
SelectionContainer.disabled(
  child: NavRail(...),
)

// Buttons and action controls:
SelectionContainer.disabled(
  child: FilledButton(...),
)

// Status badges and tags:
SelectionContainer.disabled(
  child: StatusBadge(...),
)

// Data table header rows:
SelectionContainer.disabled(
  child: TableHeaderRow(...),
)
```

### Where to Place `SelectionArea`
Do **not** wrap the root `MaterialApp` with `SelectionArea`, because it will automatically attempt to select the entire navigation hierarchy.
Instead, wrap the content body inside your `AppShell` or page scaffolds:

```dart
Scaffold(
  appBar: SelectionContainer.disabled(child: TopAppBar(...)),
  drawer: SelectionContainer.disabled(child: AppDrawer(...)),
  body: SelectionArea(
    selectionControls: desktopTextSelectionHandleControls,
    child: PageContentWidget(),
  ),
);
```

---

## 3. Brand Text Selection Theming

Generic Flutter apps display cyan or bright blue Material highlights that clash with dark or custom branded themes.

### Configuring `TextSelectionThemeData` in `ThemeData`:
```dart
ThemeData(
  textSelectionTheme: TextSelectionThemeData(
    // Match the primary brand accent (e.g. Signal Magenta, Emerald, Royal Blue)
    cursorColor: scheme.primary,
    selectionColor: scheme.primary.withValues(alpha: 0.35),
    selectionHandleColor: scheme.primary,
  ),
  // ...
)
```

---

## 4. Native Browser Right-Click Context Menu

By default on web, Flutter captures and cancels the browser's right-click event (`contextmenu`). Right-clicking selected text or links produces either nothing or a synthetic Material popup.

Web users expect native browser options:
- **Copy** (Ctrl+C / Cmd+C)
- **Search Google for "..."**
- **Inspect Element** (DevTools)
- **Open Link in New Tab**

### Enabling Native Context Menu
In `initState` or startup initialization:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    BrowserContextMenu.enableContextMenu();
  }
  runApp(const MyApp());
}
```

When native context menus are enabled:
1. Users can right-click any selected text and copy it natively with browser extensions, password managers, and OS services.
2. Web developers and operators can right-click and "Inspect Element" directly on DOM structures.
3. Links wrapped in semantic `Link` widgets trigger the browser's native link context menu ("Open link in new tab", "Copy link address").

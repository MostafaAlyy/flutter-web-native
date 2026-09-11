# Accessibility & Keyboard on the Web

On the desktop web, accessibility is not optional and not only about screen readers. It is **Tab order, focus visibility, keyboard shortcuts, reduced motion, and a real semantics DOM**. A Flutter canvas gets none of these for free.

## 1. The semantics DOM is off by default

Flutter injects an invisible *"Enable accessibility"* button; the semantics tree (and the ARIA DOM it produces) only builds after a click or when a screen reader is detected. For tests, crawlers, or a11y-critical routes you can force it:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  runApp(const MyApp());
}
```

Then give the tree real structure: `Semantics(button: true, label: ...)`, `MergeSemantics` for icon+label rows, `SemanticsRole`/`Semantics(header: true)` for headings, and `ExcludeSemantics` for decorative art. Standard widgets (`TabBar`, `MenuAnchor`, `Table`, `ListTile`) already emit correct roles — prefer them.

## 2. Keyboard focus & traversal

- Group each screen in a `FocusTraversalGroup` and set a sensible `order`. Flutter's default reading order is widget-tree order, which rarely matches visual order on a responsive layout.
- Give each screen's primary control `autofocus: true` so Tab starts somewhere predictable.
- Never let a modal trap focus; restore focus on dismiss.
- **Focus-visible**: show a ring only for keyboard navigation, not mouse clicks. Flutter exposes the highlight mode:

```dart
final showRing = focused &&
    FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
```

## 3. Keyboard shortcuts

Desktop users expect industry-standard shortcuts. Bind them with `Shortcuts`/`Actions` or `CallbackShortcuts`, and mirror macOS `meta` with Windows/Linux `control`:

```dart
CallbackShortcuts(
  bindings: <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.keyK, control: true): _focusSearch,
    const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _focusSearch,
    const SingleActivator(LogicalKeyboardKey.escape): _closeOverlay,
  },
  child: Focus(autofocus: true, child: body),
);
```

Watch out: text fields consume keys first. Scope global commands so they don't fire while typing, and never hijack the browser's reserved shortcuts (Cmd+W, Cmd+T, Cmd+L).

## 4. Reduced motion is automatic

`MediaQuery.of(context).disableAnimations` mirrors `prefers-reduced-motion` on web, and `AnimationController` already honors it. Gate looping/parallax/auto-playing motion on it — do not read `matchMedia` yourself. Provide a static fallback rather than a frozen frame.

## 5. Screen readers

Flutter supports VoiceOver/TalkBack (mobile) and VoiceOver/JAWS/NVDA (desktop). Test with a real reader at least once:
- Every interactive control needs a label.
- Images need `semanticLabel` (or `excludeFromSemantics` when decorative).
- Live regions (`Semantics(liveRegion: true)`) for async status ("Saved", "Loading failed").

## 6. Checklist

- [ ] `ensureSemantics()` on web where a11y/crawl matters.
- [ ] Labels on all icon-only buttons; `semanticLabel` on meaningful images.
- [ ] Tab order matches visual order; visible focus ring for keyboard only.
- [ ] Standard shortcuts bound with Ctrl/Cmd parity; Esc closes overlays.
- [ ] `disableAnimations`/reduced-motion honored with a static fallback.
- [ ] Reduced-motion and dark mode both verified on a real device/browser.

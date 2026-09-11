# Mouse Cursors, Hover States & Focus Rings

On mobile touch devices, cursors do not exist. On the desktop web, **the cursor is the primary feedback mechanism** connecting user intent to interactive affordances.

When a Flutter Web app displays the default arrow cursor over clickable buttons or cards, it immediately feels dead and unresponsive.

---

## 1. The Missing Click Cursor Bug

### The Standard Web Expectation
Every clickable or actionable element in HTML renders `cursor: pointer`. Users rely on this subtle cue to distinguish static badges from clickable filters, plain text from links, and decorative cards from navigable cards.

### Fixing Interactive Elements
Wrap custom interactive widgets in `MouseRegion(cursor: SystemMouseCursors.click)`:

```dart
// Custom card or list row:
MouseRegion(
  cursor: SystemMouseCursors.click,
  child: GestureDetector(
    onTap: () => context.go('/details'),
    child: CardWidget(...),
  ),
)
```

### Essential Cursor Map for Web:
| UI Component | Expected Cursor | Flutter Constant |
|---|---|---|
| Buttons, Links, Tabs, Filter Chips | Pointer / Hand | `SystemMouseCursors.click` |
| Text Inputs, Search Bars | I-Beam | `SystemMouseCursors.text` |
| Movable Artwork, Draggable Blocks | 4-Way Crosshair | `SystemMouseCursors.move` |
| Panning Canvas (Inactive) | Open Hand | `SystemMouseCursors.grab` |
| Panning Canvas (Active Drag) | Closed Hand | `SystemMouseCursors.grabbing` |
| Column / Window Resizing | Horizontal Resize | `SystemMouseCursors.resizeColumn` / `resizeLeftRight` |
| Disabled Buttons / Forbidden Actions | Not Allowed / Circle Slash | `SystemMouseCursors.forbidden` |

---

## 2. Desktop Tooltip Ergonomics

On mobile, tooltips are triggered by long-pressing (500–1000ms tap-and-hold). On desktop web, tooltips must appear automatically when hovering with a mouse, after a comfortable delay (~300–500ms), and disappear instantly when moving away.

### Configuring Desktop Tooltips in `ThemeData`:
```dart
tooltipTheme: TooltipThemeData(
  waitDuration: const Duration(milliseconds: 400),
  showDuration: const Duration(milliseconds: 1500),
  decoration: ShapeDecoration(
    color: scheme.inverseSurface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
  ),
  textStyle: textTheme.labelSmall?.copyWith(
    color: scheme.onInverseSurface,
  ),
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
)
```

---

## 3. WCAG Keyboard Focus Rings vs. Mouse Click Focus

Web accessibility standards (WCAG 2.2 Level AA) mandate clearly visible focus indicators when navigating with the **Tab** key.
However, if a focus ring appears every time a user clicks with a mouse, the UI feels cluttered and unpolished.

### How to Implement "Focus-Visible" in Flutter
Use `FocusHighlightMode`:

```dart
class WebFocusRing extends StatelessWidget {
  const WebFocusRing({
    super.key,
    required this.child,
    required this.focused,
    this.borderRadius = 4.0,
  });

  final Widget child;
  final bool focused;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    // Only display focus indicator if user is navigating via keyboard:
    final highlightMode = FocusManager.instance.highlightMode;
    final showRing = focused && highlightMode == FocusHighlightMode.traditional;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: showRing ? context.colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: child,
    );
  }
}
```

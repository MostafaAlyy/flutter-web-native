# Arabic / RTL & Mobile-Web Chrome

An Arabic-first Flutter web app has web-specific concerns the generic checklist misses: document language/direction, Arabic font loading, iOS-PWA safe areas, and browser chrome color. These are DOM/host concerns, not Flutter widget concerns.

## 1. `lang` and `dir`

The engine sets `document.documentElement.lang` from the active locale, but it **never sets `dir`**. For an RTL app the pre-Flutter splash, scrollbars, and native DOM (semantics overlay, platform views) need `dir="rtl"`:

```html
<html lang="ar" dir="rtl">
```

If the app supports English too, still start RTL (matching the default) and update `lang`/`dir` when the locale changes:

```dart
// On locale change (web):
web.document.documentElement?.setAttribute('lang', locale.languageCode);
web.document.documentElement?.setAttribute(
  'dir', locale.languageCode == 'ar' ? 'rtl' : 'ltr',
);
```

`left`/`right` in the splash CSS are physical properties and are unaffected by `dir`, so the branded splash still centers correctly.

## 2. Arabic fonts: bundle, don't fall back

Flutter's `fontFallbackBaseUrl` defaults to `https://fonts.gstatic.com/s/`. Any glyph missing from your bundled font silently triggers a network fetch — a **FOUT flash**, a CSP hole, and a privacy/offline gap.

- Bundle a full Arabic face (e.g. Cairo, IBM Plex Sans Arabic, Noto Naskh Arabic) with the glyph coverage your content needs.
- Test with **harakat/diacritics**, ligatures, and Eastern Arabic numerals (٠١٢٣).
- Verify `FontManifest.json` lists the face and weights; preload it if it is above the fold.

## 3. iOS-PWA safe areas

The engine's injected viewport tag has no `viewport-fit=cover`, and only keyboard insets are mapped; iOS-PWA safe-area insets are a long-standing gap. If the app is installable on iOS, add insets in the surrounding DOM and keep critical chrome inside them:

```css
html { padding: env(safe-area-inset-top) env(safe-area-inset-right)
                env(safe-area-inset-bottom) env(safe-area-inset-left); }
flutter-view { width: 100%; height: 100%; }
```

Then confirm Taps near the notch/home indicator still land.

## 4. Browser chrome color & status bar

- Set `<meta name="theme-color" content="#...">` to the splash/brand color for first paint and Android Chrome.
- On iOS, `apple-mobile-web-app-status-bar-style` (`default` / `black` / `black-translucent`) controls the PWA status bar. `black-translucent` requires content to respect safe areas.
- Flutter then manages `theme-color` at runtime; keep the static tag as the pre-boot fallback.

## 5. RTL interaction caveats

- **Text selection**: desktop handles (`desktopTextSelectionHandleControls`) render correctly in RTL, but verify selection direction feels natural with Arabic.
- **Context menu / platform views**: RTL offset behavior around platform views (iframes) is not documented; test with the browser menu enabled.
- **Scrollbars** flip sides under RTL; ensure custom scrollbar styling doesn't assume a side.
- **Long text**: Arabic words are longer than their English equivalents — test narrow widths for overflow, and avoid fixed-width chips/labels.

## 6. Checklist

- [ ] `<html lang="ar" dir="rtl">` (or dynamic lang/dir) on the host document.
- [ ] Arabic font bundled; no gstatic fallback flash; diacritics render.
- [ ] iOS-PWA safe areas respected (if installable).
- [ ] `theme-color` + `apple-mobile-web-app-status-bar-style` set.
- [ ] Long Arabic text, RTL selection, and scrollbars verified on narrow widths.

# flutter-web-native

An AI Engineering Skill designed to eliminate the clunky "canvas / video game" feel of Flutter Web applications, transforming them into fluid, native-feeling desktop and mobile web experiences.

**This is the 100X Depth Edition**: It goes far beyond CSS and scrolling, diving into memory management, WebAssembly GC, Web Worker concurrency, Drag and Drop OS integration, multi-tab syncing, and SEO.

## Features

- **Viewport & CSS Integration**: Resolves blurry Retina rendering and browser zoom lockouts.
- **Scroll Architecture**: Implements smooth interpolating wheel scrolling and strips mobile drag-to-pan on desktop.
- **Text Selection**: Enforces desktop text handles, shields UI chrome from selection highlights, and restores the browser right-click menu.
- **Trackpad & Zoom**: Native support for Mac/Windows trackpad pinch-to-zoom and Ctrl+Wheel canvas zooming.
- **Cursor & Hover**: Correct system cursor mapping and accessible focus rings.
- **Wasm & CanvasKit Memory**: Deep strategies for `ImageCache` management to prevent Aw Snap crashes.
- **Concurrency**: Usage of Dart Isolates on web and `BroadcastChannel` for multi-tab sync.
- **Forms & Autofill**: Bridging password managers to the Flutter Canvas.

## Usage for AI Agents

Link this skill into your agent's active skills directory. The agent will read `SKILL.md` and use the comprehensive reference guides in `references/` and drop-in code in `examples/` to upgrade any Flutter web project to native-level fidelity.

### Quick Install for Antigravity / Cortex Agents

```bash
chmod +x scripts/install.sh
./scripts/install.sh
```

## Structure

- `SKILL.md`: The primary agent instruction file (The 10 Pillars of Native Web Fidelity).
- `references/`: 13 deep-dive architectural documents on how to solve specific web rendering problems.
- `examples/`: Production-ready Dart files and HTML shells you can drop directly into projects.
- `scripts/audit_web_fidelity.sh`: A bash utility to scan a codebase and warn about missing native-web best practices.

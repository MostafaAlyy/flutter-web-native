# flutter-web-native

An AI Engineering Skill that eliminates the clunky "canvas / video game" feel of Flutter Web applications and transforms them into fluid, native-feeling desktop and mobile web experiences.

**100X Depth Edition — updated for Flutter 3.29+ (verified on 3.47).** It goes beyond CSS and scrolling into WebAssembly/Skwasm deployment, CanvasKit memory management, bootstrap/loading UX, caching headers, DOM semantics and keyboard accessibility, PWA/offline, RTL/Arabic web chrome, multi-tab syncing, web testing, and the browser APIs Flutter does not wrap.

## What it fixes

- **Viewport & CSS**: blurry Retina rendering, browser-zoom lockouts, DPR buffer mistakes, safe areas.
- **Scroll**: stepped mouse-wheel jumps, mouse-drag panning that steals text selection, unsafe scrollbar theming.
- **Text selection**: mobile teardrop pins under a mouse, chrome getting highlighted by drag-select, broken native right-click menus.
- **Trackpad & zoom**: focal Ctrl/Cmd-wheel and trackpad pinch/pan for canvas stages.
- **Cursors & focus**: missing pointer cursors, hover tooltips, keyboard-only focus rings.
- **Performance**: Wasm/Skwasm vs CanvasKit, `--wasm`, COOP/COEP, image-cache bounds, startup/loading UI.
- **Platform**: path URL strategy, anchor links, lifecycle/visibility, multi-tab sync, offline handling.
- **Content & a11y**: semantics DOM (off by default), keyboard traversal, reduced motion, SEO reality, RTL/Arabic chrome.

## Usage for AI agents

Point your agent's skill directory at this folder. The agent reads `SKILL.md`, follows the `references/` deep-dives, and drops in the `examples/` files.

### Install for OpenCode (global)

```bash
ln -sfn "$(pwd)" "$HOME/.config/opencode/skills/flutter-web-native"
```

### Install for other agents

```bash
chmod +x scripts/install.sh
./scripts/install.sh
```

`install.sh` symlinks into `~/.agents/skills/`, `~/.gemini/antigravity/global_skills/`, and `~/.gemini/skills/` when those directories exist. Symlinks mean edits here are picked up immediately.

## Structure

- `SKILL.md` — primary agent instructions: the 10 Pillars, reality checks, tradeoffs, workflow.
- `references/` — focused deep-dives (interaction, platform, a11y/i18n, testing).
- `examples/` — production-ready Dart/JS/HTML to drop into a project.
- `scripts/audit_web_fidelity.sh` — portable, comment-aware scanner (multiline `dragDevices`, viewport, selection, memory, URLs, a11y, lifecycle).
- `scripts/install.sh` — installer for agent environments.

## Audit

```bash
./scripts/audit_web_fidelity.sh /path/to/flutter_project
./scripts/audit_web_fidelity.sh /path/to/flutter_project --strict  # CI: warnings fail
```

Exits non-zero only on critical anti-patterns (or any finding with `--strict`).

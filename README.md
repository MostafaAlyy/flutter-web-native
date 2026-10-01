# flutter-web-native

An AI Engineering Skill that eliminates the clunky "canvas / video game" feel of Flutter Web applications and transforms them into fluid, native-feeling desktop and mobile web experiences.

**100X Depth Edition — updated for Flutter 3.29+ (verified on 3.47).** It goes beyond CSS and scrolling into WebAssembly/Skwasm deployment, performance engineering (measurement, raster cost, boot critical path, delivery), CanvasKit memory management, bootstrap/loading UX, caching headers, DOM semantics and keyboard accessibility, PWA/offline, RTL/Arabic web chrome, multi-tab syncing, web testing, and the browser APIs Flutter does not wrap.

## What it fixes

- **Viewport & CSS**: blurry Retina rendering, browser-zoom lockouts, DPR buffer mistakes, safe areas.
- **Scroll**: stepped mouse-wheel jumps (app-wide page-level wheel shim or per-view scroller), mouse-drag panning that steals text selection, unsafe scrollbar theming.
- **Text selection**: mobile teardrop pins under a mouse, chrome getting highlighted by drag-select, broken native right-click menus.
- **Trackpad & zoom**: focal Ctrl/Cmd-wheel and trackpad pinch/pan for canvas stages.
- **Cursors & focus**: missing pointer cursors, hover tooltips, keyboard-only focus rings.
- **Measurement**: reading Lighthouse on a canvas app (LCP = splash; TBT/Speed Index are the real costs), SwiftShader headless rig with GPU-independent metrics (ms/frame, LoAF, time to first Flutter frame), worktree A/B builds served prod-like, worker-aware network inventory, profile builds for readable CPU profiles.
- **Raster cost**: single-threaded Skwasm without COOP/COEP, no web picture raster cache, ambient-animation cost, `toImageSync` texture caching for rigid vector motion, boot warm-up and scroll/playback pauses.
- **Boot critical path**: Firebase JS SDK import chains (generated modulepreloads), eager plugin wasm (pdfium), third-party boot fetches, font manifest trimming, entry preloads that mirror flutter.js renderer selection, metadata-only `<head>` injection.
- **Delivery**: content-hashed entrypoints + cache headers, compressed function-rendered HTML, sized `fetchpriority` splash, dangling source maps, robots.txt and `/.well-known` hygiene, honest Lighthouse expectations.
- **Renderers & memory**: Wasm/Skwasm vs CanvasKit and who actually gets Skwasm, image-cache bounds, startup/loading UI.
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
- `examples/` — production-ready Dart/JS/HTML to drop into a project (incl. `smooth_wheel_shim.js`).
- `scripts/audit_web_fidelity.sh` — portable, comment-aware scanner (multiline `dragDevices`, viewport, selection, memory, URLs, a11y, lifecycle, boot/delivery: head injection, splash sizing, robots.txt, source maps, eager pdfrx, Firebase preloads).
- `scripts/perf_probe.py` — CDP performance probe (needs `websocket-client`).
- `scripts/prod_serve.py` — prod-like static server for A/B builds (`brotli` optional).
- `scripts/install.sh` — installer for agent environments.

## Audit

```bash
./scripts/audit_web_fidelity.sh /path/to/flutter_project
./scripts/audit_web_fidelity.sh /path/to/flutter_project --strict  # CI: warnings fail
```

Exits non-zero only on critical anti-patterns (or any finding with `--strict`).

## Performance probe

```bash
pip install websocket-client brotli
python3 scripts/prod_serve.py build/web 8080 &          # brotli, prod cache headers, SPA fallback
python3 scripts/perf_probe.py http://127.0.0.1:8080/ --profile mobile --runs 3
python3 scripts/perf_probe.py http://127.0.0.1:8080/ --profile mobile --runs 3 --reduced-motion
```

Run probes sequentially, never alongside a build or another probe.

#!/usr/bin/env bash
# audit_web_fidelity.sh
# Scans a Flutter project for web fidelity anti-patterns.
#
# Usage: ./audit_web_fidelity.sh [path_to_flutter_project] [--strict]
#
# Exits non-zero only on FAIL findings (critical anti-patterns). With --strict,
# warnings also fail the run (useful in CI once a project is clean).
#
# Portable across GNU and BSD userlands: no grep -P, no grep -z, no awk
# gensub. HTML comments are stripped before markup checks so documentation
# that *mentions* an anti-pattern is not flagged as one.
#
# Sections: 1 host HTML/CSS, 2 scroll, 3 selection/menus, 4 OS/memory/build,
# 5 URLs, 6 a11y, 7 lifecycle, 8 performance & delivery (non-metadata in
# <head>, splash <img> sizing, robots.txt directives, dangling
# sourceMappingURL in build/web, eager pdfrx init, Firebase JS SDK
# modulepreloads vs the resolved firebase_core_web version). Section 8 reads
# build/web and .dart_tool/package_config.json when present — run it after
# `flutter pub get` / `flutter build web` for full coverage.

set -uo pipefail

TARGET_DIR="."
STRICT=0
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1 ;;
    -h|--help)
      echo "Usage: $0 [path_to_flutter_project] [--strict]"
      exit 0
      ;;
    *) TARGET_DIR="$arg" ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ ! -d "$TARGET_DIR" ]; then
  echo -e "${RED}Target directory not found: $TARGET_DIR${NC}"
  exit 2
fi

LIB_DIR="$TARGET_DIR/lib"
INDEX_HTML="$TARGET_DIR/web/index.html"

if [ -t 1 ]; then
  : # keep colors on a TTY
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; NC=''
fi

ERRORS=0
WARNINGS=0

check_pass() { echo -e "  [${GREEN}PASS${NC}] $1"; }
check_fail() {
  echo -e "  [${RED}FAIL${NC}] $1"
  echo -e "         ${RED}Issue:${NC} $2"
  echo -e "         ${GREEN}Fix:${NC} $3"
  ERRORS=$((ERRORS + 1))
}
check_warn() {
  echo -e "  [${YELLOW}WARN${NC}] $1"
  echo -e "         ${YELLOW}Suggestion:${NC} $2"
  WARNINGS=$((WARNINGS + 1))
}
check_info() { echo -e "  [${CYAN}INFO${NC}] $1"; }

echo -e "${BLUE}=== Flutter Web Native Fidelity Audit (v3) ===${NC}"
echo "Target: $TARGET_DIR"
echo ""

# --- helpers ---------------------------------------------------------------

# grep across lib/, quiet; returns 0 if any match.
lib_has() {
  [ -d "$LIB_DIR" ] || return 1
  grep -rEn "$1" "$LIB_DIR" >/dev/null 2>&1
}

# grep index.html excluding lines that are pure HTML comments.
# (For tag checks we match the actual tag, which comments don't contain.)
html_has() {
  [ -f "$INDEX_HTML" ] || return 1
  grep -v '^[[:space:]]*<!--' "$INDEX_HTML" | grep -Eiq "$1"
}

# Return the actual <meta name="viewport"> tag line (comments stripped).
viewport_tag() {
  [ -f "$INDEX_HTML" ] || return 0
  grep -v '^[[:space:]]*<!--' "$INDEX_HTML" \
    | grep -Ei '<meta[^>]*name=["'"'"']viewport["'"'"']' \
    | head -n 1
}

# Print a file with every <!-- ... --> removed, including multi-line comments.
# RS is a single control character, so the whole file is one record (portable
# across gawk, mawk and BSD awk).
strip_html_comments() {
  [ -f "$1" ] || return 0
  awk 'BEGIN { RS = "\001" }
    {
      s = $0; out = ""
      while ((i = index(s, "<!--")) > 0) {
        out = out substr(s, 1, i - 1)
        s = substr(s, i + 4)
        j = index(s, "-->")
        if (j == 0) { s = ""; break }
        s = substr(s, j + 3)
      }
      printf "%s", out s
    }' "$1"
}

# One HTML tag per line: comments stripped, newlines folded, split on "<".
# Lines then start with the tag name ("img src=...", "/head>", ...).
html_tag_stream() {
  strip_html_comments "$1" | tr '\n\r' '  ' | tr '<' '\n'
}

# Count <img> tag lines (from html_tag_stream) missing width= or height=.
count_unsized_imgs() {
  awk '{ t = tolower($0) } t ~ /^img[[:space:]]/ && (t !~ /[[:space:]]width[[:space:]]*=/ || t !~ /[[:space:]]height[[:space:]]*=/) { n++ } END { print n + 0 }'
}

# rootUri of a package from .dart_tool/package_config.json, as a local path.
package_root() {
  local cfg="$TARGET_DIR/.dart_tool/package_config.json" uri
  [ -f "$cfg" ] || return 1
  uri="$(awk -v want="$1" '
    /"name"[[:space:]]*:/ {
      line = $0; sub(/.*"name"[[:space:]]*:[[:space:]]*"/, "", line); sub(/".*/, "", line); cur = line
    }
    /"rootUri"[[:space:]]*:/ && cur == want {
      line = $0; sub(/.*"rootUri"[[:space:]]*:[[:space:]]*"/, "", line); sub(/".*/, "", line); print line; exit
    }' "$cfg")"
  [ -n "$uri" ] || return 1
  case "$uri" in
    file://*) uri="${uri#file://}" ;;
    /*) ;;
    *) uri="$TARGET_DIR/.dart_tool/$uri" ;;
  esac
  printf '%s\n' "$uri" | sed 's/%20/ /g'
}

# Names of resolved packages matching an ERE.
package_names() {
  local cfg="$TARGET_DIR/.dart_tool/package_config.json"
  [ -f "$cfg" ] || return 0
  grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' "$cfg" \
    | sed 's/.*:[[:space:]]*"//; s/"$//' | grep -E "$1"
}

# Detect PointerDeviceKind.mouse inside a dragDevices block, across lines.
# Dart line comments are stripped first so prose that *mentions* the anti-pattern
# is not reported as one. awk buffers from a line containing "dragDevices"
# until the closing "}".
drag_devices_uses_mouse() {
  [ -d "$LIB_DIR" ] || return 1
  local found
  found="$(
    find "$LIB_DIR" -name '*.dart' -type f 2>/dev/null | while read -r f; do
      awk '
        {
          line = $0
          sub(/\/\/.*$/, "", line)
        }
        line ~ /dragDevices/ { inblock = 1; buf = "" }
        inblock { buf = buf " " line }
        inblock && line ~ /}/ {
          if (buf ~ /PointerDeviceKind[[:space:]]*\.[[:space:]]*mouse/) {
            print FILENAME
          }
          inblock = 0
        }
      ' "$f"
    done
  )"
  [ -n "$found" ]
}

# --- 1. HTML & CSS ---------------------------------------------------------

echo -e "${BLUE}[1/8] HTML & CSS (web/index.html)${NC}"
if [ -f "$INDEX_HTML" ]; then
  VT="$(viewport_tag)"
  if echo "$VT" | grep -Eiq 'user-scalable[[:space:]]*=[[:space:]]*["'"'"']?no|maximum-scale[[:space:]]*=[[:space:]]*["'"'"']?1(\.0)?([^0-9]|$)'; then
    check_fail "Viewport zoom accessibility" \
      "The viewport meta locks browser zoom (user-scalable=no / maximum-scale=1). WCAG 1.4.4 / ACT B4F0C3 failure." \
      "Use <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">. Flutter's engine injects its own tag (maximum-scale=5.0) and strips zoom locks."
  else
    check_pass "Viewport zoom is enabled for accessibility"
  fi

  if grep -v '^[[:space:]]*<!--' "$INDEX_HTML" | grep -Eiq 'flutter-view[[:space:]]+canvas[^{]*\{[^}]*\b(width|height)[[:space:]]*:' ; then
    check_fail "Canvas buffer sizing" \
      "CSS width/height on 'flutter-view canvas' overrides the engine's devicePixelRatio buffer, causing blur and off-by-pixel taps." \
      "Remove CSS targeting 'flutter-view canvas'. Size the '<flutter-view>' host only."
  else
    check_pass "No destructive CSS overrides on 'flutter-view canvas'"
  fi

  if html_has 'touch-action[[:space:]]*:[^;{}]*pinch-zoom'; then
    check_pass "touch-action declares pinch-zoom"
  else
    check_warn "Touch action / pinch-zoom" \
      "No 'touch-action: pinch-zoom' rule found. Decide deliberately: the engine sets 'touch-action: none' on its host, so browser pinch-zoom may be blocked. Enabling 'pinch-zoom' re-opts into browser zoom, but can steal in-app pinch gestures (PDF/InteractiveViewer) — test those surfaces."
  fi

  if grep -v '^[[:space:]]*<!--' "$INDEX_HTML" | grep -Eiq 'body[^{]*\{[^}]*overflow(-x)?[[:space:]]*:[[:space:]]*hidden'; then
    check_warn "Body overflow locks" \
      "'overflow: hidden' on <body> can freeze visual-viewport panning when the page is zoomed."
  else
    check_pass "Body overflow does not lock visual viewport panning"
  fi

  if html_has '<html[^>]*lang='; then
    check_pass "<html> declares lang"
  else
    check_warn "Document language" \
      "Add lang to <html> (e.g. lang=\"ar\" dir=\"rtl\" for RTL apps). The engine sets documentElement.lang from the locale at runtime but never sets dir."
  fi

  if html_has 'name=["'"'"']theme-color["'"'"']|<meta[^>]*theme-color'; then
    check_pass "theme-color meta present"
  else
    check_warn "theme-color" \
      "Add <meta name=\"theme-color\" content=\"#...\"> matching the splash. Flutter manages it after boot; before boot the browser chrome/PWA bar has no color."
  fi

  if html_has 'rel=["'"'"']manifest["'"'"']'; then
    check_pass "Web app manifest linked"
  else
    check_warn "Web app manifest" \
      "Link manifest.json for installability (Add to Home Screen / Install App)."
  fi

  if html_has 'http-equiv=["'"'"']Content-Security-Policy["'"'"']'; then
    check_info "Content-Security-Policy present (review it for 'unsafe-eval'/'unsafe-inline')"
  else
    check_warn "Content-Security-Policy" \
      "No CSP meta found. Flutter/wasm builds need care; a CSP with nonce support is available via the flutter_bootstrap config."
  fi
else
  check_warn "web/index.html not found" "Skipping HTML/CSS checks."
fi

# --- 2. Scroll architecture ------------------------------------------------

echo ""
echo -e "${BLUE}[2/8] Scroll architecture${NC}"
if drag_devices_uses_mouse; then
  check_fail "Scroll drag devices" \
    "PointerDeviceKind.mouse is included in a scroll dragDevices set. Mouse-drag then pans the page instead of selecting text." \
    "Exclude PointerDeviceKind.mouse from dragDevices; keep wheel/trackpad scrolling and scrollbar dragging."
else
  check_pass "Mouse is not in scroll dragDevices"
fi

WHEEL_SHIM=""
if [ -d "$TARGET_DIR/web" ]; then
  WHEEL_SHIM="$(grep -lE "addEventListener\\([[:space:]]*['\"]wheel['\"]" "$TARGET_DIR"/web/*.js 2>/dev/null | head -n 1)"
fi
if [ -n "$WHEEL_SHIM" ]; then
  check_pass "Page-level wheel shim present ($(basename "$WHEEL_SHIM"))"
  if lib_has 'SmoothWheelScroll|SmoothScrollController|SmoothScrollPosition' && ! lib_has '__[A-Za-z]*SmoothWheel|isSmoothWheelShimActive|pageShimActive'; then
    check_warn "Double wheel smoothing" \
      "A page-level wheel shim and a widget-level smoother both exist, but no Dart code reads the shim's page flag. The engine classifies the shim's synthetic events as trackpad, so filtering by PointerDeviceKind cannot detect it — read the flag via dart:js_interop or the distance is eased twice."
  fi
elif lib_has 'SmoothScrollController|SmoothScrollPosition|SmoothWheelScroller|pointerScroll[ (]'; then
  check_pass "Smoothed wheel/trackpad scrolling implemented"
else
  check_warn "Smooth scrolling" \
    "Flutter applies raw wheel deltas synchronously (discrete ticks). There is no framework hook; ease app-wide with a page-level JS wheel shim (examples/smooth_wheel_shim.js) or per view with a coalescing scroller (references/scroll-architecture.md), respecting reduced motion."
fi

if lib_has 'thumbVisibility:[[:space:]]*(const[[:space:]]+)?WidgetStatePropertyAll\(true\)|interactive:[[:space:]]*(const[[:space:]]+)?WidgetStatePropertyAll\(true\)'; then
  check_warn "Global scrollbar visibility/interactivity" \
    "Setting thumbVisibility/interactive globally via ThemeData can crash on any Scrollbar without an attached controller."
else
  check_pass "No unsafe global scrollbar theme"
fi

# --- 3. Text selection & context menu --------------------------------------

echo ""
echo -e "${BLUE}[3/8] Text selection & browser menus${NC}"
HAS_SELECTION_AREA=0
lib_has 'SelectionArea' && HAS_SELECTION_AREA=1

if lib_has 'desktopTextSelectionHandleControls'; then
  check_pass "Desktop text selection handle controls configured"
elif [ "$HAS_SELECTION_AREA" -eq 1 ]; then
  check_warn "SelectionArea handles" \
    "SelectionArea is used without desktopTextSelectionHandleControls. Mouse selections show mobile teardrop pins on desktop/web."
else
  check_info "No SelectionArea found (no selectable content surface)"
fi

if lib_has 'BrowserContextMenu\.enableContextMenu'; then
  check_pass "Native browser context menu is enabled"
elif lib_has 'BrowserContextMenu\.disableContextMenu'; then
  check_info "Browser context menu is explicitly disabled (deliberate copy-protection?)"
else
  check_warn "Browser context menu" \
    "No BrowserContextMenu call. Flutter suppresses the native right-click menu by default; call BrowserContextMenu.enableContextMenu() for copy/search/Inspect — and ensure index.html has no blanket contextmenu preventDefault."
fi

if [ "$HAS_SELECTION_AREA" -eq 1 ] && ! lib_has 'SelectionContainer\.disabled'; then
  check_warn "Selection isolation" \
    "SelectionArea is used but no SelectionContainer.disabled wraps UI chrome. Nav rails/toolbars/buttons will highlight during drag-select."
else
  check_pass "Selection chrome isolation present (or no SelectionArea)"
fi

if lib_has 'textSelectionTheme'; then
  check_pass "Brand text selection theme configured"
else
  check_warn "Text selection theme" \
    "No textSelectionTheme. Selection highlight/handles fall back to stock Material cyan; set cursorColor/selectionColor/selectionHandleColor to brand tokens."
fi

# --- 4. Advanced OS, memory & web build ------------------------------------

echo ""
echo -e "${BLUE}[4/8] OS integration, memory & web build${NC}"
if lib_has 'imageCache\.(clear|clearLiveImages|evict)'; then
  check_pass "Image cache eviction found"
elif lib_has 'imageCache\.maximumSizeBytes|imageCache\.maximumSize'; then
  check_info "Image cache is bounded via maximumSizeBytes (no explicit clear/evict)"
else
  check_warn "Memory management" \
    "No imageCache management. CanvasKit tabs can crash ('Aw, Snap!') on heavy image routes; bound the cache and/or evict on leaving heavy views."
fi

if lib_has 'desktop_drop|super_clipboard|cross_file' || grep -qE 'desktop_drop|super_clipboard' "$TARGET_DIR/pubspec.yaml" 2>/dev/null; then
  check_pass "OS clipboard / drag-and-drop integration detected"
else
  check_warn "OS integration" \
    "Consider desktop_drop (OS file drops) and super_clipboard (rich/image paste) if the app accepts uploads/attachments."
fi

if lib_has 'AutofillGroup|finishAutofillContext'; then
  check_pass "Password manager / autofill support detected"
else
  check_warn "Forms & autofill" \
    "No AutofillGroup. Password managers and browser autofill won't fill or offer to save credentials."
fi

if lib_has 'Future\.delayed\(Duration\.zero\)|Timer\.run\(|scheduleTask\(|web\.Worker\('; then
  check_pass "Event-loop yielding / Web Worker usage detected"
else
  check_warn "Concurrency" \
    "No event-loop yielding or Web Worker found. Heavy synchronous work freezes the single web thread (which also renders on CanvasKit / single-threaded Skwasm). Chunk with Future.delayed(Duration.zero) or use a JS Web Worker."
fi
if lib_has 'Isolate\.(run|spawn)'; then
  check_info "Isolate.run/Isolate.spawn used — both throw UnsupportedError on web; make sure web code paths never reach them (compute() on web runs on the main thread)"
fi

SW_FILE="$TARGET_DIR/web/flutter_service_worker.js"
if [ -f "$SW_FILE" ]; then
  if grep -Fq 'registration.unregister' "$SW_FILE" 2>/dev/null; then
    check_info "Service worker is a deliberate self-destruct worker (purges stale caches)"
  elif html_has 'serviceWorker.*(unregister|register)|disableServiceWorkers'; then
    check_warn "Service worker mismatch" \
      "web/flutter_service_worker.js exists but index.html manages service workers separately. Confirm this is intentional."
  else
    check_info "Service worker present (verify it is deliberate: Flutter 3.29+ does not manage one)"
  fi
else
  check_info "No service worker (Flutter 3.29+: bring your own, e.g. Workbox)"
fi

if [ -f "$TARGET_DIR/web/flutter_bootstrap.js" ]; then
  check_pass "Custom flutter_bootstrap.js present"
else
  check_info "Default Flutter bootstrap (no custom loading UI / wasm fallback logic)"
fi

# --- 5. URLs & navigation --------------------------------------------------

echo ""
echo -e "${BLUE}[5/8] URLs & navigation${NC}"
if lib_has 'usePathUrlStrategy|PathUrlStrategy|setUrlStrategy'; then
  check_pass "Path URL strategy configured (no '#' routes)"
else
  check_warn "URL strategy" \
    "No PathUrlStrategy. URLs keep '#/...' hashes and are less shareable/indexable; servers must rewrite unknown paths to index.html."
fi

if lib_has 'Link\(|url_launcher/link'; then
  check_pass "Anchor-based Link widget used (middle-click / open-in-new-tab works)"
else
  check_warn "Middle-click / open in new tab" \
    "No url_launcher Link widget. GestureDetector-only links have no <a href>, so middle-click and 'open in new tab' do nothing."
fi

if lib_has 'Title\(|onGenerateTitle|setApplicationSwitcherDescription|webSeoSetDocumentTitle|document\.title'; then
  check_pass "Document title is synchronized with routes"
else
  check_warn "Document title" \
    "No per-route title updates. Multiple tabs are indistinguishable; use Title/onGenerateTitle or set document.title on route change."
fi

# --- 6. Accessibility ----------------------------------------------------

echo ""
echo -e "${BLUE}[6/8] Accessibility${NC}"
if lib_has 'ensureSemantics|Semantics\(|SemanticsRole|MergeSemantics|SemanticsService'; then
  check_pass "Semantics usage detected"
else
  check_warn "Semantics" \
    "No explicit Semantics usage. Web semantics is OFF by default (behind the 'Enable accessibility' button); add Semantics labels/roles so screen readers and crawlers see structure."
fi

if lib_has 'disableAnimations|reducedMotion|MediaQuery\.of\([^)]*\)\.disableAnimations'; then
  check_pass "Reduced-motion / disableAnimations respected"
else
  check_warn "Reduced motion" \
    "No reduced-motion handling. On web MediaQuery.disableAnimations mirrors prefers-reduced-motion; gate heavy/looping animation on it."
fi

# --- 7. Lifecycle, offline & multi-tab --------------------------------------

echo ""
echo -e "${BLUE}[7/8] Lifecycle, offline & multi-tab${NC}"
if lib_has 'BroadcastChannel|StorageEvent|addEventListener\(["'"'"']storage|SharedPreferences.*onChange'; then
  check_pass "Cross-tab / storage synchronization detected"
else
  check_warn "Multi-tab sync" \
    "No BroadcastChannel/storage sync. Logging out or changing cart/state in one tab won't update others."
fi

if lib_has 'Connectivity|onConnectivityChanged|connectivity_plus'; then
  check_pass "Connectivity / offline handling detected"
else
  check_warn "Offline handling" \
    "No connectivity listener. Show an offline banner and disable submit actions instead of raw socket errors."
fi

if lib_has 'WidgetsBindingObserver|didChangeAppLifecycleState|visibilitychange'; then
  check_pass "App lifecycle handling detected"
else
  check_warn "Web lifecycle / visibility" \
    "No lifecycle handling. On web, hidden tabs stop painting but keep firing Timers — pause video/audio/animations on inactive/hidden."
fi

# --- 8. Performance, boot critical path & delivery ------------------------

echo ""
echo -e "${BLUE}[8/8] Performance, boot critical path & delivery${NC}"
BUILD_INDEX="$TARGET_DIR/build/web/index.html"

# 8a. Non-metadata elements inside <head> close it early (CSP meta etc. fall into body).
if [ -f "$INDEX_HTML" ]; then
  HEAD_INTRUDERS="$(html_tag_stream "$INDEX_HTML" | awk '
    { name = ""; if (match($0, /^\/?[A-Za-z!][A-Za-z0-9-]*/)) name = tolower(substr($0, RSTART, RLENGTH)) }
    name == "script" { inscript = 1; next }
    name == "/script" { inscript = 0; next }
    inscript { next }
    name == "style" { instyle = 1; next }
    name == "/style" { instyle = 0; next }
    instyle { next }
    name == "head" { inhead = 1; next }
    name == "/head" || name == "body" { exit }
    inhead && name != "" && name !~ /^\// && name !~ /^(meta|link|title|\/title|base|noscript|\/noscript|template|\/template|!doctype)$/ { print name }
  ' | sort -u | tr '\n' ' ')"
  if [ -n "$HEAD_INTRUDERS" ]; then
    check_warn "Non-metadata element in <head>" \
      "Found <${HEAD_INTRUDERS% }> inside <head>. The parser closes <head> at the first non-metadata element, so everything after it (preloads, CSP <meta>) lands in <body>. Move visual markup to <body>; inject only link/style/script into <head>."
  else
    check_pass "<head> contains only metadata elements"
  fi
fi

# 8b. Splash / LCP <img> sizing.
if [ -f "$INDEX_HTML" ]; then
  IMG_TAGS="$(html_tag_stream "$INDEX_HTML" | grep -Ei '^img[[:space:]]' || true)"
  if [ -n "$IMG_TAGS" ]; then
    UNSIZED="$(printf '%s\n' "$IMG_TAGS" | count_unsized_imgs)"
    LAZY="$(printf '%s\n' "$IMG_TAGS" | grep -Eic 'loading[[:space:]]*=[[:space:]]*["'"'"']?lazy|decoding[[:space:]]*=[[:space:]]*["'"'"']?async' || true)"
    BUILD_SIZED=0
    if [ "$UNSIZED" -gt 0 ] && [ -f "$BUILD_INDEX" ]; then
      BUILD_IMGS="$(html_tag_stream "$BUILD_INDEX" | grep -Ei '^img[[:space:]]' || true)"
      if [ -n "$BUILD_IMGS" ] && [ "$(printf '%s\n' "$BUILD_IMGS" | count_unsized_imgs)" -eq 0 ]; then
        BUILD_SIZED=1
      fi
    fi
    if [ "$UNSIZED" -gt 0 ] && [ "$BUILD_SIZED" -eq 1 ]; then
      check_info "Splash <img> sized only in build/web/index.html (annotated at build/deploy time) — keep that step in the pipeline"
    elif [ "$UNSIZED" -gt 0 ]; then
      check_warn "Splash <img> dimensions" \
        "$UNSIZED <img> tag(s) in web/index.html lack width/height. The HTML splash image is usually the LCP element: give it explicit width/height (1x intrinsic size) and fetchpriority=\"high\"."
    else
      check_pass "All <img> tags in index.html have explicit width/height"
    fi
    if [ "$LAZY" -gt 0 ]; then
      check_warn "Splash <img> loading hints" \
        "$LAZY <img> tag(s) use loading=lazy or decoding=async. On the LCP splash image both can delay the LCP paint — remove them there."
    fi
  else
    check_info "No <img> in web/index.html (no HTML splash image)"
  fi
fi

# 8c. robots.txt directives Lighthouse's robots-txt audit doesn't know.
ROBOTS="$TARGET_DIR/web/robots.txt"
if [ -f "$ROBOTS" ]; then
  ROBOTS_BAD="$(sed 's/#.*//' "$ROBOTS" | tr -d '\r' | awk '
    /^[[:space:]]*$/ { next }
    {
      line = $0
      if (index(line, ":") == 0) { print "(no colon): " substr(line, 1, 40); next }
      d = substr(line, 1, index(line, ":") - 1); gsub(/[[:space:]]/, "", d); d = tolower(d)
      if (d !~ /^(user-agent|allow|disallow|sitemap|crawl-delay|clean-param|host|request-rate|visit-time|noindex)$/) print d
    }' | sort -u)"
  AGENTMAP="$(printf '%s\n' "$ROBOTS_BAD" | grep -x 'agentmap' || true)"
  ROBOTS_BAD="$(printf '%s\n' "$ROBOTS_BAD" | grep -vx 'agentmap' | grep '[^[:space:]]' | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  if [ -n "$ROBOTS_BAD" ]; then
    check_warn "robots.txt directives" \
      "Unrecognized robots.txt line(s): $ROBOTS_BAD. Lighthouse's robots-txt audit fails on non-standard directives (e.g. LLM-Txt:) — keep such hints as # comments."
  else
    check_pass "robots.txt uses only standard directives"
  fi
  if [ -n "$AGENTMAP" ]; then
    check_info "robots.txt has Agentmap: (agentic-browsing discovery) — confirm your Lighthouse version's robots-txt audit accepts it"
  fi
fi

# 8d. sourceMappingURL in the shipped bootstrap pointing at a map that isn't deployed.
BUILD_DIR="$TARGET_DIR/build/web"
if [ -f "$BUILD_DIR/flutter_bootstrap.js" ]; then
  MAP_MISSING=""
  for f in "$BUILD_DIR/flutter_bootstrap.js" "$BUILD_DIR/flutter.js"; do
    [ -f "$f" ] || continue
    for m in $(grep -E '^[[:space:]]*//[#@][[:space:]]*sourceMappingURL=' "$f" 2>/dev/null | sed 's/.*sourceMappingURL=//' | tr -d '\r'); do
      case "$m" in data:*|http*) continue ;; esac
      [ -f "$BUILD_DIR/$m" ] || MAP_MISSING="$MAP_MISSING $(basename "$f")->$m"
    done
  done
  if [ -n "$MAP_MISSING" ]; then
    check_warn "Source map reference without a map" \
      "build/web ships sourceMappingURL comments whose map is not in the build:$MAP_MISSING. The SPA fallback answers with HTML and Lighthouse valid-source-maps fails. Strip the comment at deploy (before any content stamp) or deploy the map."
  else
    check_pass "No dangling sourceMappingURL in build/web bootstrap"
  fi
else
  check_info "No build/web/flutter_bootstrap.js — run after 'flutter build web' to check shipped source-map references"
fi

# 8e. Eager plugin wasm at boot: pdfrxFlutterInitialize() in main/bootstrap without a web guard.
if [ -d "$LIB_DIR" ] && grep -qE '^[[:space:]]*pdfrx[[:space:]]*:' "$TARGET_DIR/pubspec.yaml" 2>/dev/null; then
  EAGER_PDFRX="$(find "$LIB_DIR" -type f \( -name 'main*.dart' -o -name '*bootstrap*.dart' \) 2>/dev/null | while read -r f; do
    awk '
      { line = $0; sub(/\/\/.*$/, "", line) }
      line ~ /pdfrxFlutterInitialize[[:space:]]*\(/ && line !~ /Future|^[[:space:]]*import/ {
        guarded = 0
        for (k = 1; k <= 8; k++) if (prev[k] ~ /kIsWeb|isWeb/) guarded = 1
        if (line ~ /kIsWeb|isWeb/) guarded = 1
        if (!guarded) { print FILENAME ":" NR; exit }
      }
      { for (k = 8; k > 1; k--) prev[k] = prev[k - 1]; prev[1] = line }
    ' "$f"
  done)"
  if [ -n "$EAGER_PDFRX" ]; then
    check_warn "Eager pdfrx init at boot" \
      "pdfrxFlutterInitialize() runs at startup without a web guard ($(echo "$EAGER_PDFRX" | head -n 1 | sed "s#^$TARGET_DIR/##")). On web it starts a worker that downloads/compiles pdfium.wasm on every cold visit. Skip it on web (pdfrx widgets and PdfDocumentRef self-initialize; await it only before direct PdfDocument.open* calls)."
  else
    check_pass "No unguarded pdfrxFlutterInitialize() in main/bootstrap"
  fi
fi

# 8f. Firebase JS SDK modulepreloads (firebase_core_web loads the SDK via import() only after wasm runs).
FB_CORE_ROOT="$(package_root firebase_core_web 2>/dev/null || true)"
if [ -n "$FB_CORE_ROOT" ] && [ -f "$FB_CORE_ROOT/lib/src/firebase_sdk_version.dart" ]; then
  FB_VERSION="$(grep -oE "supportedFirebaseJsSdkVersion[[:space:]]*=[[:space:]]*'[0-9.]+'" "$FB_CORE_ROOT/lib/src/firebase_sdk_version.dart" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -n 1)"
  FB_EXPECTED="firebase-app.js"
  for pkg in $(package_names '^firebase_[a-z_]+_web$' | grep -vx 'firebase_core_web'); do
    PROOT="$(package_root "$pkg" 2>/dev/null || true)"
    [ -d "$PROOT/lib" ] || continue
    for svc in $(find "$PROOT/lib" -name '*.dart' -type f 2>/dev/null | while read -r f; do
        tr '\n' ' ' < "$f" | grep -oE "FirebaseCoreWeb\.registerService\([[:space:]]*'[a-z0-9-]+'" | sed "s/.*'\([a-z0-9-]*\)'/\1/"
      done | sort -u); do
      if [ "$svc" = "firestore" ]; then FB_EXPECTED="$FB_EXPECTED firebase-firestore-pipelines.js"; else FB_EXPECTED="$FB_EXPECTED firebase-$svc.js"; fi
    done
  done
  FB_SRC=""
  for h in "$INDEX_HTML" "$BUILD_INDEX"; do
    [ -f "$h" ] || continue
    if html_tag_stream "$h" | grep -Ei '^link[[:space:]]' | grep -i 'modulepreload' | grep -q 'gstatic\.com/firebasejs/'; then FB_SRC="$h"; break; fi
  done
  if [ -z "$FB_SRC" ]; then
    check_warn "Firebase JS SDK modulepreloads" \
      "firebase_core_web $FB_VERSION is used but neither web/index.html nor build/web/index.html modulepreloads its bundles. The SDK is import()ed only after the app's wasm runs (firebase-app.js strictly first); if main() awaits Firebase.initializeApp, that chain is on the first-frame path. Generate <link rel=\"modulepreload\" href=\"https://www.gstatic.com/firebasejs/$FB_VERSION/<bundle>\"> (no crossorigin) for: $FB_EXPECTED. (Injected only at deploy time? Check the deployed HTML instead.)"
  else
    FB_LINKS="$(html_tag_stream "$FB_SRC" | grep -Ei '^link[[:space:]]' | grep -i 'modulepreload' | grep 'gstatic\.com/firebasejs/')"
    FB_FOUND_VERSIONS="$(printf '%s\n' "$FB_LINKS" | grep -oE 'firebasejs/[0-9.]+/' | sort -u | sed 's#firebasejs/##; s#/##' | tr '\n' ' ')"
    FB_MISSING=""
    for b in $FB_EXPECTED; do
      printf '%s\n' "$FB_LINKS" | grep -q "firebasejs/$FB_VERSION/$b" || FB_MISSING="$FB_MISSING $b"
    done
    if [ "${FB_FOUND_VERSIONS% }" != "$FB_VERSION" ]; then
      check_warn "Stale Firebase modulepreloads" \
        "$(basename "$(dirname "$FB_SRC")")/index.html preloads Firebase ${FB_FOUND_VERSIONS% } but firebase_core_web resolves $FB_VERSION. Stale preloads waste bandwidth and leave the real bundles serial — derive the version from firebase_sdk_version.dart at build time."
    elif [ -n "$FB_MISSING" ]; then
      check_warn "Incomplete Firebase modulepreloads" \
        "Missing modulepreload for:$FB_MISSING (registered services in the resolved firebase_*_web packages)."
    else
      check_pass "Firebase JS SDK $FB_VERSION bundles are modulepreloaded ($(basename "$(dirname "$FB_SRC")")/index.html)"
    fi
    if printf '%s\n' "$FB_LINKS" | grep -qi 'crossorigin'; then
      check_warn "Firebase modulepreload crossorigin" \
        "Firebase modulepreloads carry a crossorigin attribute; the SDK's dynamic import() is credentials-mode same-origin, so a mismatched preload is fetched twice. Use bare <link rel=\"modulepreload\" href=...>."
    fi
  fi
fi

# --- summary ---------------------------------------------------------------

echo ""
echo -e "${BLUE}=== Audit Summary ===${NC}"
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}✓ 0 critical native-web fidelity errors.${NC}"
else
  echo -e "${RED}✗ $ERRORS critical issue(s). Fix them before shipping.${NC}"
fi
if [ "$WARNINGS" -gt 0 ]; then
  echo -e "${YELLOW}ℹ $WARNINGS recommendation(s) to improve native feel.${NC}"
fi

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

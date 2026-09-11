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

echo -e "${BLUE}=== Flutter Web Native Fidelity Audit (v2) ===${NC}"
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

echo -e "${BLUE}[1/7] HTML & CSS (web/index.html)${NC}"
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
echo -e "${BLUE}[2/7] Scroll architecture${NC}"
if drag_devices_uses_mouse; then
  check_fail "Scroll drag devices" \
    "PointerDeviceKind.mouse is included in a scroll dragDevices set. Mouse-drag then pans the page instead of selecting text." \
    "Exclude PointerDeviceKind.mouse from dragDevices; keep wheel/trackpad scrolling and scrollbar dragging."
else
  check_pass "Mouse is not in scroll dragDevices"
fi

if lib_has 'SmoothScrollController|SmoothScrollPosition|SmoothWheelScroller|pointerScroll[ (]'; then
  check_pass "Smoothed wheel/trackpad scrolling implemented"
else
  check_warn "Smooth scrolling" \
    "Flutter applies raw wheel deltas synchronously (discrete ticks). There is no global first-party hook — use a per-view interceptor that coalesces deltas into one eased target (see references/scroll-architecture.md), respecting reduced motion."
fi

if lib_has 'thumbVisibility:[[:space:]]*(const[[:space:]]+)?WidgetStatePropertyAll\(true\)|interactive:[[:space:]]*(const[[:space:]]+)?WidgetStatePropertyAll\(true\)'; then
  check_warn "Global scrollbar visibility/interactivity" \
    "Setting thumbVisibility/interactive globally via ThemeData can crash on any Scrollbar without an attached controller."
else
  check_pass "No unsafe global scrollbar theme"
fi

# --- 3. Text selection & context menu --------------------------------------

echo ""
echo -e "${BLUE}[3/7] Text selection & browser menus${NC}"
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
echo -e "${BLUE}[4/7] OS integration, memory & web build${NC}"
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

if lib_has 'Isolate\.run|Isolate\.spawn|compute\(|Future\.delayed\(Duration\.zero\)'; then
  check_pass "Concurrency / event-loop yielding detected"
else
  check_warn "Concurrency" \
    "No Isolate.run/compute/event-loop yield. Heavy synchronous work freezes the single web thread. Note: isolates on web map to Web Workers with real startup cost — chunk or defer."
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
echo -e "${BLUE}[5/7] URLs & navigation${NC}"
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
echo -e "${BLUE}[6/7] Accessibility${NC}"
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
echo -e "${BLUE}[7/7] Lifecycle, offline & multi-tab${NC}"
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

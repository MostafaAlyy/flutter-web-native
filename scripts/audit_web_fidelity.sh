#!/usr/bin/env bash
# audit_web_fidelity.sh
# Scans a Flutter project for web fidelity anti-patterns.
# Usage: ./audit_web_fidelity.sh [path_to_flutter_project]

set -euo pipefail

TARGET_DIR="${1:-.}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Flutter Web Native Fidelity Audit ===${NC}"
echo "Target: $TARGET_DIR"
echo ""

ERRORS=0
WARNINGS=0

check_pass() {
  echo -e "  [${GREEN}PASS${NC}] $1"
}

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

INDEX_HTML="$TARGET_DIR/web/index.html"

echo -e "${BLUE}[1/4] Checking HTML & CSS (web/index.html)...${NC}"
if [ -f "$INDEX_HTML" ]; then
  # 1. Viewport zoom lockout
  if grep -E "user-scalable\s*=\s*no|maximum-scale\s*=\s*1(\.0)?" "$INDEX_HTML" >/dev/null 2>&1; then
    check_fail "Viewport zoom accessibility" \
      "user-scalable=no or maximum-scale=1.0 blocks browser zoom & pinch-to-zoom." \
      "Change viewport meta to: <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
  else
    check_pass "Viewport zoom is enabled for accessibility"
  fi

  # 2. Canvas dimension override
  if grep -E "flutter-view\s+canvas.*width|flutter-view\s+canvas.*height" "$INDEX_HTML" >/dev/null 2>&1; then
    check_fail "Canvas buffer sizing" \
      "CSS width/height on 'flutter-view canvas' overrides dynamic DPR, causing blurriness and click misalignments." \
      "Remove CSS rules targeting 'flutter-view canvas'. Set width/height on 'flutter-view' host only."
  else
    check_pass "No destructive CSS overrides on 'flutter-view canvas'"
  fi

  # 3. Touch action
  if grep -E "touch-action\s*:\s*.*pinch-zoom" "$INDEX_HTML" >/dev/null 2>&1; then
    check_pass "touch-action: pan-x pan-y pinch-zoom configured"
  else
    check_warn "Touch action configuration" \
      "Consider setting 'touch-action: pan-x pan-y pinch-zoom;' on 'flutter-view' to assist browser gesture dispatch."
  fi

  # 4. Overflow lock
  if grep -E "overflow(-x)?\s*:\s*hidden" "$INDEX_HTML" >/dev/null 2>&1; then
    check_warn "Body overflow locks" \
      "Found 'overflow: hidden' or 'overflow-x: hidden' in index.html, which may freeze visual viewport panning when zoomed."
  else
    check_pass "Body overflow does not lock visual viewport panning"
  fi
else
  check_warn "web/index.html not found" "Skipping web/index.html checks."
fi

echo ""
echo -e "${BLUE}[2/4] Checking Scroll Architecture...${NC}"

# Check for mouse in dragDevices
if grep -rnE "PointerDeviceKind\.mouse" "$TARGET_DIR/lib" >/dev/null 2>&1; then
  if grep -rnE "dragDevices.*PointerDeviceKind\.mouse" "$TARGET_DIR/lib" >/dev/null 2>&1; then
    check_fail "Scroll drag devices" \
      "PointerDeviceKind.mouse is included in scroll dragDevices! This breaks mouse text selection across the website." \
      "Exclude mouse from dragDevices in your custom ScrollBehavior."
  else
    check_pass "Mouse is not in scroll dragDevices"
  fi
else
  check_pass "Mouse is not in scroll dragDevices"
fi

# Check for SmoothScrollController usage
if grep -rnE "SmoothScrollController|SmoothScrollPosition" "$TARGET_DIR/lib" >/dev/null 2>&1; then
  check_pass "SmoothScrollController is implemented"
else
  check_warn "Smooth scrolling" \
    "Default Flutter wheel scrolling produces discrete stepped jumps. Consider adopting SmoothScrollController."
fi

echo ""
echo -e "${BLUE}[3/4] Checking Text Selection & Menus...${NC}"

# Check for desktop text selection handles
if grep -rnE "desktopTextSelectionHandleControls" "$TARGET_DIR/lib" >/dev/null 2>&1; then
  check_pass "Desktop text selection handle controls configured"
else
  if grep -rnE "SelectionArea" "$TARGET_DIR/lib" >/dev/null 2>&1; then
    check_warn "SelectionArea handles" \
      "SelectionArea is used without desktopTextSelectionHandleControls. Mobile teardrop pins may appear on desktop."
  fi
fi

# Check for BrowserContextMenu
if grep -rnE "BrowserContextMenu\.enableContextMenu" "$TARGET_DIR/lib" >/dev/null 2>&1; then
  check_pass "Native browser context menu is enabled"
else
  check_warn "Browser context menu" \
    "Consider calling BrowserContextMenu.enableContextMenu() so right-clicking copy/inspect works natively."
fi

# Check for selection isolation
if grep -rnE "SelectionContainer\.disabled" "$TARGET_DIR/lib" >/dev/null 2>&1; then
  check_pass "SelectionContainer.disabled is used to shield UI chrome"
else
  check_warn "Selection isolation" \
    "No SelectionContainer.disabled found. UI chrome (nav rails, toolbars, buttons) may be highlighted during drag selection."
fi

echo ""
echo -e "${BLUE}[4/4] Checking URLs & Navigation...${NC}"

# Check for usePathUrlStrategy
if grep -rnE "usePathUrlStrategy" "$TARGET_DIR/lib" >/dev/null 2>&1; then
  check_pass "Path URL strategy is configured (no hash # routes)"
else
  check_warn "URL strategy" \
    "Consider adding usePathUrlStrategy() in main() to eliminate '#' hash routes in URLs."
fi

echo ""
echo -e "${BLUE}=== Audit Summary ===${NC}"
if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}✓ Great job! Zero critical native web fidelity errors found.${NC}"
else
  echo -e "${RED}✗ Found $ERRORS critical issue(s). Review recommendations above.${NC}"
fi

if [ $WARNINGS -gt 0 ]; then
  echo -e "${YELLOW}ℹ Found $WARNINGS recommendation(s) to improve desktop polish.${NC}"
fi

exit $ERRORS

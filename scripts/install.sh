#!/usr/bin/env bash
# install.sh
# Installs the flutter-web-native skill into active AI assistant directories.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_NAME="flutter-web-native"

echo "Installing skill '$SKILL_NAME' from: $SKILL_DIR"

INSTALL_TARGETS=(
  "$HOME/.agents/skills/$SKILL_NAME"
  "$HOME/.gemini/antigravity/global_skills/$SKILL_NAME"
  "$HOME/.gemini/skills/$SKILL_NAME"
)

for TARGET in "${INSTALL_TARGETS[@]}"; do
  TARGET_PARENT="$(dirname "$TARGET")"
  if [ -d "$TARGET_PARENT" ]; then
    rm -rf "$TARGET"
    ln -s "$SKILL_DIR" "$TARGET"
    echo "  ✓ Linked into: $TARGET"
  else
    echo "  - Skipped (parent directory does not exist): $TARGET_PARENT"
  fi
done

echo ""
echo "Installation complete. Skill is active and ready to use."

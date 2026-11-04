#!/usr/bin/env bash
set -euo pipefail

LABEL="com.aliihsan.oldphonedeck"
LAUNCH_DIR="${LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
PLIST="$LAUNCH_DIR/$LABEL.plist"

if [[ "${LAUNCHD_DRY_RUN:-0}" != "1" ]] && command -v launchctl >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
fi

rm -f "$PLIST"
echo "stopped"

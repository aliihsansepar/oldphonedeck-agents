#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$ROOT/.build/release/oldphonedeck"
LABEL="com.aliihsan.oldphonedeck"
LAUNCH_DIR="${LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
PLIST="$LAUNCH_DIR/$LABEL.plist"
LOG="$HOME/Library/Logs/oldphonedeck.log"

if [[ ! -x "$BIN" ]]; then
  echo "Build first: cd \"$ROOT\" && swift build -c release" >&2
  exit 1
fi

mkdir -p "$LAUNCH_DIR" "$(dirname "$LOG")"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN</string>
    <string>--port</string>
    <string>8045</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST

if [[ "${LAUNCHD_DRY_RUN:-0}" != "1" ]]; then
  if command -v launchctl >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
  fi
fi

echo "LaunchAgent: $PLIST"
echo "Log: $LOG"
echo "Stop: launchctl bootout gui/$(id -u) \"$PLIST\""

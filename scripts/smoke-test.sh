#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$ROOT/.build/release/oldphonedeck"
PORT="${SMOKE_PORT:-18045}"
LOG="$(mktemp -t oldphonedeck-smoke.XXXXXX.log)"

if [[ ! -x "$BIN" ]]; then
  echo "Build first: cd \"$ROOT\" && swift build -c release" >&2
  exit 1
fi

"$BIN" --port "$PORT" >"$LOG" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true; rm -f "$LOG"' EXIT

sleep 1
TOKEN=$(cat "$HOME/.oldphonedeck/token")
BASE="http://127.0.0.1:$PORT"

curl --max-time 5 -fsS "$BASE/agents?k=$TOKEN" | jq -e '.sources and (.agents | type == "array")' >/dev/null
test "$(curl --max-time 5 -s -o /dev/null -w '%{http_code}' "$BASE/agents")" = "403"

ID=$(curl --max-time 5 -fsS "$BASE/agents?k=$TOKEN" | jq -r '.agents[0].id // empty')
if [[ -n "$ID" ]]; then
  test "$(curl --max-time 5 -s -o /dev/null -w '%{http_code}' -X POST "$BASE/focus?k=$TOKEN" --data-urlencode "id=$ID")" = "200"
fi
test "$(curl --max-time 5 -s -o /dev/null -w '%{http_code}' -X POST "$BASE/focus?k=$TOKEN" --data 'id=nope')" = "404"

echo "smoke ok"

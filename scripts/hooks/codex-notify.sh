#!/usr/bin/env bash
# Codex CLI notify hook → Tockk.
#
# Codex invokes this script with a JSON payload as the final arg (or on stdin
# depending on version). Safest approach: read both and prefer $1 if it parses.
#
# Codex `agent-turn-complete` payload shape (as of Codex CLI 0.x):
#   {
#     "type": "agent-turn-complete",
#     "turn-id": "...",
#     "input-messages": ["..."],
#     "last-assistant-message": "..."
#   }
#
# Install by adding to ~/.codex/config.toml:
#   notify = ["/bin/bash", "/path/to/tockk/scripts/hooks/codex-notify.sh"]
set -euo pipefail

CWD="${CODEX_CWD:-$PWD}"
SOCKET="${HOME}/Library/Application Support/Tockk/tockk.sock"
SOURCE_APP_BUNDLE_ID="${__CFBundleIdentifier:-}"

previous_notify=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --previous-notify)
      previous_notify="${2:-}"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

# Accept payload from arg or stdin.
payload="${1:-}"
if [[ -z "$payload" ]]; then
  payload="$(cat 2>/dev/null || true)"
fi

# Diagnostic trail for payload shape investigation. Disable by unsetting
# TOCKK_CODEX_DEBUG_LOG. Kept opt-in-by-default here because the log size
# is trivial (a few hundred bytes per turn) and the blind spot when Codex
# changes payload shape without docs has bitten us twice already.
TOCKK_CODEX_DEBUG_LOG="${TOCKK_CODEX_DEBUG_LOG:-$HOME/Library/Logs/Tockk/codex-notify.log}"
if [[ -n "$TOCKK_CODEX_DEBUG_LOG" ]]; then
  mkdir -p "$(dirname "$TOCKK_CODEX_DEBUG_LOG")" 2>/dev/null || true
  {
    printf '=== %s pid=%s ===\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$$"
    printf 'argv:'
    for a in "$@"; do printf ' %q' "$a"; done
    printf '\npayload: %s\n\n' "$payload"
  } >>"$TOCKK_CODEX_DEBUG_LOG" 2>/dev/null || true
fi

if [[ ! -S "$SOCKET" ]]; then
  # Socket missing — skip Tockk emit but still chain previous_notify below.
  :
else
  PAYLOAD="$payload" CWD="$CWD" SOURCE_APP_BUNDLE_ID="$SOURCE_APP_BUNDLE_ID" \
    python3 <<'PY' | nc -U "$SOCKET" >/dev/null 2>&1 || true
import json
import os

cwd = os.environ["CWD"]
raw = os.environ.get("PAYLOAD", "") or ""

try:
    data = json.loads(raw) if raw.strip() else {}
except Exception:
    data = {}

# Prefer the cwd embedded in the payload itself. Codex Desktop spawns the
# notify script with its own working directory (typically inside the app
# bundle), so `$PWD` and `$CODEX_CWD` both resolve to "codex"-ish paths
# and the notification header ends up looking like `codex / codex`
# instead of `codex / <project>`.
if isinstance(data, dict):
    payload_cwd = data.get("cwd") or data.get("workspace-root") or ""
    if isinstance(payload_cwd, str) and payload_cwd:
        cwd = payload_cwd

# Codex sends 'last-assistant-message' on agent-turn-complete; older/other
# payloads may use 'title' or 'message' — honour either.
last_msg = ""
if isinstance(data, dict):
    last_msg = (
        data.get("last-assistant-message")
        or data.get("title")
        or data.get("message")
        or ""
    )

# Title / summary promotion (mirrors claude-stop.sh):
#   • last-assistant-message present → first meaningful line → title,
#                                      rest → summary.
#   • otherwise → generic "Done", no summary.
title = "Done"
summary = None
if last_msg:
    lines = [ln.strip() for ln in last_msg.splitlines() if ln.strip()]
    if lines:
        head = lines[0]
        if len(head) > 80:
            head = head[:79].rstrip() + "\u2026"
        title = head
        rest = "\n".join(lines[1:]).strip()
        if rest:
            if len(rest) > 220:
                rest = rest[:217].rstrip() + "\u2026"
            summary = rest

doc = {
    "agent": "codex",
    "project": os.path.basename(cwd) or "codex",
    "status": "success",
    "title": title,
    "cwd": cwd,
}
if summary:
    doc["summary"] = summary

source_app = os.environ.get("SOURCE_APP_BUNDLE_ID", "").strip()
if source_app:
    doc["sourceAppBundleId"] = source_app

print(json.dumps(doc, ensure_ascii=False))
PY
fi

if [[ -n "$previous_notify" ]]; then
  PREVIOUS_NOTIFY="$previous_notify" PAYLOAD="$payload" python3 - <<'PY' >/dev/null 2>&1 || true
import json
import os
import subprocess

try:
    command = json.loads(os.environ["PREVIOUS_NOTIFY"])
except Exception:
    command = None

if isinstance(command, list) and all(isinstance(item, str) for item in command):
    payload = os.environ.get("PAYLOAD", "")
    if payload:
        command = [*command, payload]
    subprocess.run(command, check=False)
PY
fi

exit 0

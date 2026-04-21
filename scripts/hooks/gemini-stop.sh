#!/usr/bin/env bash
# Gemini CLI AfterAgent hook → Tockk.
#
# Install by adding to ~/.gemini/settings.json:
#   {
#     "hooks": {
#       "AfterAgent": [
#         {
#           "matcher": "*",
#           "hooks": [
#             { "type": "command", "command": "/bin/bash /path/to/tockk/scripts/hooks/gemini-stop.sh" }
#           ]
#         }
#       ]
#     }
#   }
#
# Gemini CLI sends stdin JSON on AfterAgent:
#   { "session_id", "transcript_path", "cwd", "hook_event_name",
#     "timestamp", "prompt", "prompt_response", "stop_hook_active" }
# Env vars provided by Gemini:
#   GEMINI_PROJECT_DIR, GEMINI_CWD, GEMINI_SESSION_ID
# (CLAUDE_PROJECT_DIR is a compatibility alias Gemini also sets.)
set -euo pipefail

CWD="${GEMINI_PROJECT_DIR:-${GEMINI_CWD:-${CLAUDE_PROJECT_DIR:-$PWD}}}"
SOCKET="${HOME}/Library/Application Support/Tockk/tockk.sock"

if [[ ! -S "$SOCKET" ]]; then exit 0; fi

STDIN_JSON="$(cat || true)"
SOURCE_APP_BUNDLE_ID="${__CFBundleIdentifier:-}"

export CWD STDIN_JSON SOURCE_APP_BUNDLE_ID

# Gemini's AfterAgent fires recursively if our script rewrites the transcript;
# stop_hook_active=true signals we're inside a re-entry and must exit cleanly.
# See Claude Code's identical `stop_hook_active` convention.
python3 <<'PY' | nc -U "$SOCKET" >/dev/null 2>&1 || true
import json
import os

cwd = os.environ["CWD"]
raw = os.environ.get("STDIN_JSON", "") or ""

prompt_response = ""
transcript_path = ""
stop_hook_active = False
try:
    hook = json.loads(raw) if raw.strip() else {}
    prompt_response = hook.get("prompt_response", "") or ""
    transcript_path = hook.get("transcript_path", "") or ""
    stop_hook_active = bool(hook.get("stop_hook_active", False))
except Exception:
    pass

if stop_hook_active:
    raise SystemExit(0)

FENCE = chr(96) * 3


def clean_and_truncate(text: str):
    if not text:
        return None
    cleaned = text.strip()
    if FENCE in cleaned:
        parts = cleaned.split(FENCE)
        cleaned = "".join(p for i, p in enumerate(parts) if i % 2 == 0).strip()
    lines = [ln.rstrip() for ln in cleaned.splitlines() if ln.strip()]
    cleaned = "\n".join(lines[:4]) if lines else ""
    if len(cleaned) > 220:
        cleaned = cleaned[:217].rstrip() + "\u2026"
    return cleaned or None


summary_text = clean_and_truncate(prompt_response)

# Fallback: when prompt_response is empty (rare — some tool-only turns),
# read the final assistant line from the transcript. Mirrors
# claude-stop.sh's transcript-tail logic.
if not summary_text and transcript_path and os.path.isfile(transcript_path):
    try:
        last_text = None
        with open(transcript_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except Exception:
                    continue
                if entry.get("type") != "assistant":
                    continue
                msg = entry.get("message") or {}
                content = msg.get("content") or []
                if not isinstance(content, list):
                    continue
                pieces = []
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "text":
                        t = block.get("text") or ""
                        if t.strip():
                            pieces.append(t)
                if pieces:
                    last_text = "\n".join(pieces)
        summary_text = clean_and_truncate(last_text)
    except Exception:
        summary_text = None

title_detail_summary = summary_text
if summary_text:
    lines = [ln for ln in summary_text.splitlines() if ln.strip()]
    head = lines[0].strip() if lines else ""
    if len(head) > 80:
        head = head[:79].rstrip() + "\u2026"
    title = head or "Done"
    rest = "\n".join(lines[1:]).strip()
    title_detail_summary = rest or None
else:
    title = "Done"

doc = {
    "agent": "gemini-cli",
    "project": os.path.basename(cwd) or "gemini-cli",
    "status": "success",
    "title": title,
    "cwd": cwd,
}
if title_detail_summary:
    doc["summary"] = title_detail_summary

source_app = os.environ.get("SOURCE_APP_BUNDLE_ID", "").strip()
if source_app:
    doc["sourceAppBundleId"] = source_app

print(json.dumps(doc, ensure_ascii=False))
PY

exit 0

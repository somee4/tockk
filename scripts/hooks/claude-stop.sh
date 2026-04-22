#!/usr/bin/env bash
# Claude Code Stop hook → Tockk.
#
# Install by adding to ~/.claude/settings.json:
#   {
#     "hooks": {
#       "Stop": [
#         { "command": "/path/to/tockk/scripts/hooks/claude-stop.sh" }
#       ]
#     }
#   }
#
# Claude Code sends stdin JSON on Stop:
#   { "session_id", "transcript_path", "hook_event_name", "stop_hook_active" }
# Env vars also provided:
#   CLAUDE_PROJECT_DIR  — the project directory
set -euo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
SOCKET="${HOME}/Library/Application Support/Tockk/tockk.sock"

if [[ ! -S "$SOCKET" ]]; then exit 0; fi

# Capture stdin (Claude Code hook JSON) so Python can read it.
STDIN_JSON="$(cat || true)"

# Diagnostic trail — mirrors codex-notify.sh. Keeps the raw stdin payload
# and transcript path so we can tell "no summary" apart from "hook didn't
# fire" after the fact. Opt-out by unsetting TOCKK_CLAUDE_DEBUG_LOG.
TOCKK_CLAUDE_DEBUG_LOG="${TOCKK_CLAUDE_DEBUG_LOG:-$HOME/Library/Logs/Tockk/claude-stop.log}"
if [[ -n "$TOCKK_CLAUDE_DEBUG_LOG" ]]; then
  mkdir -p "$(dirname "$TOCKK_CLAUDE_DEBUG_LOG")" 2>/dev/null || true
  {
    printf '=== %s pid=%s ===\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$$"
    printf 'cwd: %s\n' "$CWD"
    printf 'stdin: %s\n\n' "$STDIN_JSON"
  } >>"$TOCKK_CLAUDE_DEBUG_LOG" 2>/dev/null || true
fi

export CWD STDIN_JSON

# IMPORTANT: do NOT wrap this heredoc in $(...). Bash's command-substitution
# parser still interprets backticks inside a single-quoted heredoc body,
# which breaks Python code containing triple-backtick literals. Stream the
# payload straight into `nc` instead.
python3 <<'PY' | nc -U "$SOCKET" >/dev/null 2>&1 || true
import json
import os

cwd = os.environ["CWD"]
raw = os.environ.get("STDIN_JSON", "") or ""

transcript_path = ""
stdin_last_assistant = ""
try:
    hook = json.loads(raw) if raw.strip() else {}
    transcript_path = hook.get("transcript_path", "") or ""
    # Recent Claude Code versions include the assistant's final reply
    # directly in the Stop hook payload. Prefer this over re-parsing the
    # jsonl transcript, which races with disk flushing — the hook often
    # fires before the assistant turn (and its surrounding attachments)
    # have been written out, producing empty summaries and blank titles.
    stdin_last_assistant = hook.get("last_assistant_message", "") or ""
except Exception:
    transcript_path = ""
    stdin_last_assistant = ""

FENCE = chr(96) * 3  # avoid literal backticks in source to dodge shell quirks


def summarize_last_assistant(path: str):
    """Return (summary, edits_count, duration_ms) from the transcript tail."""
    if not path or not os.path.isfile(path):
        return None, 0, None

    last_assistant_text = None
    last_turn_tool_files: set = set()
    current_turn_files: set = set()
    in_assistant_turn = False

    # Track only the CURRENT turn's duration: from the most recent user
    # message timestamp to the final assistant message timestamp. Using the
    # first/last ts of the entire file measures session age, which produces
    # misleading multi-hour durations for long-lived sessions.
    pending_user_ts = None
    turn_start_ts = None
    turn_end_ts = None

    EDIT_TOOLS = {"Edit", "MultiEdit", "Write", "NotebookEdit"}

    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except Exception:
                    continue

                ts = entry.get("timestamp")
                etype = entry.get("type")

                if etype != "assistant":
                    if in_assistant_turn:
                        last_turn_tool_files = current_turn_files
                        current_turn_files = set()
                        in_assistant_turn = False
                        # Do NOT reset turn_start_ts here. Attachment/system
                        # entries frequently land between the final assistant
                        # message and EOF, and wiping the start TS here means
                        # the last turn's duration becomes uncomputable whenever
                        # the transcript tail isn't a clean assistant line.
                        # A fresh turn, if one follows, reassigns via the
                        # `turn_start_ts = pending_user_ts or ts` line below.
                    if etype == "user" and ts:
                        pending_user_ts = ts
                    continue

                if not in_assistant_turn:
                    in_assistant_turn = True
                    turn_start_ts = pending_user_ts or ts
                if ts:
                    turn_end_ts = ts

                msg = entry.get("message") or {}
                content = msg.get("content") or []
                if not isinstance(content, list):
                    continue

                text_pieces = []
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    btype = block.get("type")
                    if btype == "text":
                        t = block.get("text") or ""
                        if t.strip():
                            text_pieces.append(t)
                    elif btype == "tool_use":
                        name = block.get("name") or ""
                        inp = block.get("input") or {}
                        if name in EDIT_TOOLS:
                            fp = inp.get("file_path") or inp.get("notebook_path")
                            if fp:
                                current_turn_files.add(fp)

                if text_pieces:
                    last_assistant_text = "\n".join(text_pieces)

        if in_assistant_turn and current_turn_files:
            last_turn_tool_files = current_turn_files
    except Exception:
        return None, 0, None

    summary = None
    if last_assistant_text:
        cleaned = last_assistant_text.strip()
        if FENCE in cleaned:
            parts = cleaned.split(FENCE)
            cleaned = "".join(p for i, p in enumerate(parts) if i % 2 == 0).strip()
        lines = [ln.rstrip() for ln in cleaned.splitlines() if ln.strip()]
        cleaned = "\n".join(lines[:4]) if lines else ""
        if len(cleaned) > 220:
            cleaned = cleaned[:217].rstrip() + "\u2026"
        summary = cleaned or None

    duration_ms = None
    if turn_start_ts and turn_end_ts and turn_start_ts != turn_end_ts:
        try:
            from datetime import datetime
            def parse(t: str):
                return datetime.fromisoformat(t.replace("Z", "+00:00"))
            duration_ms = int((parse(turn_end_ts) - parse(turn_start_ts)).total_seconds() * 1000)
            if duration_ms < 0:
                duration_ms = None
        except Exception:
            duration_ms = None

    return summary, len(last_turn_tool_files), duration_ms


summary, edits, duration_ms = summarize_last_assistant(transcript_path)

# stdin-supplied `last_assistant_message` wins over whatever we scraped
# from the transcript. The transcript parser still runs because it also
# gives us `edits` and `duration_ms`, which are not in the stdin payload.
if stdin_last_assistant:
    cleaned = stdin_last_assistant.strip()
    if FENCE in cleaned:
        parts = cleaned.split(FENCE)
        cleaned = "".join(p for i, p in enumerate(parts) if i % 2 == 0).strip()
    lines = [ln.rstrip() for ln in cleaned.splitlines() if ln.strip()]
    cleaned = "\n".join(lines[:4]) if lines else ""
    if len(cleaned) > 220:
        cleaned = cleaned[:217].rstrip() + "\u2026"
    summary = cleaned or summary

# Title / detail promotion:
#   • edits > 0  → keep the explicit file-count headline; the agent's final
#                  message flows into `summary` as supplementary detail.
#   • edits == 0 and summary exists → the COMPLETE state chip in the
#                  expanded view already signals "done", so a generic
#                  "Done" title just restates it. Promote the first
#                  meaningful line of the assistant's last message to the
#                  title slot and demote the rest to `summary`.
#   • edits == 0 and no summary → fall back to the generic "Done"
#                  because there is nothing better to say.
title_detail_summary = summary
if edits > 0:
    title = "Done \u00b7 " + str(edits) + " file" + ("s" if edits != 1 else "") + " edited"
elif summary:
    lines = [ln for ln in summary.splitlines() if ln.strip()]
    head = lines[0].strip() if lines else ""
    # Keep the title one glanceable line — truncate long leads so the
    # 19pt headline never wraps beyond two lines.
    if len(head) > 80:
        head = head[:79].rstrip() + "\u2026"
    title = head or "Done"
    rest = "\n".join(lines[1:]).strip()
    title_detail_summary = rest or None
else:
    title = "Done"

doc = {
    "agent": "claude-code",
    "project": os.path.basename(cwd) or "claude-code",
    "status": "success",
    "title": title,
}
if title_detail_summary:
    doc["summary"] = title_detail_summary
if duration_ms is not None:
    doc["durationMs"] = duration_ms

print(json.dumps(doc, ensure_ascii=False))
PY

exit 0

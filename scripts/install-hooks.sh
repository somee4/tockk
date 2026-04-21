#!/usr/bin/env bash
# Tockk hook installer — applies Claude/Codex/Gemini hook setup in one command.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/../cli/tockk" setup --claude --codex --gemini

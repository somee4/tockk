# Tockk

A tock in the notch.
Never miss when your AI coding agent finishes work.

Tockk is a macOS menu bar app that receives local agent events over a Unix socket and turns them into notch-style notifications. It is built for Claude Code, Codex CLI, Gemini CLI, and any other local tool that can emit a small JSON payload when work finishes.

**Apache 2.0** | **macOS 13+** | **Claude Code · Codex CLI · Gemini CLI**

[한국어](./README.ko.md) · [Contributing](./CONTRIBUTING.md) · [Protocol](./docs/protocol.md) · [Install Guide](./docs/install.md)

---

## Why Tockk

- You need a notification that actually catches your eye when a terminal task finishes.
- The default macOS banner is small and brief — not a good fit for long-running agent work.
- You want to wire this up with local CLI hooks, without depending on a paid app.
- You want an open-source notch notification tool you can control end-to-end.

Tockk receives completion events on `~/Library/Application Support/Tockk/tockk.sock` and displays them in the notch area.

---

## Distribution

- `DMG`: the default path. Standard install flow for general users.
- `Homebrew cask`: coming soon. Will target `brew install --cask tockk`.

---

## Install Today

Grab the latest build from [GitHub Releases](https://github.com/somee4/tockk/releases).

1. Download `Tockk.dmg` from the latest release
2. Open the DMG and drag `Tockk.app` into `/Applications`
3. Launch it once

Requirements:

- macOS 13 Ventura or later

---

## Quick Start

Launch Tockk and its icon appears in the menu bar.

Fire a sample event to confirm the notch notification animates in:

```bash
tockk send \
  --agent claude \
  --project tockk \
  --status success \
  --title "Build passed" \
  --summary "42 tests, 0 failures — 12.3s" \
  --duration 12300
```

Or pipe a raw JSON payload straight into the socket:

```bash
printf '{"agent":"codex","project":"my-app","status":"error","title":"Type check failed","summary":"3 errors in src/api.ts"}\n' | \
  nc -U ~/Library/Application\ Support/Tockk/tockk.sock
```

---

## Hook Setup

Tockk configures agent hooks for you — no manual JSON editing required.

### From the app

Open `Tockk → Settings → Integrations` and toggle each agent on. Tockk writes the hook entry into the matching config file and keeps the path pointing at the bundled scripts inside `Tockk.app`.

### From the CLI

The bundled `tockk` CLI does the same thing from your shell:

```bash
tockk setup                 # configure Claude Code, Codex CLI, and Gemini CLI
tockk setup --claude        # Claude Code only
tockk setup --codex         # Codex CLI only
tockk setup --gemini        # Gemini CLI only
```

### Other tools

Any tool that can send a JSON line to the Unix socket works with Tockk:

```bash
tockk send --agent mytool --project demo --status success --title "Done"
```

See [docs/protocol.md](./docs/protocol.md) for the event schema and field definitions.

---

## License

Apache 2.0 © 2026 [somee4](https://github.com/somee4)

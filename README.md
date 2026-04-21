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

Two distribution targets are planned.

- `DMG`: the default path. Standard install flow for general users.
- `Homebrew cask`: the developer-friendly path. Targets `brew install --cask tockk`.

The release script in this repo prepares both the `DMG` and the Homebrew cask artifact together. Public distribution still requires a GitHub Releases upload and, if desired, publishing to a dedicated tap.

---

## Install Today

Until public install packages land, running from source is the most reliable path.

```bash
git clone https://github.com/somee4/tockk.git
cd tockk

brew install xcodegen
xcodegen generate
open Tockk.xcodeproj
```

Run the `Tockk` scheme from Xcode, or build from the terminal:

```bash
xcodebuild -scheme Tockk -configuration Debug build
```

Requirements:

- macOS 13 Ventura or later
- Xcode 15+

---

## Release Plan

Once releases are cut, only two install paths will remain.

### 1. DMG

The default path.

1. Download `Tockk.dmg`
2. Drag `Tockk.app` into `/Applications`
3. Launch it once

### 2. Homebrew

The developer path.

```bash
brew install --cask tockk
```

Maintainers can produce both artifacts with the release script:

```bash
./scripts/release.sh 0.1.0
```

Outputs:

- `build/Tockk-0.1.0.dmg`
- `build/homebrew/tockk.rb`

To generate a styled install-style DMG (with app icon dragged onto Applications in Finder), run the script inside a logged-in macOS session. In CI or headless sessions, fall back to a default-layout DMG with `TOCKK_SKIP_DMG_STYLING=1 ./scripts/release.sh 0.1.0`.

You can pass `TOCKK_HOMEBREW_TAP_DIR=/path/to/homebrew-tap` to have the cask file copied straight into a tap checkout.

Recommended environment for public distribution:

```bash
export TOCKK_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export TOCKK_NOTARYTOOL_PROFILE="tockk-notary"
./scripts/release.sh 0.1.0
```

Instead of `TOCKK_NOTARYTOOL_PROFILE`, you may pass these three directly:

```bash
export TOCKK_NOTARY_APPLE_ID="you@example.com"
export TOCKK_NOTARY_PASSWORD="app-specific-password"
export TOCKK_NOTARY_TEAM_ID="TEAMID"
```

Storing notarytool credentials once is usually easier:

```bash
xcrun notarytool store-credentials "tockk-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID"
```

---

## Quick Start

Launch the app and an icon appears in the menu bar.

You can verify the install with a test event:

```bash
printf '{"agent":"test","project":"demo","status":"success","title":"hello"}\n' | \
  nc -U ~/Library/Application\ Support/Tockk/tockk.sock
```

If everything is wired up, a notification animates in the notch area.

---

## Hook Setup

The easiest path today is to use the scripts bundled with the repository.

Configure all three integrations in one command:

```bash
./scripts/install-hooks.sh
```

Or drive it from the CLI directly:

```bash
./cli/tockk setup                 # all supported agents
./cli/tockk setup --claude        # Claude Code only
./cli/tockk setup --codex         # Codex CLI only
./cli/tockk setup --gemini        # Gemini CLI only
```

### Claude Code

Adds a `Stop` hook to `~/.claude/settings.json`.

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/bin/bash /absolute/path/to/tockk/scripts/hooks/claude-stop.sh"
          }
        ]
      }
    ]
  }
}
```

### Codex CLI

Adds a top-level `notify` entry to `~/.codex/config.toml`.

```toml
notify = ["/bin/bash", "/absolute/path/to/tockk/scripts/hooks/codex-notify.sh"]
```

### Gemini CLI

Adds an `AfterAgent` hook to `~/.gemini/settings.json`.

```json
{
  "hooks": {
    "AfterAgent": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/bin/bash /absolute/path/to/tockk/scripts/hooks/gemini-stop.sh"
          }
        ]
      }
    ]
  }
}
```

### Other Tools

Any tool that can send a JSON event to the Unix socket can integrate with Tockk.

```bash
printf '{"agent":"mytool","project":"demo","status":"success","title":"Done"}\n' | \
  nc -U ~/Library/Application\ Support/Tockk/tockk.sock
```

Using the bundled CLI:

```bash
./cli/tockk send --agent mytool --project demo --status success --title "Done"
```

See [docs/protocol.md](./docs/protocol.md) for the event schema and field definitions.

---

## What Tockk Shows

- Compact notch notification
- Expanded notification view
- Recent events in the menu bar
- Per-app theme presets in Settings

Current theme presets:

- `Practical Utility`
- `Developer Tool`
- `Small Product`

---

## Development

Tests:

```bash
xcodebuild test -scheme Tockk -destination 'platform=macOS'
```

Shell script linting:

```bash
shellcheck cli/tockk scripts/hooks/*.sh scripts/install-hooks.sh
```

The release packaging script lives at [`scripts/release.sh`](./scripts/release.sh). It produces a `DMG + Homebrew cask`, and will code-sign and notarize the build when `TOCKK_CODESIGN_IDENTITY` and notarization credentials are provided.

---

## License

Apache 2.0 © 2026 [somee4](https://github.com/somee4)

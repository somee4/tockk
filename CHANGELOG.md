# Changelog

All notable changes to Tockk are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.1] - 2026-04-22

### Added
- Homebrew cask distribution via the [`somee4/tockk`](https://github.com/somee4/homebrew-tockk) tap (`brew install --cask somee4/tockk/tockk`).
- `scripts/release.sh`: one-shot publish pipeline — uploads the DMG to GitHub Releases, re-derives `sha256` from the remote artifact (source of truth), and optionally auto-commits the cask into the tap checkout (`TOCKK_TAP_AUTO_PUSH=1`, `TOCKK_HOMEBREW_TAP_DIR`).
- New env vars: `TOCKK_RELEASE_REPO`, `TOCKK_SKIP_PUBLISH`, `TOCKK_TAP_AUTO_PUSH`.

### Changed
- README (en/ko): replaced the "coming soon" Homebrew note with real install commands; merged `Distribution` + `Install Today` into a single `Install` section.
- Removed the broken `docs/install.md` link from README headers.

## [0.1.0] - 2026-04-20

Initial public release.

### Added
- Notch-style notifications for AI coding agent completion (Claude Code, Codex, any CLI).
- Unix-domain-socket event ingestion with newline-delimited JSON protocol (v1).
- `EventQueue` with sequential display and minimum-display-time guarantee.
- Menubar 🔔 icon with recent events list (up to 10), Settings…, Quit.
- Settings window: sound toggle, display duration (3–15s), launch at login.
- Shell CLI (`cli/tockk send …`) for sending events from scripts.
- Example hook scripts:
  - `scripts/hooks/claude-stop.sh` — Claude Code Stop hook
  - `scripts/hooks/codex-notify.sh` — Codex CLI notify hook
  - `scripts/install-hooks.sh` — prints installation snippets
- Comprehensive docs: `README.md`, `docs/spec.md`, `docs/plan.md`, `docs/protocol.md`, `docs/install.md`.
- GitHub Actions CI: build, test, shellcheck.
- Apache 2.0 licensed.

### Known Limitations
- Settings changes apply on next app launch (no live reload of queue timings).
- No auto-update mechanism (planned for v0.2 via Sparkle).
- Ad-hoc code signing only; no Apple notarization yet (Gatekeeper prompts on first run).
- Best experience on MacBooks with a notch; fallback centered top drop for non-notch displays is minimal.

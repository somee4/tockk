# Contributing to Tockk

Tockk is an open-source project, but it is currently maintained in a lightweight solo-developer workflow.

Contributions are welcome, especially for:

- bug fixes
- documentation improvements
- small UX improvements
- hook integrations for developer tools

## Before You Start

For anything larger than a small fix, please open an issue or discussion first.

This helps avoid duplicate work and reduces the chance of building something that does not fit the direction of the project.

## Workflow

- Use `main` as the stable default branch.
- Do not work directly on `main`.
- Create a short-lived branch for your change.
- Keep changes focused and easy to review.

Recommended branch names:

- `fix/...`
- `feature/...`
- `docs/...`
- `chore/...`

Examples:

- `fix/socket-reconnect`
- `docs/readme-clarity`

## Pull Requests

When opening a pull request:

- explain what changed
- explain why the change is needed
- keep the scope narrow
- include screenshots for UI changes when possible

Before opening the PR, make sure:

- relevant tests pass
- documentation is updated if behavior changed
- unrelated files are not included

## Code and Commit Style

- Prefer small, coherent commits.
- Do not mix unrelated refactors with functional changes.
- Use clear commit messages.

Recommended commit prefixes:

- `feat:`
- `fix:`
- `docs:`
- `chore:`
- `refactor:`
- `test:`

## Build and Test

Generate the Xcode project if needed:

```bash
brew install xcodegen
xcodegen generate
```

Run tests:

```bash
xcodebuild test -scheme Tockk -destination 'platform=macOS'
```

If you could not run tests locally, mention that clearly in the pull request.

## Documentation

Public project documentation lives in:

- `README.md`
- `docs/`

Please do not add personal notes, temporary plans, or local working scratch files to `docs/`.

`docs/` is for durable, public-safe documentation such as:

- install and usage guides
- protocol references
- stable product specs
- archived implementation history that is still useful as public context

## Local-Only Files

Do not commit local-only files such as:

- `AGENTS.md`
- `.codex/`
- `.agents/`
- `.local/`
- machine-specific config
- secrets or credentials

## Maintainer Review

Submitting a pull request does not guarantee merge.

Large architectural changes, workflow changes, or product direction changes should be discussed first before implementation.

## Notes for Local AI Agents

If you are working locally with Codex, Claude Code, or another coding agent:

- treat `CONTRIBUTING.md` as the public repository workflow source of truth
- keep local-only agent notes and prompts out of git
- do not commit `AGENTS.md`, `.codex/`, `.agents/`, or `.local/` unless explicitly requested

## License

By contributing to this project, you agree that your contributions will be licensed under the Apache 2.0 license used by this repository.

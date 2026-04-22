# Tockk

노치에서 똑.
AI 코딩 에이전트의 작업 완료를 놓치지 마세요.

Tockk는 Unix 소켓으로 로컬 에이전트 이벤트를 받아 노치 스타일 알림으로 보여주는 macOS 메뉴바 앱입니다. Claude Code, Codex CLI, Gemini CLI 등 작업 완료 시 간단한 JSON payload를 전송할 수 있는 로컬 도구를 위해 만들어졌습니다.

**Apache 2.0** | **macOS 13+** | **Claude Code · Codex CLI · Gemini CLI**

[English](./README.md) · [Contributing](./CONTRIBUTING.md) · [Protocol](./docs/protocol.md)

---

## Why Tockk

- 터미널에서 작업이 끝나도 바로 눈에 들어오는 알림이 필요했습니다.
- macOS 기본 배너는 짧고 작아서 장시간 에이전트 작업에 잘 맞지 않습니다.
- 유료 앱 의존 없이, 로컬 CLI 훅만으로 단순하게 연결하고 싶었습니다.
- 오픈소스로 직접 제어 가능한 notch notification 도구가 필요했습니다.

Tockk는 작업 완료 이벤트를 `~/Library/Application Support/Tockk/tockk.sock`으로 받아 노치 영역에 표시합니다.

---

## 설치

macOS 13 Ventura 이상 필요.

### Homebrew (권장)

```bash
brew install --cask somee4/tockk/tockk
```

또는 tap을 먼저 추가한 뒤 설치:

```bash
brew tap somee4/tockk
brew install --cask tockk
```

### DMG

[GitHub Releases](https://github.com/somee4/tockk/releases)에서 최신 빌드를 받으세요.

1. 최신 릴리스에서 `Tockk.dmg` 다운로드
2. DMG를 열고 `Tockk.app`을 `/Applications`로 드래그
3. 첫 실행

---

## Quick Start

Tockk를 실행하면 메뉴바에 아이콘이 나타납니다.

샘플 이벤트로 노치 알림이 뜨는지 바로 확인해볼 수 있습니다.

```bash
tockk send \
  --agent claude \
  --project tockk \
  --status success \
  --title "Build passed" \
  --summary "42 tests, 0 failures — 12.3s" \
  --duration 12300
```

혹은 JSON payload를 소켓으로 직접 보낼 수도 있습니다.

```bash
printf '{"agent":"codex","project":"my-app","status":"error","title":"Type check failed","summary":"3 errors in src/api.ts"}\n' | \
  nc -U ~/Library/Application\ Support/Tockk/tockk.sock
```

---

## Hook Setup

Tockk가 에이전트 훅을 대신 설정해줍니다. 설정 파일을 직접 열어 고칠 필요가 없습니다.

### 앱에서 설정

`Tockk → Settings → Integrations`에서 각 에이전트를 토글하면 됩니다. Tockk가 해당 설정 파일에 훅을 등록하고, 경로는 `Tockk.app` 번들에 포함된 스크립트를 가리키도록 유지합니다.

### CLI에서 설정

번들된 `tockk` CLI로도 동일하게 설정할 수 있습니다.

```bash
tockk setup                 # Claude Code, Codex CLI, Gemini CLI 모두
tockk setup --claude        # Claude Code만
tockk setup --codex         # Codex CLI만
tockk setup --gemini        # Gemini CLI만
```

### 그 외 도구

Unix 소켓으로 JSON 한 줄을 보낼 수 있는 도구라면 무엇이든 연동 가능합니다.

```bash
tockk send --agent mytool --project demo --status success --title "Done"
```

이벤트 스키마와 필드 설명은 [docs/protocol.md](./docs/protocol.md)를 참고하세요.

---

## License

Apache 2.0 © 2026 [somee4](https://github.com/somee4)

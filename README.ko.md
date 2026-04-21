# Tockk

노치에서 똑.
AI 코딩 에이전트의 작업 완료를 놓치지 마세요.

Tockk는 Unix 소켓으로 로컬 에이전트 이벤트를 받아 노치 스타일 알림으로 보여주는 macOS 메뉴바 앱입니다. Claude Code, Codex CLI, Gemini CLI 등 작업 완료 시 간단한 JSON payload를 전송할 수 있는 로컬 도구를 위해 만들어졌습니다.

**Apache 2.0** | **macOS 13+** | **Claude Code · Codex CLI · Gemini CLI**

[English](./README.md) · [Contributing](./CONTRIBUTING.md) · [Protocol](./docs/protocol.md) · [설치 가이드](./docs/install.md)

---

## Why Tockk

- 터미널에서 작업이 끝나도 바로 눈에 들어오는 알림이 필요했습니다.
- macOS 기본 배너는 짧고 작아서 장시간 에이전트 작업에 잘 맞지 않습니다.
- 유료 앱 의존 없이, 로컬 CLI 훅만으로 단순하게 연결하고 싶었습니다.
- 오픈소스로 직접 제어 가능한 notch notification 도구가 필요했습니다.

Tockk는 작업 완료 이벤트를 `~/Library/Application Support/Tockk/tockk.sock`으로 받아 노치 영역에 표시합니다.

---

## Distribution

배포 방향은 두 가지로 정리합니다.

- `DMG`: 기본 설치 경로. 일반 사용자 기준의 표준 설치 방식입니다.
- `Homebrew cask`: 개발자용 보조 설치 경로. `brew install --cask tockk`를 목표로 합니다.

저장소의 릴리스 스크립트는 `DMG`와 Homebrew cask 산출물을 함께 만들도록 정리되어 있습니다. 공개 배포를 위해서는 GitHub Releases 업로드와, 필요하면 별도 tap 반영이 이어져야 합니다.

---

## Install Today

공개 설치 패키지가 정리되기 전에는 소스에서 실행하는 방식이 가장 확실합니다.

```bash
git clone https://github.com/somee4/tockk.git
cd tockk

brew install xcodegen
xcodegen generate
open Tockk.xcodeproj
```

Xcode에서 `Tockk` 스킴으로 실행하거나 터미널에서 빌드할 수 있습니다.

```bash
xcodebuild -scheme Tockk -configuration Debug build
```

요구사항:

- macOS 13 Ventura 이상
- Xcode 15+

---

## Release Plan

릴리스가 정리되면 설치 방법은 아래 둘만 남길 예정입니다.

### 1. DMG

기본 경로입니다.

1. `Tockk.dmg` 다운로드
2. `Tockk.app`을 `/Applications`로 드래그
3. 첫 실행

### 2. Homebrew

개발자용 경로입니다.

```bash
brew install --cask tockk
```

유지보수자는 아래 릴리스 스크립트로 두 산출물을 함께 만들 수 있습니다.

```bash
./scripts/release.sh 0.1.0
```

결과물:

- `build/Tockk-0.1.0.dmg`
- `build/homebrew/tockk.rb`

Finder에서 앱 아이콘을 `Applications`로 드래그하는 설치형 DMG 레이아웃까지 만들려면, 이 스크립트를 로그인된 macOS 세션에서 실행하는 편이 좋습니다. CI나 헤드리스 세션에서는 `TOCKK_SKIP_DMG_STYLING=1 ./scripts/release.sh 0.1.0`처럼 기본 레이아웃 DMG로 폴백할 수 있습니다.

필요하면 `TOCKK_HOMEBREW_TAP_DIR=/path/to/homebrew-tap` 환경변수를 주어 cask 파일을 tap 체크아웃으로 바로 복사할 수 있습니다.

공개 배포용 권장 환경변수:

```bash
export TOCKK_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export TOCKK_NOTARYTOOL_PROFILE="tockk-notary"
./scripts/release.sh 0.1.0
```

`TOCKK_NOTARYTOOL_PROFILE` 대신 아래 3개를 직접 써도 됩니다.

```bash
export TOCKK_NOTARY_APPLE_ID="you@example.com"
export TOCKK_NOTARY_PASSWORD="app-specific-password"
export TOCKK_NOTARY_TEAM_ID="TEAMID"
```

처음 한 번은 notarytool 자격증명을 저장해두는 편이 편합니다.

```bash
xcrun notarytool store-credentials "tockk-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID"
```

---

## Quick Start

앱을 실행하면 메뉴바에 아이콘이 나타납니다.

아래 테스트 이벤트로 바로 동작을 확인할 수 있습니다.

```bash
printf '{"agent":"test","project":"demo","status":"success","title":"hello"}\n' | \
  nc -U ~/Library/Application\ Support/Tockk/tockk.sock
```

정상 동작하면 노치 영역에 알림 애니메이션이 표시됩니다.

---

## Hook Setup

현재 기준으로 가장 쉬운 경로는 저장소 안의 스크립트를 그대로 사용하는 방식입니다.

세 가지 연동을 한 번에 설정:

```bash
./scripts/install-hooks.sh
```

CLI로 직접 설정:

```bash
./cli/tockk setup                 # 지원하는 모든 에이전트
./cli/tockk setup --claude        # Claude Code만
./cli/tockk setup --codex         # Codex CLI만
./cli/tockk setup --gemini        # Gemini CLI만
```

### Claude Code

`~/.claude/settings.json`에 Stop 훅을 추가합니다.

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

`~/.codex/config.toml`에 top-level `notify`를 추가합니다.

```toml
notify = ["/bin/bash", "/absolute/path/to/tockk/scripts/hooks/codex-notify.sh"]
```

### Gemini CLI

`~/.gemini/settings.json`에 `AfterAgent` 훅을 추가합니다.

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

어떤 도구든 JSON 이벤트를 Unix 소켓으로 보내면 연동할 수 있습니다.

```bash
printf '{"agent":"mytool","project":"demo","status":"success","title":"Done"}\n' | \
  nc -U ~/Library/Application\ Support/Tockk/tockk.sock
```

번들된 CLI를 쓰는 경우:

```bash
./cli/tockk send --agent mytool --project demo --status success --title "Done"
```

이벤트 스키마와 필드 설명은 [docs/protocol.md](./docs/protocol.md)를 참고하세요.

---

## What Tockk Shows

- 컴팩트 노치 알림
- 확장 알림 뷰
- 메뉴바의 최근 이벤트 목록
- 설정의 앱별 테마 프리셋

현재 테마 프리셋:

- `Practical Utility`
- `Developer Tool`
- `Small Product`

---

## Development

테스트:

```bash
xcodebuild test -scheme Tockk -destination 'platform=macOS'
```

쉘 스크립트 확인:

```bash
shellcheck cli/tockk scripts/hooks/*.sh scripts/install-hooks.sh
```

릴리스 패키징 스크립트는 [`scripts/release.sh`](./scripts/release.sh)에 있습니다. 현재 기준 산출물은 `DMG + Homebrew cask`이며, `TOCKK_CODESIGN_IDENTITY`와 notarization 자격증명을 주면 공개 배포용 서명/노타리제이션까지 수행합니다.

---

## License

Apache 2.0 © 2026 [somee4](https://github.com/somee4)

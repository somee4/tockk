# Tockk Install Guide

---

## Quick Install

1. [GitHub Releases](https://github.com/somee4/tockk/releases)에서 최신 `Tockk.app.zip` 다운로드
2. 압축 해제 후 `Tockk.app`을 `/Applications` 폴더로 드래그
3. 첫 실행 시 Gatekeeper 경고가 표시됩니다:
   - Finder에서 `Tockk.app` 우클릭 → **열기(Open)**
   - "확인되지 않은 개발자" 경고에서 **열기** 클릭
   - 이후 실행부터는 경고가 나타나지 않습니다

> Homebrew cask는 추후 릴리스에서 제공할 예정입니다.

---

## Permissions

**Tockk는 특별한 권한을 요청하지 않습니다.**

| Permission | Required |
|------------|----------|
| Accessibility (손쉬운 사용) | No |
| Network | No |
| Microphone | No |
| Location | No |
| Camera | No |

Tockk는 Unix 도메인 소켓(`~/Library/Application Support/Tockk/tockk.sock`)만 사용하며,  
이는 사용자 디렉터리 내 로컬 통신이므로 네트워크 권한이 필요 없습니다.

---

## Verifying the Install

1. `/Applications/Tockk.app`을 실행합니다.
2. 메뉴바에 🔔 아이콘이 나타나면 정상 실행된 것입니다.
3. 아래 테스트 이벤트를 터미널에서 실행하세요:

```bash
printf '{"agent":"test","project":"demo","status":"success","title":"hello"}\n' | \
  nc -U ~/Library/Application\ Support/Tockk/tockk.sock
```

노치 영역에서 알림 애니메이션이 재생되면 설치가 완료된 것입니다.

---

## Hook Setup

### Claude Code

`~/.claude/settings.json`을 열어 아래 내용을 추가하세요:

```json
{
  "hooks": {
    "Stop": [
      {
        "command": "/absolute/path/to/tockk/scripts/hooks/claude-stop.sh"
      }
    ]
  }
}
```

경로는 실제 Tockk 클론 위치로 교체하세요. 예:

```json
"command": "/Users/myname/Projects/tockk/scripts/hooks/claude-stop.sh"
```

**훅이 실행되지 않는다면:**
- 경로가 절대 경로인지 확인 (`~/` 확장이 안 될 수 있음)
- 스크립트에 실행 권한이 있는지 확인: `ls -l scripts/hooks/claude-stop.sh`
- 실행 권한 부여: `chmod +x scripts/hooks/claude-stop.sh`
- Claude Code를 재시작한 후 다시 시도

### Codex CLI

`~/.codex/config.toml`에 아래 내용을 추가하세요:

```toml
[notifications]
command = ["/absolute/path/to/tockk/scripts/hooks/codex-notify.sh"]
```

**훅이 실행되지 않는다면:**
- 경로가 절대 경로이고 파일이 존재하는지 확인
- 실행 권한 부여: `chmod +x scripts/hooks/codex-notify.sh`
- `~/.codex/config.toml` 문법이 유효한 TOML인지 확인

### Gemini CLI

`~/.gemini/settings.json`을 열어 아래 내용을 추가하세요:

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

경로는 실제 Tockk 클론 위치로 교체하세요.

**훅이 실행되지 않는다면:**
- 경로가 절대 경로인지 확인 (`~/`는 Gemini CLI가 확장하지 않음)
- 실행 권한 부여: `chmod +x scripts/hooks/gemini-stop.sh`
- `~/.gemini/settings.json`이 유효한 JSON인지 확인
- Gemini CLI를 재시작한 후 다시 시도

### 자동 설치 스크립트

훅을 자동으로 등록하는 스크립트도 제공됩니다:

```bash
./scripts/install-hooks.sh
```

이 스크립트는 Claude Code, Codex CLI, Gemini CLI 설정 파일에 훅을 추가합니다.

---

## Uninstall

### 앱 제거

```bash
# 앱 파일 삭제
rm -rf /Applications/Tockk.app

# 앱 데이터 삭제 (소켓 파일, 설정 등)
rm -rf ~/Library/Application\ Support/Tockk
```

### Hook 제거

**Claude Code** (`~/.claude/settings.json`):  
`hooks.Stop` 배열에서 `claude-stop.sh` 항목을 제거하세요.

**Codex CLI** (`~/.codex/config.toml`):  
`[notifications]` 섹션에서 `command` 줄을 제거하거나 섹션 전체를 삭제하세요.

**Gemini CLI** (`~/.gemini/settings.json`):  
`hooks.AfterAgent` 배열에서 `gemini-stop.sh` 항목을 제거하세요.

---

## Troubleshooting

### 소켓 파일이 생성되지 않음

**증상:** `nc -U` 연결 시 `No such file or directory` 오류

**원인 및 해결:**
- Tockk 앱이 실행 중이 아닙니다. `/Applications/Tockk.app`을 실행하세요.
- 앱이 크래시된 경우: 콘솔(Console.app)에서 `Tockk` 관련 로그를 확인하세요.
- 소켓 경로 확인: `ls ~/Library/Application\ Support/Tockk/`

### 소리가 나지 않음

**증상:** 노치 알림은 표시되지만 소리가 없음

**해결:**
1. 메뉴바 아이콘 → **Settings** → **Sound** 토글 확인
2. 시스템 볼륨이 음소거 상태가 아닌지 확인
3. 시스템 설정 → 사운드 → 출력 장치 확인

### 훅은 실행되지만 노치 알림이 없음

**증상:** 스크립트는 실행되지만 노치에 아무것도 표시되지 않음

**해결:**
1. Tockk 앱이 실행 중인지 확인 (메뉴바에 🔔 아이콘)
2. 아래 명령으로 수동 테스트:
   ```bash
   printf '{"agent":"test","project":"demo","status":"success","title":"test"}\n' | \
     nc -U ~/Library/Application\ Support/Tockk/tockk.sock
   ```
3. 수동 테스트에서도 실패한다면 소켓 파일 문제 — 위 "소켓 파일이 생성되지 않음" 항목 참조
4. MacBook에 노치가 없는 모델이면 알림이 표시되지 않을 수 있습니다 (노치 없는 Mac은 지원하지 않음)

### Gatekeeper가 열기를 반복 차단함

**해결:**
```bash
# Quarantine 속성 제거
xattr -dr com.apple.quarantine /Applications/Tockk.app
```

이후 정상적으로 실행됩니다.

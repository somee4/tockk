# Tockk — Spec

**Tagline:** 노치에서 똑. AI 코딩 에이전트의 작업 완료를 놓치지 마세요.

---

## 1. Goal

맥북 노치(또는 상단 중앙 영역)에서 Dynamic Island 스타일로 펼쳐지는 알림으로 Claude Code·Codex CLI 같은 AI 에이전트의 작업 완료 이벤트를 눈에 띄게 알려주는 오픈소스 macOS 앱.

## 2. Problem

- macOS 기본 알림 배너는 작고 짧게 지나가서 놓치기 쉽다.
- 기존 AI 완료 알림 도구(code-notify, CCNotify, agent-notify)는 전부 OS 기본 배너 사용.
- 기존 노치 앱(NotchNook, DynamicLake)은 외부 CLI/URL 트리거 API를 열어두지 않음.
- **"AI 완료 → 노치 애니메이션" 조합의 기성품은 없다.**

## 3. Users

- Claude Code, Codex CLI, 또는 Gemini CLI로 장시간 작업을 돌려두고 다른 일을 하는 개발자.
- 여러 프로젝트/세션을 병렬로 돌리며 각각의 완료 시점을 놓치지 않고 싶은 사람.

## 4. MVP Scope

### In-scope

1. **이벤트 수신** — 로컬 Unix 도메인 소켓 서버. JSON payload 받음.
2. **노치 알림 표시** — 컴팩트 뷰(한 줄) → 클릭 시 확장 뷰.
3. **큐잉** — 동시 수신 시 순차 표시, 최소 표시 시간 보장.
4. **사운드** — 기본 on, 설정에서 끄기.
5. **메뉴바 아이콘** — 최근 이벤트 목록, 설정 접근.
6. **설정 창** — 사운드 on/off, 표시 시간, 시작 시 자동 실행.
7. **훅 스크립트** — Claude Code `Stop` 훅, Codex `notify` 훅, Gemini CLI `AfterAgent` 훅 예제 포함.
8. **CLI 헬퍼** — `tockk send --title "..." --summary "..."` 한 줄 명령.

### Out-of-scope (v1)

- iCloud 동기화, 원격 알림.
- Slack/Discord 연동 (이미 agent-notify 등이 있음).
- 노치 없는 맥(외장 모니터 전용) 전용 UI — 기본 폴백은 상단 중앙 드롭다운으로 해결.
- 푸시 알림, iOS 앱.

## 5. UX

### 컴팩트 뷰 (기본)

```
┌─────────────────────────────────┐
│  ✅  site · 빌드 완료 · 2m 14s  │
└─────────────────────────────────┘
```

- 노치 양옆으로 슬라이드하며 펼쳐짐 (DynamicNotchKit 애니메이션).
- 기본 6초 표시. 설정에서 3~15초 조절.
- 호버 시 일시정지, 밖으로 나가면 다시 카운트.

### 확장 뷰 (클릭 시)

```
┌─────────────────────────────────────────┐
│  ✅  site                               │
│  빌드 완료 (2m 14s)                     │
│  ───────────────────────────────────    │
│  3 files changed, all tests passing     │
│  마지막 커밋: feat(content): add lang.. │
│                               [닫기]    │
└─────────────────────────────────────────┘
```

- 클릭으로 확장/축소 토글.

### 큐 동작

- 이벤트 A 표시 중 이벤트 B 수신 → A가 최소 표시 시간(2초)을 채운 후 B로 전환.
- 뱃지에 "+N" 표시해서 뒤에 몇 개 대기 중인지 알림.
- 메뉴바 드롭다운에서 최근 10개 이벤트 목록 볼 수 있음.

### 상태 아이콘

| 상태 | 아이콘 | 색 |
|---|---|---|
| success | ✅ | 초록 |
| error | ❌ | 빨강 |
| waiting | ⏳ | 주황 (사용자 입력 대기) |
| info | 💬 | 파랑 |

## 6. Event Protocol

### Transport

- **Unix 도메인 소켓**: `~/Library/Application Support/Tockk/tockk.sock`
- 라인 단위 JSON (newline-delimited JSON).
- 소켓 권한 0600 (현재 유저만 읽고 쓰기).

### Event Schema

```json
{
  "agent": "claude-code",
  "project": "site",
  "status": "success",
  "title": "빌드 완료",
  "summary": "3 files changed, all tests passing",
  "durationMs": 134000,
  "timestamp": "2026-04-20T10:30:00Z"
}
```

| 필드 | 필수 | 설명 |
|---|---|---|
| `agent` | ✅ | `claude-code`, `codex`, `gemini-cli`, `custom` 등 |
| `project` | ✅ | 프로젝트 이름 (보통 디렉토리 basename) |
| `status` | ✅ | `success` / `error` / `waiting` / `info` |
| `title` | ✅ | 한 줄 요약 (최대 80자) |
| `summary` | | 상세 내용 (최대 500자) |
| `durationMs` | | 작업 소요 시간 |
| `timestamp` | | ISO 8601 |

### CLI

```bash
tockk send --agent claude-code --project site --status success \
  --title "빌드 완료" --summary "3 files changed" --duration 134000
```

- stdin으로도 JSON 받을 수 있음: `echo '{...}' | tockk send`
- 앱이 안 떠 있으면 소켓 연결 실패 → 조용히 exit 1 (에이전트 훅을 방해하지 않음).

## 7. Architecture

```
┌────────────────┐    JSON over     ┌──────────────┐
│ Claude/Codex   │  ─────────────>  │  Tockk app    │
│  Stop hook     │   Unix socket     │  (menubar)   │
└────────────────┘                   └──────┬───────┘
                                            │
                                            v
                                    ┌───────────────┐
                                    │  EventQueue   │
                                    └──────┬────────┘
                                           │
                                           v
                                    ┌───────────────┐
                                    │ NotchPresenter│
                                    │ (DynamicNotch │
                                    │     Kit)      │
                                    └───────────────┘
```

### Modules

- **SocketServer** — Unix domain socket listening, JSON decoding.
- **EventQueue** — FIFO queue with min-display-time guarantee.
- **NotchPresenter** — DynamicNotchKit wrapper, compact/expanded views.
- **Settings** — UserDefaults-backed preferences.
- **MenubarController** — NSStatusItem, recent events dropdown.
- **LaunchAtLogin** — ServiceManagement API.

## 8. Tech Stack

- **Language**: Swift 5.9+
- **UI**: SwiftUI + AppKit (NSStatusItem, NSPanel)
- **Min OS**: macOS 13 Ventura (DynamicNotchKit 요구사항)
- **Dependencies** (SPM):
  - [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) — 노치 렌더링
  - [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin) — 로그인 시 자동 실행
- **Testing**: XCTest
- **Build**: Xcode 15+
- **Distribution**: GitHub Releases (`.dmg` + Sparkle for auto-update 추후), Homebrew cask (2차)

## 9. Non-Goals

- 완벽한 Sandbox 준수 — v1은 non-sandboxed (Unix 소켓 권한 때문). 배포는 개발자 서명만.
- 노치 없는 맥에서의 완벽한 경험 — 폴백은 있지만 최적화 대상은 아님.
- Windows/Linux 지원 — macOS 전용.

## 10. Open Source & Distribution

- **라이선스**: Apache 2.0
- **배포**: GitHub Releases, 무료
- **README**: 설치, 훅 설정, 스크린샷/GIF, 기여 가이드, 라이선스, 후원 링크
- **후원**: GitHub Sponsors 링크 (README 하단 + `FUNDING.yml`)
- **로고**: 노치 안에서 똑똑 치는 애니메이션 모티프 (추후 디자이너 의뢰 or 자작)

## 11. Success Criteria

1. Claude Code `Stop` 훅 3줄 등록 → 빌드 완료 시 노치에서 알림 뜸.
2. 동시 3개 이벤트 발생 → 순차 표시, 뱃지로 대기 수 노출.
3. 1시간 구동 중 메모리 50MB 이하, CPU idle 시 1% 이하.
4. README 보고 비개발자도 설치 & 훅 등록 가능.

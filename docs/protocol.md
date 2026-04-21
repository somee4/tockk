# Tockk Event Protocol

Protocol version: **v1**

---

## Transport

Tockk는 Unix 도메인 소켓으로 이벤트를 수신합니다.

| Property | Value |
|----------|-------|
| Socket path | `~/Library/Application Support/Tockk/tockk.sock` |
| Permissions | `0600` (소유자 전용 — 다른 사용자 프로세스는 접근 불가) |
| Framing | Newline-delimited JSON (각 이벤트는 `\n` 으로 끝남) |
| Encoding | UTF-8 |

소켓 파일은 Tockk 앱이 실행될 때 생성되고, 앱이 종료되면 제거됩니다.  
앱이 실행 중이지 않으면 소켓 파일이 없으므로 연결 시도가 실패합니다.

---

## Event Schema

각 이벤트는 하나의 JSON 오브젝트를 담은 단일 줄(line)입니다.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `agent` | string | **Required** | 이벤트를 생성한 에이전트 이름 (예: `"claude"`, `"codex"`, `"custom"`) |
| `project` | string | **Required** | 작업 중인 프로젝트 또는 디렉터리 이름 |
| `status` | string | **Required** | 이벤트 상태 — 아래 Status Values 표 참조 |
| `title` | string | **Required** | 노치에 표시할 짧은 제목 (권장 40자 이하) |
| `summary` | string | Optional | 부제목 — 상세 정보 (예: 변경된 파일 수) |
| `durationMs` | number | Optional | 작업 소요 시간(밀리초). 표시용 메타 정보 |
| `cwd` | string | Optional | 작업 디렉터리 경로. 확장 뷰의 `열기` 동작에 사용 |
| `sourceAppBundleId` | string | Optional | 작업을 시작한 앱의 번들 ID. 있으면 Finder 대신 해당 앱으로 복귀 시도 |
| `timestamp` | string | Optional | ISO 8601 시각. 생략하면 수신 시각으로 채움 |

알 수 없는 필드는 무시됩니다. `id`는 앱이 내부적으로 채우므로 외부 클라이언트가 보낼 필요가 없습니다.

---

## Status Values

| Status | Meaning | Default Icon |
|--------|---------|--------------|
| `success` | 작업이 성공적으로 완료됨 | ✅ |
| `error` | 작업 중 오류 발생 | ❌ |
| `waiting` | 에이전트가 사용자 입력 대기 중 | ⏳ |
| `info` | 일반 정보성 알림 | ℹ️ |

알 수 없는 status 값은 `info`로 폴백 처리됩니다.

---

## Example Events

### success

```json
{"agent":"claude","project":"myapp","status":"success","title":"Task complete","summary":"3 files changed","durationMs":134000,"cwd":"/Users/me/myapp"}
```

### error

```json
{"agent":"codex","project":"api-server","status":"error","title":"Build failed","summary":"See terminal for details"}
```

### waiting

```json
{"agent":"claude","project":"refactor","status":"waiting","title":"Input needed","summary":"Waiting for your confirmation"}
```

### info

```json
{"agent":"custom","project":"deploy","status":"info","title":"Deployment started"}
```

---

## Error Handling

| Situation | Behavior |
|-----------|----------|
| JSON 파싱 실패 (malformed) | 이벤트 무시, 소켓 연결 유지 |
| 필수 필드 누락 | 이벤트 무시 |
| 앱 미실행 (소켓 없음) | 클라이언트에서 연결 오류 발생 — Tockk를 먼저 실행하세요 |
| 연결 후 즉시 닫힘 | 정상 — Tockk는 각 이벤트 수신 후 연결을 닫습니다 |
| 소켓 타임아웃 | 없음 — 전송 후 바로 연결을 닫으면 됩니다 |

클라이언트는 이벤트를 전송한 뒤 소켓 연결을 닫으면 됩니다.  
응답 데이터를 기다릴 필요가 없습니다 (fire-and-forget).

---

## Code Examples

### Bash

```bash
#!/usr/bin/env bash
SOCK=~/Library/Application\ Support/Tockk/tockk.sock

send_tockk() {
  local agent="$1" project="$2" status="$3" title="$4" cwd="${5:-$PWD}"
  printf '{"agent":"%s","project":"%s","status":"%s","title":"%s","cwd":"%s"}\n' \
    "$agent" "$project" "$status" "$title" "$cwd" \
    | nc -U "$SOCK"
}

send_tockk "mytool" "demo" "success" "Done"
```

### Python

```python
import socket
import json
import os

def send_tockk(
    agent: str,
    project: str,
    status: str,
    title: str,
    summary: str = "",
    cwd: str = "",
) -> None:
    sock_path = os.path.expanduser(
        "~/Library/Application Support/Tockk/tockk.sock"
    )
    payload = {"agent": agent, "project": project, "status": status, "title": title}
    if summary:
        payload["summary"] = summary
    if cwd:
        payload["cwd"] = cwd

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(sock_path)
        s.sendall((json.dumps(payload) + "\n").encode("utf-8"))

send_tockk(
    "myscript",
    "data-pipeline",
    "success",
    "ETL complete",
    "10k rows processed",
    os.getcwd(),
)
```

### Node.js

```js
const net = require('net');
const os = require('os');
const path = require('path');

function sendTockk({ agent, project, status, title, summary, cwd } = {}) {
  const sockPath = path.join(
    os.homedir(),
    'Library/Application Support/Tockk/tockk.sock'
  );
  const payload = JSON.stringify({ agent, project, status, title, summary, cwd }) + '\n';
  const client = net.createConnection(sockPath, () => {
    client.write(payload);
    client.end();
  });
  client.on('error', () => {}); // fire-and-forget: app may not be running
}

sendTockk({
  agent: 'node-tool',
  project: 'myapp',
  status: 'success',
  title: 'Build done',
  cwd: process.cwd(),
});
```

### nc (one-liner)

```bash
printf '{"agent":"test","project":"demo","status":"success","title":"hello"}\n' | \
  nc -U ~/Library/Application\ Support/Tockk/tockk.sock
```

---

## Version Compatibility

현재 버전: **Protocol v1**

v1은 additive-only 정책을 따릅니다:
- 필드 추가는 하위 호환 변경으로 간주합니다.
- 기존 필드의 제거 또는 타입 변경 시 major 버전이 증가합니다.
- 알 수 없는 필드는 무시됩니다 — 미래 클라이언트가 새 필드를 보내도 현재 앱은 정상 동작합니다.

## CLI Shortcut

번들된 CLI를 쓰면 JSON을 직접 만들지 않고도 같은 이벤트를 보낼 수 있습니다.

```bash
tockk send --agent codex --status success --title "Build done" --duration 134000 --cwd "$PWD"
```

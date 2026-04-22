# Tockk Event Protocol

Protocol version: **v1**

---

## Transport

Tockk receives events over a Unix domain socket.

| Property | Value |
|----------|-------|
| Socket path | `~/Library/Application Support/Tockk/tockk.sock` |
| Permissions | `0600` (owner-only — other user processes cannot access it) |
| Framing | Newline-delimited JSON (each event ends with `\n`) |
| Encoding | UTF-8 |

The socket file is created when the Tockk app launches and removed when it exits.
If the app is not running, the socket file does not exist and connection attempts will fail.

---

## Event Schema

Each event is a single line containing one JSON object.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `agent` | string | **Required** | Name of the agent that produced the event (e.g. `"claude"`, `"codex"`, `"custom"`) |
| `project` | string | **Required** | Project or directory name the work belongs to |
| `status` | string | **Required** | Event status — see the Status Values table below |
| `title` | string | **Required** | Short title shown in the notch (40 chars or fewer recommended) |
| `summary` | string | Optional | Subtitle with extra detail (e.g. number of files changed) |
| `durationMs` | number | Optional | Elapsed time in milliseconds. Metadata for display |
| `timestamp` | string | Optional | ISO 8601 timestamp. Filled with the receive time if omitted |

Unknown fields are ignored. `id` is populated internally by the app, so external clients do not need to send it.

---

## Status Values

| Status | Meaning | Default Icon |
|--------|---------|--------------|
| `success` | Work completed successfully | ✅ |
| `error` | An error occurred during the work | ❌ |
| `waiting` | Agent is waiting for user input | ⏳ |
| `info` | General informational notice | ℹ️ |

Unknown status values fall back to `info`.

---

## Example Events

### success

```json
{"agent":"claude","project":"myapp","status":"success","title":"Task complete","summary":"3 files changed","durationMs":134000}
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
| JSON parse failure (malformed) | Event is dropped, socket connection is kept alive |
| Required field missing | Event is dropped |
| App not running (no socket) | Client gets a connection error — start Tockk first |
| Connection closed right after send | Expected — Tockk closes the connection after each event |
| Socket timeout | None — clients can close the connection immediately after sending |

Clients may close the socket as soon as the event has been sent.
There is no response to wait for (fire-and-forget).

---

## Code Examples

### Bash

```bash
#!/usr/bin/env bash
SOCK=~/Library/Application\ Support/Tockk/tockk.sock

send_tockk() {
  local agent="$1" project="$2" status="$3" title="$4" summary="${5:-}"
  printf '{"agent":"%s","project":"%s","status":"%s","title":"%s","summary":"%s"}\n' \
    "$agent" "$project" "$status" "$title" "$summary" \
    | nc -U "$SOCK"
}

send_tockk "mytool" "demo" "success" "Done" "all green"
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
    duration_ms: int | None = None,
) -> None:
    sock_path = os.path.expanduser(
        "~/Library/Application Support/Tockk/tockk.sock"
    )
    payload = {"agent": agent, "project": project, "status": status, "title": title}
    if summary:
        payload["summary"] = summary
    if duration_ms is not None:
        payload["durationMs"] = duration_ms

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(sock_path)
        s.sendall((json.dumps(payload) + "\n").encode("utf-8"))

send_tockk(
    "myscript",
    "data-pipeline",
    "success",
    "ETL complete",
    "10k rows processed",
    duration_ms=42000,
)
```

### Node.js

```js
const net = require('net');
const os = require('os');
const path = require('path');

function sendTockk({ agent, project, status, title, summary, durationMs } = {}) {
  const sockPath = path.join(
    os.homedir(),
    'Library/Application Support/Tockk/tockk.sock'
  );
  const payload = JSON.stringify({ agent, project, status, title, summary, durationMs }) + '\n';
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
  durationMs: 18000,
});
```

### nc (one-liner)

```bash
printf '{"agent":"test","project":"demo","status":"success","title":"hello"}\n' | \
  nc -U ~/Library/Application\ Support/Tockk/tockk.sock
```

---

## Version Compatibility

Current version: **Protocol v1**

v1 follows an additive-only policy:
- Adding fields is considered a backward-compatible change.
- Removing existing fields or changing their types bumps the major version.
- Unknown fields are ignored — future clients can send new fields and the current app will keep working.

## CLI Shortcut

With the bundled CLI you can send the same events without crafting JSON yourself.

```bash
tockk send --agent codex --status success --title "Build done" --duration 134000
```

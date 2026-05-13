# Tockk Long-Run Measurement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local diagnostic command that repeatedly sends real Tockk socket events to the installed app and records before/during/after process metrics for long-run animation and memory investigation.

**Architecture:** Add one focused Python 3 standard-library script under `scripts/` that owns target discovery, event sending, sampling, parsing, and `.local/` output. Keep parser and dry-run behavior unit-testable without a live GUI app; keep live measurement as an explicit manual diagnostic because it depends on `/Applications/Tockk.app` and macOS process-inspection permissions.

**Tech Stack:** Python 3 standard library (`argparse`, `dataclasses`, `json`, `pathlib`, `re`, `socket`, `subprocess`, `time`, `unittest`), macOS CLI tools (`ps`, `vmmap`, `leaks`), Tockk Unix socket protocol.

**Spec:** `docs/superpowers/specs/2026-05-13-tockk-long-run-animation-measurement-design.md`

---

## File Structure

| File | Responsibility | New / Modified |
|------|----------------|----------------|
| `scripts/tockk_measure_long_run.py` | Local diagnostic CLI: resolve installed Tockk process, verify socket, send repeated test events, collect raw samples, parse summary metrics, write `.local/tockk-measurements/<timestamp>/`. | **Create** |
| `scripts/tests/test_tockk_measure_long_run.py` | Unit tests for parsers, delta summary, event payload shape, and dry-run behavior using fake command runners. | **Create** |
| `.gitignore` | Already ignores `.local/`; no change required. | No change |

No product Swift code changes. No hook/config changes. No public README/docs changes.

---

## Task 1: Parser And Summary Core

Create the script module with pure parsing helpers first. This gives the measurement command a tested foundation before touching live process behavior.

**Files:**
- Create: `scripts/tockk_measure_long_run.py`
- Create: `scripts/tests/test_tockk_measure_long_run.py`

- [ ] **Step 1: Write failing parser tests**

```python
# scripts/tests/test_tockk_measure_long_run.py
import unittest

from scripts import tockk_measure_long_run as measure


class ParserTests(unittest.TestCase):
    def test_parse_size_to_bytes(self):
        self.assertEqual(measure.parse_size_to_bytes("15.5M"), 16_252_928)
        self.assertEqual(measure.parse_size_to_bytes("587.4M"), 615_933_542)
        self.assertEqual(measure.parse_size_to_bytes("10202 KB"), 10_446_848)
        self.assertEqual(measure.parse_size_to_bytes("1.6G"), 1_717_986_918)
        self.assertEqual(measure.parse_size_to_bytes("0K"), 0)

    def test_parse_ps_output(self):
        output = """  PID     ELAPSED    RSS      VSZ COMM
40090       01:24  67952 435614928 /Applications/Tockk.app/Contents/MacOS/Tockk
"""
        process = measure.parse_ps_output(output)
        self.assertEqual(process.pid, 40090)
        self.assertEqual(process.elapsed, "01:24")
        self.assertEqual(process.rss_kb, 67952)
        self.assertEqual(process.vsz_kb, 435614928)
        self.assertEqual(process.command, "/Applications/Tockk.app/Contents/MacOS/Tockk")

    def test_parse_vmmap_summary(self):
        output = """Process:         Tockk [40090]
Physical footprint:         15.5M
Physical footprint (peak):  15.8M
CoreAnimation                       48K      48K      48K       0K       0K       0K       0K        3
IOSurface                            44.6M    44.4M    8256K    36.3M       0K    44.4M       0K       19
AttributeGraph_0x9fc4e0000                  1024K         0K         0K        64K       1392        42K        22K     35%       1
QuartzCore_0x104fc0000                       544K       288K       288K       144K        353        31K       401K     93%      12
"""
        metrics = measure.parse_vmmap_summary(output)
        self.assertEqual(metrics.physical_footprint_bytes, 16_252_928)
        self.assertEqual(metrics.peak_physical_footprint_bytes, 16_567_500)
        self.assertEqual(metrics.coreanimation_region_count, 3)
        self.assertEqual(metrics.iosurface_region_count, 19)
        self.assertEqual(metrics.attributegraph_allocation_count, 1392)
        self.assertEqual(metrics.quartzcore_allocation_count, 353)

    def test_parse_leaks_summary(self):
        output = """Process 40090: 30314 nodes malloced for 10202 KB
Process 40090: 0 leaks for 0 total leaked bytes.
"""
        metrics = measure.parse_leaks_summary(output)
        self.assertEqual(metrics.malloc_nodes, 30314)
        self.assertEqual(metrics.malloced_bytes, 10_446_848)
        self.assertEqual(metrics.leaked_bytes, 0)

    def test_delta_summary_uses_post_cooldown(self):
        before = measure.Sample(
            label="baseline",
            process=measure.ProcessInfo(40090, "00:01", 100, 1000, "/Applications/Tockk.app/Contents/MacOS/Tockk"),
            vmmap=measure.VMMapMetrics(physical_footprint_bytes=1000, peak_physical_footprint_bytes=1200),
            leaks=measure.LeaksMetrics(malloc_nodes=10, malloced_bytes=500, leaked_bytes=0),
        )
        after = measure.Sample(
            label="post-cooldown",
            process=measure.ProcessInfo(40090, "10:00", 250, 1000, "/Applications/Tockk.app/Contents/MacOS/Tockk"),
            vmmap=measure.VMMapMetrics(physical_footprint_bytes=2200, peak_physical_footprint_bytes=3000),
            leaks=measure.LeaksMetrics(malloc_nodes=25, malloced_bytes=900, leaked_bytes=0),
        )
        summary = measure.build_delta_summary(before, after)
        self.assertEqual(summary["rss_kb_delta"], 150)
        self.assertEqual(summary["physical_footprint_bytes_delta"], 1200)
        self.assertEqual(summary["malloc_nodes_delta"], 15)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run parser tests and verify they fail**

Run:

```bash
python3 -m unittest scripts/tests/test_tockk_measure_long_run.py
```

Expected: fail with `ImportError` or `AttributeError` because `scripts/tockk_measure_long_run.py` does not exist yet.

- [ ] **Step 3: Create the parser and summary core**

Create `scripts/tockk_measure_long_run.py` with this content:

```python
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import pathlib
import re
import socket
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from typing import Callable, Iterable


TOCKK_APP_PATH = "/Applications/Tockk.app/Contents/MacOS/Tockk"
DEFAULT_SOCKET_PATH = pathlib.Path.home() / "Library/Application Support/Tockk/tockk.sock"
DEFAULT_OUTPUT_ROOT = pathlib.Path(".local/tockk-measurements")


class MeasurementError(RuntimeError):
    pass


@dataclass(frozen=True)
class ProcessInfo:
    pid: int
    elapsed: str
    rss_kb: int
    vsz_kb: int
    command: str


@dataclass(frozen=True)
class VMMapMetrics:
    physical_footprint_bytes: int | None = None
    peak_physical_footprint_bytes: int | None = None
    attributegraph_allocation_count: int | None = None
    quartzcore_allocation_count: int | None = None
    coreanimation_region_count: int | None = None
    iosurface_region_count: int | None = None


@dataclass(frozen=True)
class LeaksMetrics:
    malloc_nodes: int | None = None
    malloced_bytes: int | None = None
    leaked_bytes: int | None = None


@dataclass(frozen=True)
class Sample:
    label: str
    process: ProcessInfo
    vmmap: VMMapMetrics = field(default_factory=VMMapMetrics)
    leaks: LeaksMetrics = field(default_factory=LeaksMetrics)


def parse_size_to_bytes(raw: str) -> int:
    text = raw.strip()
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)\s*([KMG]|KB|MB|GB)", text)
    if not match:
        raise ValueError(f"unsupported size: {raw!r}")
    value = float(match.group(1))
    unit = match.group(2)
    multiplier = {
        "K": 1024,
        "KB": 1024,
        "M": 1024 ** 2,
        "MB": 1024 ** 2,
        "G": 1024 ** 3,
        "GB": 1024 ** 3,
    }[unit]
    return int(value * multiplier)


def parse_ps_output(output: str) -> ProcessInfo:
    rows = [line.strip() for line in output.splitlines() if line.strip()]
    data_rows = [line for line in rows if not line.startswith("PID")]
    if len(data_rows) != 1:
        raise MeasurementError(f"expected exactly one Tockk process row, got {len(data_rows)}")
    parts = data_rows[0].split(maxsplit=4)
    if len(parts) != 5:
        raise MeasurementError(f"could not parse ps row: {data_rows[0]!r}")
    return ProcessInfo(
        pid=int(parts[0]),
        elapsed=parts[1],
        rss_kb=int(parts[2]),
        vsz_kb=int(parts[3]),
        command=parts[4],
    )


def _last_int(line: str) -> int | None:
    matches = re.findall(r"\b[0-9]+\b", line)
    return int(matches[-1]) if matches else None


def parse_vmmap_summary(output: str) -> VMMapMetrics:
    physical = None
    peak = None
    attributegraph_count = None
    quartzcore_count = None
    coreanimation_count = None
    iosurface_count = None

    for line in output.splitlines():
        stripped = line.strip()
        if stripped.startswith("Physical footprint:"):
            physical = parse_size_to_bytes(stripped.split(":", 1)[1].strip())
        elif stripped.startswith("Physical footprint (peak):"):
            peak = parse_size_to_bytes(stripped.split(":", 1)[1].strip())
        elif stripped.startswith("AttributeGraph_"):
            parts = stripped.split()
            if len(parts) >= 6:
                attributegraph_count = int(parts[5])
        elif stripped.startswith("QuartzCore_"):
            parts = stripped.split()
            if len(parts) >= 6:
                quartzcore_count = int(parts[5])
        elif stripped.startswith("CoreAnimation"):
            coreanimation_count = _last_int(stripped)
        elif stripped.startswith("IOSurface"):
            iosurface_count = _last_int(stripped)

    return VMMapMetrics(
        physical_footprint_bytes=physical,
        peak_physical_footprint_bytes=peak,
        attributegraph_allocation_count=attributegraph_count,
        quartzcore_allocation_count=quartzcore_count,
        coreanimation_region_count=coreanimation_count,
        iosurface_region_count=iosurface_count,
    )


def parse_leaks_summary(output: str) -> LeaksMetrics:
    malloc_nodes = None
    malloced_bytes = None
    leaked_bytes = None
    malloc_match = re.search(r"Process\s+\d+:\s+(\d+)\s+nodes malloced for\s+([0-9.]+\s*[KMG]B?)", output)
    if malloc_match:
        malloc_nodes = int(malloc_match.group(1))
        malloced_bytes = parse_size_to_bytes(malloc_match.group(2))
    leaked_match = re.search(r"Process\s+\d+:\s+\d+\s+leaks for\s+(\d+)\s+total leaked bytes", output)
    if leaked_match:
        leaked_bytes = int(leaked_match.group(1))
    return LeaksMetrics(
        malloc_nodes=malloc_nodes,
        malloced_bytes=malloced_bytes,
        leaked_bytes=leaked_bytes,
    )


def build_delta_summary(baseline: Sample, post_cooldown: Sample) -> dict[str, int | None]:
    def delta(left: int | None, right: int | None) -> int | None:
        if left is None or right is None:
            return None
        return right - left

    return {
        "rss_kb_delta": post_cooldown.process.rss_kb - baseline.process.rss_kb,
        "physical_footprint_bytes_delta": delta(
            baseline.vmmap.physical_footprint_bytes,
            post_cooldown.vmmap.physical_footprint_bytes,
        ),
        "peak_physical_footprint_bytes_delta": delta(
            baseline.vmmap.peak_physical_footprint_bytes,
            post_cooldown.vmmap.peak_physical_footprint_bytes,
        ),
        "malloc_nodes_delta": delta(
            baseline.leaks.malloc_nodes,
            post_cooldown.leaks.malloc_nodes,
        ),
        "malloced_bytes_delta": delta(
            baseline.leaks.malloced_bytes,
            post_cooldown.leaks.malloced_bytes,
        ),
    }
```

- [ ] **Step 4: Run parser tests and verify they pass**

Run:

```bash
python3 -m unittest scripts/tests/test_tockk_measure_long_run.py
```

Expected: `OK`.

- [ ] **Step 5: Commit parser core**

```bash
git add scripts/tockk_measure_long_run.py scripts/tests/test_tockk_measure_long_run.py
git commit -m "test: add long-run measurement parser core"
```

---

## Task 2: Target Discovery And Dry-Run

Add process discovery and dry-run mode without sending events. This validates the installed app target and socket path safely.

**Files:**
- Modify: `scripts/tockk_measure_long_run.py`
- Modify: `scripts/tests/test_tockk_measure_long_run.py`

- [ ] **Step 1: Add failing dry-run tests**

Append to `scripts/tests/test_tockk_measure_long_run.py`:

```python
class FakeRunner:
    def __init__(self, outputs):
        self.outputs = list(outputs)
        self.commands = []

    def __call__(self, command):
        self.commands.append(command)
        if not self.outputs:
            raise AssertionError(f"unexpected command: {command}")
        return self.outputs.pop(0)


class DiscoveryTests(unittest.TestCase):
    def test_find_installed_tockk_process(self):
        runner = FakeRunner([
            """  PID     ELAPSED    RSS      VSZ COMM
40090       01:24  67952 435614928 /Applications/Tockk.app/Contents/MacOS/Tockk
"""
        ])
        process = measure.find_tockk_process(runner=runner)
        self.assertEqual(process.pid, 40090)
        self.assertEqual(runner.commands[0], ["ps", "-axo", "pid,etime,rss,vsz,comm"])

    def test_find_tockk_process_fails_when_missing(self):
        runner = FakeRunner(["  PID     ELAPSED    RSS      VSZ COMM\n"])
        with self.assertRaisesRegex(measure.MeasurementError, "Tockk is not running"):
            measure.find_tockk_process(runner=runner)

    def test_find_tockk_process_fails_when_multiple_installed_apps(self):
        runner = FakeRunner([
            """  PID     ELAPSED    RSS      VSZ COMM
111       00:10  100 1000 /Applications/Tockk.app/Contents/MacOS/Tockk
222       00:20  100 1000 /Applications/Tockk.app/Contents/MacOS/Tockk
"""
        ])
        with self.assertRaisesRegex(measure.MeasurementError, "more than one"):
            measure.find_tockk_process(runner=runner)

    def test_build_run_directory_uses_timestamp(self):
        path = measure.build_run_directory(
            root=measure.pathlib.Path(".local/tockk-measurements"),
            now=measure.dt.datetime(2026, 5, 13, 15, 30, 0),
        )
        self.assertEqual(path.as_posix(), ".local/tockk-measurements/20260513-153000")
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
python3 -m unittest scripts/tests/test_tockk_measure_long_run.py
```

Expected: fail with `AttributeError` for `find_tockk_process` and `build_run_directory`.

- [ ] **Step 3: Implement target discovery and dry-run helpers**

Append to `scripts/tockk_measure_long_run.py`:

```python
CommandRunner = Callable[[list[str]], str]


def run_command(command: list[str]) -> str:
    completed = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    if completed.returncode != 0:
        joined = " ".join(command)
        raise MeasurementError(f"{joined} failed with status {completed.returncode}:\n{completed.stdout}")
    return completed.stdout


def find_tockk_process(runner: CommandRunner = run_command) -> ProcessInfo:
    output = runner(["ps", "-axo", "pid,etime,rss,vsz,comm"])
    lines = output.splitlines()
    header = lines[0] if lines else "  PID     ELAPSED    RSS      VSZ COMM"
    matches = [
        line for line in lines[1:]
        if TOCKK_APP_PATH in line
    ]
    if not matches:
        raise MeasurementError("Tockk is not running. Launch /Applications/Tockk.app first.")
    if len(matches) > 1:
        raise MeasurementError("Found more than one installed Tockk process. Quit duplicates before measuring.")
    return parse_ps_output(header + "\n" + matches[0] + "\n")


def build_run_directory(root: pathlib.Path, now: dt.datetime | None = None) -> pathlib.Path:
    stamp = (now or dt.datetime.now()).strftime("%Y%m%d-%H%M%S")
    return root / stamp


def verify_socket(path: pathlib.Path) -> None:
    if not path.exists():
        raise MeasurementError(f"Tockk socket does not exist: {path}")
    if not stat_is_socket(path):
        raise MeasurementError(f"Tockk socket path is not a socket: {path}")


def stat_is_socket(path: pathlib.Path) -> bool:
    return stat_is_socket_mode(path.stat().st_mode)


def stat_is_socket_mode(mode: int) -> bool:
    import stat
    return stat.S_ISSOCK(mode)
```

- [ ] **Step 4: Add CLI argument parsing and dry-run output**

Append to `scripts/tockk_measure_long_run.py`:

```python
def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Measure long-run Tockk notification memory and animation indicators."
    )
    parser.add_argument("--count", type=int, default=100, help="number of test events to send")
    parser.add_argument("--delay", type=float, default=2.8, help="seconds between events")
    parser.add_argument("--sample-every", type=int, default=25, help="sample every N events")
    parser.add_argument("--cooldown", type=float, default=10.0, help="seconds to wait before post-run sample")
    parser.add_argument("--socket", type=pathlib.Path, default=DEFAULT_SOCKET_PATH)
    parser.add_argument("--output-root", type=pathlib.Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--dry-run", action="store_true", help="resolve target and socket without sending events")
    parser.add_argument("--skip-leaks", action="store_true", help="skip leaks sampling")
    return parser.parse_args(argv)


def dry_run(args: argparse.Namespace, runner: CommandRunner = run_command) -> int:
    process = find_tockk_process(runner=runner)
    verify_socket(args.socket)
    run_dir = build_run_directory(args.output_root)
    print("tockk measurement dry-run")
    print(f"pid: {process.pid}")
    print(f"elapsed: {process.elapsed}")
    print(f"rss_kb: {process.rss_kb}")
    print(f"socket: {args.socket}")
    print(f"planned_events: {args.count}")
    print(f"delay_seconds: {args.delay}")
    print(f"output_dir: {run_dir}")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        if args.dry_run:
            return dry_run(args)
        raise MeasurementError("live measurement is not implemented yet; run --dry-run first")
    except MeasurementError as error:
        print(f"tockk-measure: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 5: Run tests and dry-run**

Run parser/unit tests:

```bash
python3 -m unittest scripts/tests/test_tockk_measure_long_run.py
```

Expected: `OK`.

Run dry-run against the installed app:

```bash
python3 scripts/tockk_measure_long_run.py --dry-run
```

Expected when Tockk is running: prints PID, elapsed time, RSS, socket path, planned event count, delay, output directory.

Expected when Tockk is not running: exits `2` and prints `Tockk is not running. Launch /Applications/Tockk.app first.`

- [ ] **Step 6: Commit dry-run support**

```bash
git add scripts/tockk_measure_long_run.py scripts/tests/test_tockk_measure_long_run.py
git commit -m "feat: add Tockk measurement dry-run target discovery"
```

---

## Task 3: Sampling And Raw Artifact Writing

Implement `ps`, `vmmap -summary`, and optional `leaks` sampling with raw files saved before parsing. Parsing failures should keep raw output on disk and mark fields as unavailable.

**Files:**
- Modify: `scripts/tockk_measure_long_run.py`
- Modify: `scripts/tests/test_tockk_measure_long_run.py`

- [ ] **Step 1: Add failing sampling tests**

Append to `scripts/tests/test_tockk_measure_long_run.py`:

```python
class SamplingTests(unittest.TestCase):
    def test_collect_sample_writes_raw_outputs(self):
        with measure.tempfile.TemporaryDirectory() as temp_dir:
            run_dir = measure.pathlib.Path(temp_dir)
            runner = FakeRunner([
                """  PID     ELAPSED    RSS      VSZ COMM
40090       01:24  67952 435614928 /Applications/Tockk.app/Contents/MacOS/Tockk
""",
                "Physical footprint:         15.5M\nPhysical footprint (peak):  15.8M\n",
                "Process 40090: 30314 nodes malloced for 10202 KB\nProcess 40090: 0 leaks for 0 total leaked bytes.\n",
            ])
            sample = measure.collect_sample(
                label="baseline",
                pid=40090,
                run_dir=run_dir,
                runner=runner,
                include_leaks=True,
            )
            self.assertEqual(sample.label, "baseline")
            self.assertTrue((run_dir / "baseline.ps.txt").exists())
            self.assertTrue((run_dir / "baseline.vmmap.txt").exists())
            self.assertTrue((run_dir / "baseline.leaks.txt").exists())
            self.assertEqual(sample.leaks.malloc_nodes, 30314)

    def test_write_summary_json(self):
        with measure.tempfile.TemporaryDirectory() as temp_dir:
            run_dir = measure.pathlib.Path(temp_dir)
            sample = measure.Sample(
                label="baseline",
                process=measure.ProcessInfo(40090, "00:01", 100, 1000, "/Applications/Tockk.app/Contents/MacOS/Tockk"),
            )
            measure.write_summary_json(run_dir, {"event_count": 0}, [sample])
            payload = measure.json.loads((run_dir / "summary.json").read_text())
            self.assertEqual(payload["config"]["event_count"], 0)
            self.assertEqual(payload["samples"][0]["label"], "baseline")
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
python3 -m unittest scripts/tests/test_tockk_measure_long_run.py
```

Expected: fail with `AttributeError` for `collect_sample`, `write_summary_json`, and `tempfile`.

- [ ] **Step 3: Add sampling implementation**

Modify imports at the top of `scripts/tockk_measure_long_run.py`:

```python
import tempfile
```

Append:

```python
def write_text(path: pathlib.Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def collect_sample(
    *,
    label: str,
    pid: int,
    run_dir: pathlib.Path,
    runner: CommandRunner = run_command,
    include_leaks: bool = True,
) -> Sample:
    ps_output = runner(["ps", "-p", str(pid), "-o", "pid,etime,rss,vsz,comm"])
    write_text(run_dir / f"{label}.ps.txt", ps_output)
    process = parse_ps_output(ps_output)

    vmmap_output = runner(["vmmap", "-summary", str(pid)])
    write_text(run_dir / f"{label}.vmmap.txt", vmmap_output)
    vmmap_metrics = parse_vmmap_summary(vmmap_output)

    leaks_metrics = LeaksMetrics()
    if include_leaks:
        leaks_output = runner(["leaks", str(pid)])
        write_text(run_dir / f"{label}.leaks.txt", leaks_output)
        leaks_metrics = parse_leaks_summary(leaks_output)

    return Sample(
        label=label,
        process=process,
        vmmap=vmmap_metrics,
        leaks=leaks_metrics,
    )


def write_summary_json(run_dir: pathlib.Path, config: dict, samples: list[Sample]) -> None:
    payload = {
        "config": config,
        "samples": [asdict(sample) for sample in samples],
    }
    write_text(run_dir / "summary.json", json.dumps(payload, indent=2, sort_keys=True) + "\n")
```

- [ ] **Step 4: Run tests**

Run:

```bash
python3 -m unittest scripts/tests/test_tockk_measure_long_run.py
```

Expected: `OK`.

- [ ] **Step 5: Commit sampling**

```bash
git add scripts/tockk_measure_long_run.py scripts/tests/test_tockk_measure_long_run.py
git commit -m "feat: collect raw Tockk measurement samples"
```

---

## Task 4: Event Sending And Live Run Orchestration

Send test events through the real Unix socket, sample at baseline/midpoints/final/post-cooldown, and write a concise terminal summary.

**Files:**
- Modify: `scripts/tockk_measure_long_run.py`
- Modify: `scripts/tests/test_tockk_measure_long_run.py`

- [ ] **Step 1: Add failing event and orchestration tests**

Append to `scripts/tests/test_tockk_measure_long_run.py`:

```python
class EventPayloadTests(unittest.TestCase):
    def test_build_event_payload_has_protocol_fields(self):
        payload = measure.build_event_payload(index=7, total=100)
        event = measure.json.loads(payload)
        self.assertEqual(event["agent"], "tockk-measure")
        self.assertEqual(event["project"], "long-run")
        self.assertEqual(event["status"], "info")
        self.assertEqual(event["title"], "Long-run measurement 7/100")
        self.assertIn("timestamp", event)

    def test_sample_labels_for_count(self):
        labels = measure.sample_labels_for_count(count=100, sample_every=25)
        self.assertEqual(labels, {25: "event-0025", 50: "event-0050", 75: "event-0075", 100: "final"})
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
python3 -m unittest scripts/tests/test_tockk_measure_long_run.py
```

Expected: fail with `AttributeError` for `build_event_payload` and `sample_labels_for_count`.

- [ ] **Step 3: Implement event payload and socket send**

Append to `scripts/tockk_measure_long_run.py`:

```python
def build_event_payload(index: int, total: int) -> str:
    event = {
        "agent": "tockk-measure",
        "project": "long-run",
        "status": "info",
        "title": f"Long-run measurement {index}/{total}",
        "summary": "Synthetic local event for Tockk long-run animation diagnostics.",
        "durationMs": 1000,
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    return json.dumps(event, separators=(",", ":")) + "\n"


def send_event(socket_path: pathlib.Path, payload: str) -> None:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.connect(str(socket_path))
        client.sendall(payload.encode("utf-8"))


def sample_labels_for_count(count: int, sample_every: int) -> dict[int, str]:
    labels: dict[int, str] = {}
    if sample_every > 0:
        for index in range(sample_every, count + 1, sample_every):
            labels[index] = f"event-{index:04d}"
    labels[count] = "final"
    return labels
```

- [ ] **Step 4: Implement live orchestration**

Replace the `main()` body branch that currently raises `live measurement is not implemented yet` with:

```python
        if args.dry_run:
            return dry_run(args)
        return run_measurement(args)
```

Append:

```python
def run_measurement(args: argparse.Namespace, runner: CommandRunner = run_command) -> int:
    if args.count <= 0:
        raise MeasurementError("--count must be greater than zero")
    if args.delay < 0:
        raise MeasurementError("--delay must be zero or greater")
    if args.sample_every < 0:
        raise MeasurementError("--sample-every must be zero or greater")

    process = find_tockk_process(runner=runner)
    verify_socket(args.socket)

    run_dir = build_run_directory(args.output_root)
    run_dir.mkdir(parents=True, exist_ok=False)

    labels = sample_labels_for_count(args.count, args.sample_every)
    samples: list[Sample] = []
    config = {
        "pid": process.pid,
        "event_count": args.count,
        "delay_seconds": args.delay,
        "sample_every": args.sample_every,
        "cooldown_seconds": args.cooldown,
        "socket": str(args.socket),
        "skip_leaks": args.skip_leaks,
        "output_dir": str(run_dir),
    }

    print(f"tockk-measure: writing run to {run_dir}")
    samples.append(collect_sample(
        label="baseline",
        pid=process.pid,
        run_dir=run_dir,
        runner=runner,
        include_leaks=not args.skip_leaks,
    ))

    for index in range(1, args.count + 1):
        send_event(args.socket, build_event_payload(index, args.count))
        if index in labels:
            samples.append(collect_sample(
                label=labels[index],
                pid=process.pid,
                run_dir=run_dir,
                runner=runner,
                include_leaks=not args.skip_leaks,
            ))
        if index != args.count:
            time.sleep(args.delay)

    if args.cooldown > 0:
        time.sleep(args.cooldown)
    samples.append(collect_sample(
        label="post-cooldown",
        pid=process.pid,
        run_dir=run_dir,
        runner=runner,
        include_leaks=not args.skip_leaks,
    ))

    delta = build_delta_summary(samples[0], samples[-1])
    config["post_cooldown_delta"] = delta
    write_summary_json(run_dir, config, samples)
    print_delta_summary(delta)
    print(f"tockk-measure: raw output saved to {run_dir}")
    return 0


def print_delta_summary(delta: dict[str, int | None]) -> None:
    print("post-cooldown delta from baseline:")
    for key in [
        "rss_kb_delta",
        "physical_footprint_bytes_delta",
        "peak_physical_footprint_bytes_delta",
        "malloc_nodes_delta",
        "malloced_bytes_delta",
    ]:
        value = delta.get(key)
        print(f"  {key}: {'unavailable' if value is None else value}")
```

- [ ] **Step 5: Run tests**

Run:

```bash
python3 -m unittest scripts/tests/test_tockk_measure_long_run.py
```

Expected: `OK`.

- [ ] **Step 6: Run dry-run again**

Run:

```bash
python3 scripts/tockk_measure_long_run.py --dry-run
```

Expected: prints PID/config and sends no notification.

- [ ] **Step 7: Commit orchestration**

```bash
git add scripts/tockk_measure_long_run.py scripts/tests/test_tockk_measure_long_run.py
git commit -m "feat: send repeated Tockk measurement events"
```

---

## Task 5: Live Smoke Verification

Run the actual 100-event smoke test against `/Applications/Tockk.app`, preserving raw outputs under `.local/`.

**Files:**
- No source edits expected.
- Runtime output: `.local/tockk-measurements/<timestamp>/` (ignored by git).

- [ ] **Step 1: Confirm clean worktree**

Run:

```bash
git status --short
```

Expected: no unstaged source changes.

- [ ] **Step 2: Confirm installed app is running**

Run:

```bash
python3 scripts/tockk_measure_long_run.py --dry-run
```

Expected: prints the installed app PID and socket path.

- [ ] **Step 3: Run a short 5-event sanity check**

Run:

```bash
python3 scripts/tockk_measure_long_run.py --count 5 --delay 2.8 --sample-every 5 --cooldown 5
```

Expected:
- five Tockk notifications appear,
- command exits `0`,
- output directory is printed,
- `summary.json`, `baseline.*`, `final.*`, and `post-cooldown.*` files exist under `.local/tockk-measurements/<timestamp>/`.

- [ ] **Step 4: Run the 100-event smoke test**

Run:

```bash
python3 scripts/tockk_measure_long_run.py --count 100 --delay 2.8 --sample-every 25 --cooldown 10
```

Expected:
- command exits `0`,
- samples exist for `baseline`, `event-0025`, `event-0050`, `event-0075`, `final`, and `post-cooldown`,
- terminal prints `post-cooldown delta from baseline`,
- raw logs remain only under `.local/`.

- [ ] **Step 5: Inspect summary**

Run:

```bash
RUN_DIR="$(ls -td .local/tockk-measurements/* | head -n 1)"
python3 -m json.tool "$RUN_DIR/summary.json"
```

Expected:
- JSON is valid,
- `config.event_count` is `100`,
- `config.post_cooldown_delta` includes RSS, footprint, peak footprint, malloc nodes, and malloced bytes deltas.

- [ ] **Step 6: Confirm no local artifacts are tracked**

Run:

```bash
git status --short --ignored .local scripts docs/superpowers/plans
```

Expected:
- source files under `scripts/` are tracked or clean,
- `.local/` appears only as ignored output,
- no raw measurement files are staged.

---

## Self-Review Against Spec

- Spec target app: covered by `TOCKK_APP_PATH` and `find_tockk_process`.
- No product code changes: plan only creates `scripts/tockk_measure_long_run.py` and tests.
- `.local/` runtime artifacts: covered by `DEFAULT_OUTPUT_ROOT`, `build_run_directory`, and live verification.
- Dry-run: covered by Task 2.
- 100-event smoke and later 500-event support: `--count` supports both; Task 5 runs 100.
- Metrics: `ps`, `vmmap -summary`, and `leaks` raw output plus parsed summary are covered.
- Error handling: missing app, duplicate app processes, missing/non-socket socket path, and command failures are explicit.
- Security: no network, no settings edits, only local socket events and process inspection.
- Completeness scan: all implementation steps include concrete file paths, commands, and code.

#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import socket
import stat
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from typing import Callable


TOCKK_APP_PATH = "/Applications/Tockk.app/Contents/MacOS/Tockk"
DEFAULT_SOCKET_PATH = pathlib.Path.home() / "Library/Application Support/Tockk/tockk.sock"
DEFAULT_OUTPUT_ROOT = pathlib.Path(".local/tockk-measurements")
CommandRunner = Callable[[list[str]], str]
EventSender = Callable[[pathlib.Path, str], None]
Sleeper = Callable[[float], None]
SocketVerifier = Callable[[pathlib.Path], None]
SocketFactory = Callable[[int, int], socket.socket]


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
    attributegraph_size_bytes: int | None = None
    quartzcore_size_bytes: int | None = None
    coreanimation_size_bytes: int | None = None
    iosurface_size_bytes: int | None = None


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


def run_command(command: list[str]) -> str:
    command_text = " ".join(command)
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=False)
    except OSError as error:
        raise MeasurementError(f"failed to start command ({command_text}): {error}") from error
    output = f"{result.stdout}{result.stderr}"
    if result.returncode != 0:
        raise MeasurementError(f"command failed ({command_text}): {output.strip()}")
    return output


def run_leaks_command(command: list[str]) -> str:
    command_text = " ".join(command)
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=False)
    except OSError as error:
        raise MeasurementError(f"failed to start command ({command_text}): {error}") from error
    output = f"{result.stdout}{result.stderr}"
    if result.returncode not in (0, 1):
        raise MeasurementError(f"command failed ({command_text}): {output.strip()}")
    return output


def write_text(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def collect_sample(
    label: str,
    pid: int,
    run_dir: pathlib.Path,
    runner: CommandRunner = run_command,
    leaks_runner: CommandRunner | None = None,
    include_leaks: bool = True,
) -> Sample:
    ps_output = runner(["ps", "-p", str(pid), "-o", "pid,etime,rss,vsz,comm"])
    write_text(run_dir / f"{label}.ps.txt", ps_output)
    process = parse_ps_output(ps_output)

    vmmap_output = runner(["vmmap", "-summary", str(pid)])
    write_text(run_dir / f"{label}.vmmap.txt", vmmap_output)
    try:
        vmmap = parse_vmmap_summary(vmmap_output)
    except (MeasurementError, ValueError, IndexError):
        vmmap = VMMapMetrics()

    leaks = LeaksMetrics()
    if include_leaks:
        active_leaks_runner = leaks_runner or (run_leaks_command if runner is run_command else runner)
        leaks_output = active_leaks_runner(["leaks", str(pid)])
        write_text(run_dir / f"{label}.leaks.txt", leaks_output)
        try:
            leaks = parse_leaks_summary(leaks_output)
        except (MeasurementError, ValueError, IndexError):
            leaks = LeaksMetrics()

    return Sample(
        label=label,
        process=process,
        vmmap=vmmap,
        leaks=leaks,
    )


def write_summary_json(
    run_dir: pathlib.Path,
    config: dict,
    samples: list[Sample],
    status: str = "success",
    failure: dict[str, str | int | None] | None = None,
) -> None:
    payload = {
        "status": status,
        "config": config,
        "samples": [asdict(sample) for sample in samples],
    }
    if failure is not None:
        payload["failure"] = failure
    write_text(run_dir / "summary.json", json.dumps(payload, indent=2, sort_keys=True))


def find_tockk_process(runner: CommandRunner = run_command) -> ProcessInfo:
    command = ["ps", "-axo", "pid,etime,rss,vsz,comm"]
    output = runner(command)
    rows = [line for line in output.splitlines() if line.strip()]
    header = rows[0] if rows else "PID ELAPSED RSS VSZ COMM"
    matches = []
    for line in rows[1:]:
        parts = line.split(maxsplit=4)
        if len(parts) == 5 and parts[4] == TOCKK_APP_PATH:
            matches.append(line)
    if not matches:
        raise MeasurementError(f"Tockk is not running at {TOCKK_APP_PATH}")
    if len(matches) > 1:
        raise MeasurementError(f"found more than one installed Tockk process at {TOCKK_APP_PATH}")
    return parse_ps_output(f"{header}\n{matches[0]}\n")


def build_run_directory(root: pathlib.Path, now: dt.datetime | None = None) -> pathlib.Path:
    timestamp = (now or dt.datetime.now()).strftime("%Y%m%d-%H%M%S")
    return root / timestamp


def stat_is_socket_mode(mode: int) -> bool:
    return stat.S_ISSOCK(mode)


def stat_is_socket(path: pathlib.Path) -> bool:
    return stat_is_socket_mode(path.stat().st_mode)


def verify_socket(path: pathlib.Path) -> None:
    try:
        path_stat = path.stat()
    except FileNotFoundError as error:
        raise MeasurementError(f"socket does not exist: {path}") from error
    except PermissionError as error:
        raise MeasurementError(f"permission denied while checking socket: {path}") from error
    except OSError as error:
        raise MeasurementError(f"failed to check socket: {path}: {error}") from error
    if not stat_is_socket_mode(path_stat.st_mode):
        raise MeasurementError(f"path is not a socket: {path}")


def probe_socket_connection(
    path: pathlib.Path,
    socket_verifier: SocketVerifier = verify_socket,
    socket_factory: SocketFactory = socket.socket,
) -> None:
    socket_verifier(path)
    try:
        with socket_factory(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.connect(str(path))
    except OSError as error:
        raise MeasurementError(f"failed to connect to socket {path}: {error}") from error


def positive_int(raw: str) -> int:
    try:
        value = int(raw)
    except ValueError as error:
        raise argparse.ArgumentTypeError(f"must be an integer: {raw}") from error
    if value <= 0:
        raise argparse.ArgumentTypeError("must be greater than 0")
    return value


def non_negative_int(raw: str) -> int:
    try:
        value = int(raw)
    except ValueError as error:
        raise argparse.ArgumentTypeError(f"must be an integer: {raw}") from error
    if value < 0:
        raise argparse.ArgumentTypeError("must be greater than or equal to 0")
    return value


def non_negative_float(raw: str) -> float:
    try:
        value = float(raw)
    except ValueError as error:
        raise argparse.ArgumentTypeError(f"must be a number: {raw}") from error
    if value < 0:
        raise argparse.ArgumentTypeError("must be greater than or equal to 0")
    return value


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Measure Tockk long-run memory behavior.")
    parser.add_argument("--count", type=positive_int, default=100)
    parser.add_argument("--delay", type=non_negative_float, default=2.8)
    parser.add_argument("--sample-every", type=non_negative_int, default=25)
    parser.add_argument("--cooldown", type=non_negative_float, default=10.0)
    parser.add_argument("--socket", type=pathlib.Path, default=DEFAULT_SOCKET_PATH)
    parser.add_argument("--output-root", type=pathlib.Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-leaks", action="store_true")
    return parser.parse_args(argv)


def dry_run(
    args: argparse.Namespace,
    runner: CommandRunner = run_command,
    socket_verifier: SocketVerifier = probe_socket_connection,
) -> int:
    process = find_tockk_process(runner)
    socket_verifier(args.socket)
    output_dir = build_run_directory(args.output_root)
    print("tockk measurement dry-run")
    print(f"pid: {process.pid}")
    print(f"elapsed: {process.elapsed}")
    print(f"rss_kb: {process.rss_kb}")
    print(f"socket: {args.socket}")
    print(f"planned_events: {args.count}")
    print(f"delay_seconds: {args.delay}")
    print(f"output_dir: {output_dir}")
    return 0


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse_args(sys.argv[1:] if argv is None else argv)
        if args.dry_run:
            return dry_run(args)
        return run_measurement(args)
    except MeasurementError as error:
        print(f"tockk-measure: {error}", file=sys.stderr)
        return 2


def _last_int(line: str) -> int | None:
    matches = re.findall(r"\b[0-9]+\b", line)
    return int(matches[-1]) if matches else None


def _first_size_after_name(line: str) -> int | None:
    parts = line.split()
    if len(parts) < 2:
        return None
    return parse_size_to_bytes(parts[1])


def parse_vmmap_summary(output: str) -> VMMapMetrics:
    physical = None
    peak = None
    attributegraph_count = None
    quartzcore_count = None
    coreanimation_count = None
    iosurface_count = None
    attributegraph_size = None
    quartzcore_size = None
    coreanimation_size = None
    iosurface_size = None

    for line in output.splitlines():
        stripped = line.strip()
        if stripped.startswith("Physical footprint:"):
            physical = parse_size_to_bytes(stripped.split(":", 1)[1].strip())
        elif stripped.startswith("Physical footprint (peak):"):
            peak = parse_size_to_bytes(stripped.split(":", 1)[1].strip())
        elif stripped.startswith("AttributeGraph_"):
            parts = stripped.split()
            if len(parts) >= 6:
                attributegraph_size = _first_size_after_name(stripped)
                attributegraph_count = int(parts[5])
        elif stripped.startswith("QuartzCore_"):
            parts = stripped.split()
            if len(parts) >= 6:
                quartzcore_size = _first_size_after_name(stripped)
                quartzcore_count = int(parts[5])
        elif stripped.startswith("CoreAnimation"):
            coreanimation_size = _first_size_after_name(stripped)
            coreanimation_count = _last_int(stripped)
        elif stripped.startswith("IOSurface"):
            iosurface_size = _first_size_after_name(stripped)
            iosurface_count = _last_int(stripped)

    return VMMapMetrics(
        physical_footprint_bytes=physical,
        peak_physical_footprint_bytes=peak,
        attributegraph_allocation_count=attributegraph_count,
        quartzcore_allocation_count=quartzcore_count,
        coreanimation_region_count=coreanimation_count,
        iosurface_region_count=iosurface_count,
        attributegraph_size_bytes=attributegraph_size,
        quartzcore_size_bytes=quartzcore_size,
        coreanimation_size_bytes=coreanimation_size,
        iosurface_size_bytes=iosurface_size,
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
        "leaked_bytes_delta": delta(
            baseline.leaks.leaked_bytes,
            post_cooldown.leaks.leaked_bytes,
        ),
    }


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
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.connect(str(socket_path))
            client.sendall(payload.encode("utf-8"))
    except OSError as error:
        raise MeasurementError(f"failed to send event to socket {socket_path}: {error}") from error


def sample_labels_for_count(count: int, sample_every: int) -> dict[int, str]:
    if count <= 0:
        raise MeasurementError("--count must be greater than zero")
    if sample_every < 0:
        raise MeasurementError("--sample-every must be zero or greater")

    labels: dict[int, str] = {}
    if sample_every > 0:
        for index in range(sample_every, count + 1, sample_every):
            labels[index] = f"event-{index:04d}"
    labels[count] = "final"
    return labels


def run_measurement(
    args: argparse.Namespace,
    runner: CommandRunner = run_command,
    sender: EventSender = send_event,
    sleeper: Sleeper = time.sleep,
    socket_verifier: SocketVerifier = probe_socket_connection,
) -> int:
    if args.count <= 0:
        raise MeasurementError("--count must be greater than zero")
    if args.delay < 0:
        raise MeasurementError("--delay must be zero or greater")
    if args.sample_every < 0:
        raise MeasurementError("--sample-every must be zero or greater")
    if args.cooldown < 0:
        raise MeasurementError("--cooldown must be zero or greater")

    process = find_tockk_process(runner=runner)
    socket_verifier(args.socket)

    run_dir = build_run_directory(args.output_root)
    run_dir.mkdir(parents=True, exist_ok=False)

    labels = sample_labels_for_count(args.count, args.sample_every)
    samples: list[Sample] = []
    last_attempted_event: int | None = None
    last_sent_event: int | None = None
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

    try:
        print(f"tockk-measure: writing run to {run_dir}")
        samples.append(
            collect_sample(
                label="baseline",
                pid=process.pid,
                run_dir=run_dir,
                runner=runner,
                include_leaks=not args.skip_leaks,
            )
        )

        for index in range(1, args.count + 1):
            last_attempted_event = index
            sender(args.socket, build_event_payload(index, args.count))
            last_sent_event = index
            if index in labels:
                samples.append(
                    collect_sample(
                        label=labels[index],
                        pid=process.pid,
                        run_dir=run_dir,
                        runner=runner,
                        include_leaks=not args.skip_leaks,
                    )
                )
            if index != args.count:
                sleeper(args.delay)

        if args.cooldown > 0:
            sleeper(args.cooldown)
        samples.append(
            collect_sample(
                label="post-cooldown",
                pid=process.pid,
                run_dir=run_dir,
                runner=runner,
                include_leaks=not args.skip_leaks,
            )
        )

        delta = build_delta_summary(samples[0], samples[-1])
        config["post_cooldown_delta"] = delta
        write_summary_json(run_dir, config, samples)
        print_delta_summary(delta)
        print(f"tockk-measure: raw output saved to {run_dir}")
        return 0
    except MeasurementError as error:
        write_summary_json(
            run_dir,
            config,
            samples,
            status="failure",
            failure={
                "message": str(error),
                "last_attempted_event": last_attempted_event,
                "last_sent_event": last_sent_event,
            },
        )
        raise


def print_delta_summary(delta: dict[str, int | None]) -> None:
    print("post-cooldown delta from baseline:")
    for key in [
        "rss_kb_delta",
        "physical_footprint_bytes_delta",
        "peak_physical_footprint_bytes_delta",
        "malloc_nodes_delta",
        "malloced_bytes_delta",
        "leaked_bytes_delta",
    ]:
        value = delta.get(key)
        print(f"  {key}: {'unavailable' if value is None else value}")


if __name__ == "__main__":
    raise SystemExit(main())

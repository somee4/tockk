#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
from dataclasses import dataclass, field


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

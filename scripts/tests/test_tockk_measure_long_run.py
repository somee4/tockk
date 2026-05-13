import json
import tempfile
import unittest

from scripts import tockk_measure_long_run as measure


class FakeRunner:
    def __init__(self, outputs):
        self.outputs = list(outputs)
        self.commands = []

    def __call__(self, command):
        self.commands.append(command)
        return self.outputs.pop(0)


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
        self.assertEqual(metrics.coreanimation_size_bytes, 49_152)
        self.assertEqual(metrics.coreanimation_region_count, 3)
        self.assertEqual(metrics.iosurface_size_bytes, 46_766_489)
        self.assertEqual(metrics.iosurface_region_count, 19)
        self.assertEqual(metrics.attributegraph_size_bytes, 1_048_576)
        self.assertEqual(metrics.attributegraph_allocation_count, 1392)
        self.assertEqual(metrics.quartzcore_size_bytes, 557_056)
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
            leaks=measure.LeaksMetrics(malloc_nodes=25, malloced_bytes=900, leaked_bytes=10),
        )
        summary = measure.build_delta_summary(before, after)
        self.assertEqual(summary["rss_kb_delta"], 150)
        self.assertEqual(summary["physical_footprint_bytes_delta"], 1200)
        self.assertEqual(summary["malloc_nodes_delta"], 15)
        self.assertEqual(summary["leaked_bytes_delta"], 10)

    def test_parse_args_rejects_invalid_count(self):
        for value in ["0", "-1"]:
            with self.subTest(value=value):
                with self.assertRaises(SystemExit):
                    measure.parse_args(["--count", value])

    def test_parse_args_rejects_invalid_sample_every(self):
        with self.assertRaises(SystemExit):
            measure.parse_args(["--sample-every", "0"])

    def test_parse_args_rejects_invalid_delay(self):
        with self.assertRaises(SystemExit):
            measure.parse_args(["--delay", "-0.1"])

    def test_parse_args_rejects_invalid_cooldown(self):
        with self.assertRaises(SystemExit):
            measure.parse_args(["--cooldown", "-1"])


class ArtifactCollectionTests(unittest.TestCase):
    def test_collect_sample_creates_missing_run_dir_for_raw_outputs(self):
        ps_output = """  PID     ELAPSED    RSS      VSZ COMM
40090       01:24  67952 435614928 /Applications/Tockk.app/Contents/MacOS/Tockk
"""
        vmmap_output = """Process:         Tockk [40090]
Physical footprint:         15.5M
"""

        with tempfile.TemporaryDirectory() as directory:
            run_dir = measure.pathlib.Path(directory) / "missing" / "run"
            runner = FakeRunner([ps_output, vmmap_output])

            measure.collect_sample(
                label="baseline",
                pid=40090,
                run_dir=run_dir,
                runner=runner,
                include_leaks=False,
            )

            self.assertTrue((run_dir / "baseline.ps.txt").exists())
            self.assertTrue((run_dir / "baseline.vmmap.txt").exists())

    def test_collect_sample_writes_raw_outputs(self):
        ps_output = """  PID     ELAPSED    RSS      VSZ COMM
40090       01:24  67952 435614928 /Applications/Tockk.app/Contents/MacOS/Tockk
"""
        vmmap_output = """Process:         Tockk [40090]
Physical footprint:         15.5M
Physical footprint (peak):  15.8M
"""
        leaks_output = """Process 40090: 30314 nodes malloced for 10202 KB
Process 40090: 0 leaks for 0 total leaked bytes.
"""

        with tempfile.TemporaryDirectory() as directory:
            run_dir = measure.pathlib.Path(directory)
            runner = FakeRunner([ps_output, vmmap_output, leaks_output])

            sample = measure.collect_sample(
                label="baseline",
                pid=40090,
                run_dir=run_dir,
                runner=runner,
                include_leaks=True,
            )

            self.assertTrue((run_dir / "baseline.ps.txt").exists())
            self.assertTrue((run_dir / "baseline.vmmap.txt").exists())
            self.assertTrue((run_dir / "baseline.leaks.txt").exists())
            self.assertEqual(sample.leaks.malloc_nodes, 30314)
            self.assertEqual(
                runner.commands,
                [
                    ["ps", "-p", "40090", "-o", "pid,etime,rss,vsz,comm"],
                    ["vmmap", "-summary", "40090"],
                    ["leaks", "40090"],
                ],
            )

    def test_collect_sample_skips_leaks_when_disabled(self):
        ps_output = """  PID     ELAPSED    RSS      VSZ COMM
40090       01:24  67952 435614928 /Applications/Tockk.app/Contents/MacOS/Tockk
"""
        vmmap_output = """Process:         Tockk [40090]
Physical footprint:         15.5M
"""

        with tempfile.TemporaryDirectory() as directory:
            run_dir = measure.pathlib.Path(directory)
            runner = FakeRunner([ps_output, vmmap_output])

            sample = measure.collect_sample(
                label="baseline",
                pid=40090,
                run_dir=run_dir,
                runner=runner,
                include_leaks=False,
            )

            self.assertTrue((run_dir / "baseline.ps.txt").exists())
            self.assertTrue((run_dir / "baseline.vmmap.txt").exists())
            self.assertFalse((run_dir / "baseline.leaks.txt").exists())
            self.assertIsNone(sample.leaks.malloc_nodes)
            self.assertIsNone(sample.leaks.malloced_bytes)
            self.assertIsNone(sample.leaks.leaked_bytes)
            self.assertEqual(
                runner.commands,
                [
                    ["ps", "-p", "40090", "-o", "pid,etime,rss,vsz,comm"],
                    ["vmmap", "-summary", "40090"],
                ],
            )

    def test_write_summary_json(self):
        sample = measure.Sample(
            label="baseline",
            process=measure.ProcessInfo(40090, "00:01", 100, 1000, "/Applications/Tockk.app/Contents/MacOS/Tockk"),
            vmmap=measure.VMMapMetrics(physical_footprint_bytes=1000),
            leaks=measure.LeaksMetrics(malloc_nodes=30314, malloced_bytes=10_446_848, leaked_bytes=0),
        )

        with tempfile.TemporaryDirectory() as directory:
            run_dir = measure.pathlib.Path(directory)

            measure.write_summary_json(run_dir, {"event_count": 0}, [sample])

            payload = json.loads((run_dir / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(payload["config"], {"event_count": 0})
            self.assertEqual(payload["samples"][0]["label"], "baseline")

    def test_write_summary_json_creates_missing_run_dir(self):
        with tempfile.TemporaryDirectory() as directory:
            run_dir = measure.pathlib.Path(directory) / "missing" / "run"

            measure.write_summary_json(run_dir, {"event_count": 0}, [])

            payload = json.loads((run_dir / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(payload["config"], {"event_count": 0})
            self.assertEqual(payload["samples"], [])


class TargetDiscoveryTests(unittest.TestCase):
    def test_run_command_wraps_oserror_with_command_context(self):
        def raise_oserror(command, capture_output, text, check):
            raise OSError(1, "Operation not permitted", "ps")

        original_run = measure.subprocess.run
        measure.subprocess.run = raise_oserror
        try:
            with self.assertRaisesRegex(measure.MeasurementError, "failed to start command.*ps"):
                measure.run_command(["ps", "-axo", "pid,etime,rss,vsz,comm"])
        finally:
            measure.subprocess.run = original_run

    def test_run_leaks_command_accepts_exit_1_and_returns_output(self):
        class Completed:
            stdout = "Process 40090: 1 leaks for 16 total leaked bytes.\n"
            stderr = "warning: leak details\n"
            returncode = 1

        def fake_run(command, capture_output, text, check):
            return Completed()

        original_run = measure.subprocess.run
        measure.subprocess.run = fake_run
        try:
            output = measure.run_leaks_command(["leaks", "40090"])
        finally:
            measure.subprocess.run = original_run

        self.assertIn("1 leaks", output)
        self.assertIn("warning: leak details", output)

    def test_run_leaks_command_rejects_other_nonzero_exit_codes(self):
        class Completed:
            stdout = ""
            stderr = "leaks: cannot examine process\n"
            returncode = 2

        def fake_run(command, capture_output, text, check):
            return Completed()

        original_run = measure.subprocess.run
        measure.subprocess.run = fake_run
        try:
            with self.assertRaisesRegex(measure.MeasurementError, "command failed"):
                measure.run_leaks_command(["leaks", "40090"])
        finally:
            measure.subprocess.run = original_run

    def test_find_installed_tockk_process(self):
        runner = FakeRunner([
            """  PID     ELAPSED    RSS      VSZ COMM
12345       05:00   1000     2000 /usr/bin/other
40090       01:24  67952 435614928 /Applications/Tockk.app/Contents/MacOS/Tockk
"""
        ])

        process = measure.find_tockk_process(runner)

        self.assertEqual(process.pid, 40090)
        self.assertEqual(runner.commands, [["ps", "-axo", "pid,etime,rss,vsz,comm"]])

    def test_find_tockk_process_ignores_helper_and_selects_exact_app_command(self):
        runner = FakeRunner([
            """  PID     ELAPSED    RSS      VSZ COMM
40089       01:23  67951 435614927 /Applications/Tockk.app/Contents/MacOS/Tockk-helper
40090       01:24  67952 435614928 /Applications/Tockk.app/Contents/MacOS/Tockk
"""
        ])

        process = measure.find_tockk_process(runner)

        self.assertEqual(process.pid, 40090)
        self.assertEqual(process.command, "/Applications/Tockk.app/Contents/MacOS/Tockk")

    def test_find_tockk_process_fails_when_missing(self):
        runner = FakeRunner(["  PID     ELAPSED    RSS      VSZ COMM\n"])

        with self.assertRaisesRegex(measure.MeasurementError, "Tockk is not running"):
            measure.find_tockk_process(runner)

    def test_find_tockk_process_fails_when_multiple_installed_apps(self):
        runner = FakeRunner([
            """  PID     ELAPSED    RSS      VSZ COMM
40090       01:24  67952 435614928 /Applications/Tockk.app/Contents/MacOS/Tockk
40091       01:25  67953 435614929 /Applications/Tockk.app/Contents/MacOS/Tockk
"""
        ])

        with self.assertRaisesRegex(measure.MeasurementError, "more than one"):
            measure.find_tockk_process(runner)

    def test_build_run_directory_uses_timestamp(self):
        root = measure.pathlib.Path(".local/tockk-measurements")
        now = measure.dt.datetime(2026, 5, 13, 15, 30, 0)

        result = measure.build_run_directory(root, now)

        self.assertEqual(result, measure.pathlib.Path(".local/tockk-measurements/20260513-153000"))

    def test_verify_socket_wraps_missing_path(self):
        with tempfile.TemporaryDirectory() as directory:
            missing_path = measure.pathlib.Path(directory) / "missing.sock"

            with self.assertRaisesRegex(measure.MeasurementError, "socket does not exist"):
                measure.verify_socket(missing_path)

    def test_verify_socket_wraps_stat_oserror(self):
        class StatFailurePath:
            def stat(self):
                raise OSError("stat failed")

            def __str__(self):
                return "/tmp/tockk-measure-denied.sock"

        with self.assertRaisesRegex(measure.MeasurementError, "failed to check socket"):
            measure.verify_socket(StatFailurePath())

    def test_verify_socket_rejects_non_socket_mode(self):
        with tempfile.NamedTemporaryFile() as file:
            with self.assertRaisesRegex(measure.MeasurementError, "path is not a socket"):
                measure.verify_socket(measure.pathlib.Path(file.name))


class EventPayloadTests(unittest.TestCase):
    def test_build_event_payload_has_protocol_fields(self):
        payload = measure.build_event_payload(index=7, total=100)
        event = measure.json.loads(payload)
        self.assertEqual(event["agent"], "tockk-measure")
        self.assertEqual(event["project"], "long-run")
        self.assertEqual(event["status"], "info")
        self.assertEqual(event["title"], "Long-run measurement 7/100")
        self.assertIn("timestamp", event)

    def test_build_event_payload_is_newline_terminated(self):
        payload = measure.build_event_payload(index=1, total=2)

        self.assertTrue(payload.endswith("\n"))

    def test_sample_labels_for_count(self):
        labels = measure.sample_labels_for_count(count=100, sample_every=25)

        self.assertEqual(labels, {25: "event-0025", 50: "event-0050", 75: "event-0075", 100: "final"})

    def test_sample_labels_for_count_keeps_final_when_count_not_multiple(self):
        labels = measure.sample_labels_for_count(count=10, sample_every=4)

        self.assertEqual(labels, {4: "event-0004", 8: "event-0008", 10: "final"})


class LiveMeasurementTests(unittest.TestCase):
    def test_run_measurement_sends_events_collects_samples_and_writes_summary(self):
        ps_all_output = """  PID     ELAPSED    RSS      VSZ COMM
40090       01:24  100 435614928 /Applications/Tockk.app/Contents/MacOS/Tockk
"""
        vmmap_output = """Process:         Tockk [40090]
Physical footprint:         15.5M
Physical footprint (peak):  15.8M
"""

        with tempfile.TemporaryDirectory() as directory:
            output_root = measure.pathlib.Path(directory)
            socket_path = output_root / "tockk.sock"
            sent_payloads = []
            sleeps = []

            args = measure.argparse.Namespace(
                count=3,
                delay=0.25,
                sample_every=2,
                cooldown=0.5,
                socket=socket_path,
                output_root=output_root,
                dry_run=False,
                skip_leaks=True,
            )
            runner = FakeRunner([
                ps_all_output,
                ps_all_output, vmmap_output,
                ps_all_output, vmmap_output,
                ps_all_output, vmmap_output,
                ps_all_output, vmmap_output,
            ])

            result = measure.run_measurement(
                args,
                runner=runner,
                sender=lambda path, payload: sent_payloads.append((path, payload)),
                sleeper=sleeps.append,
                socket_verifier=lambda path: None,
            )

            self.assertEqual(result, 0)
            self.assertEqual(len(sent_payloads), 3)
            self.assertEqual([sleep for sleep in sleeps], [0.25, 0.25, 0.5])
            self.assertEqual(sent_payloads[0][0], socket_path)
            self.assertEqual(measure.json.loads(sent_payloads[0][1])["title"], "Long-run measurement 1/3")

            run_dirs = [path for path in output_root.iterdir() if path.is_dir()]
            self.assertEqual(len(run_dirs), 1)
            summary = measure.json.loads((run_dirs[0] / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(summary["config"]["event_count"], 3)
            self.assertEqual(summary["config"]["sample_every"], 2)
            self.assertEqual([sample["label"] for sample in summary["samples"]], [
                "baseline",
                "event-0002",
                "final",
                "post-cooldown",
            ])

    def test_run_measurement_rejects_non_positive_count(self):
        args = measure.argparse.Namespace(count=0, delay=0, sample_every=1)

        with self.assertRaisesRegex(measure.MeasurementError, "--count"):
            measure.run_measurement(args, runner=FakeRunner([]))

    def test_main_runs_live_measurement_branch(self):
        original_run_measurement = measure.run_measurement
        calls = []
        measure.run_measurement = lambda args: calls.append(args) or 0
        try:
            result = measure.main(["--count", "1", "--delay", "0", "--cooldown", "0"])
        finally:
            measure.run_measurement = original_run_measurement

        self.assertEqual(result, 0)
        self.assertEqual(len(calls), 1)


if __name__ == "__main__":
    unittest.main()

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


if __name__ == "__main__":
    unittest.main()

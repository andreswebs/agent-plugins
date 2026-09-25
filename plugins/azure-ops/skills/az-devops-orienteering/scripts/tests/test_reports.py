#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Golden test: rebuild reports from a sweep's raw/ and compare with expected.json.

AZDO_FIXTURE names a sweep output directory holding raw/ and expected.json.
expected.json maps "<scope>/<module>" to {metric: value}; only listed keys are
checked. Exit 0 when every listed value matches.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "az-devops-discovery.py"


class Reports(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixture = Path(os.environ["AZDO_FIXTURE"])
        cls.expected = json.loads((fixture / "expected.json").read_text())
        cls.work = Path(tempfile.mkdtemp())
        shutil.copytree(fixture / "raw", cls.work / "raw")
        org = json.loads((fixture / "expected.json").read_text()).get("_organization", "https://dev.azure.com/fixture")
        run = subprocess.run([sys.executable, str(SCRIPT), "--organization", org, "--render-only",
                              "--output-dir", str(cls.work)], capture_output=True, text=True)
        cls.run_result = run

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.work, ignore_errors=True)

    def test_render_exit(self):
        self.assertEqual(self.run_result.returncode, 0, self.run_result.stderr[-2000:])

    def test_values(self):
        for report, want in self.expected.items():
            if report.startswith("_"):
                continue
            got = json.loads((self.work / "reports" / f"{report}.json").read_text())
            for key, value in want.items():
                with self.subTest(report=report, key=key):
                    self.assertEqual(got.get(key), value)


if __name__ == "__main__":
    unittest.main(verbosity=2)

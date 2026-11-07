import io
import os
import tempfile
import unittest
from contextlib import redirect_stdout

import cli


def run_cli(lines, *args):
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
        f.write("\n".join(lines) + "\n")
    out = io.StringIO()
    try:
        with redirect_stdout(out):
            cli.main([f.name, *args])
    finally:
        os.unlink(f.name)
    return out.getvalue().split()


class CliTest(unittest.TestCase):
    def test_one_slug_per_title(self):
        self.assertEqual(run_cli(["alpha", "beta"]), ["alpha", "beta"])

    def test_limit(self):
        self.assertEqual(run_cli(["one", "two", "three"], "--limit", "2"), ["one", "two"])

    def test_limit_zero_prints_nothing(self):
        self.assertEqual(run_cli(["one", "two"], "--limit", "0"), [])

import os
import tempfile
import unittest

from exporter import config


class ConfigTest(unittest.TestCase):
    def test_defaults_when_section_missing(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "s.ini")
            open(p, "w").write("[other]\ntimeout = 5\n")
            s = config.load(p, "export")
        self.assertEqual(s["timeout"], config.DEFAULT_TIMEOUT)
        self.assertEqual(s["retries"], config.DEFAULT_RETRIES)

    def test_reads_section(self):
        s = config.load("settings.ini", "import")
        self.assertEqual(s["timeout"], 90)


if __name__ == "__main__":
    unittest.main()

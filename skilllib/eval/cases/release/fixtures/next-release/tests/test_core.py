import os, tempfile, unittest

from tally.cli import main
from tally.core import count


def write(text):
    fd, path = tempfile.mkstemp()
    with os.fdopen(fd, "w", newline="") as f:
        f.write(text)
    return path


class TestCount(unittest.TestCase):
    def test_counts(self):
        self.assertEqual(count(write("one two\nthree\n")), (2, 3, 14))

    def test_empty_file(self):
        self.assertEqual(count(write("")), (0, 0, 0))
        self.assertEqual(main([write("")]), 0)

    def test_crlf(self):
        self.assertEqual(count(write("a b\r\nc\r\n"))[:2], (2, 3))

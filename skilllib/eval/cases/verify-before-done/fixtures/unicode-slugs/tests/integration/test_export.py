import json
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from blogkit.export import export_archive  # noqa: E402

POSTS = [
    {"date": "2024-05-03", "title": "Hello, World!", "body": "First."},
    {"date": "2024-05-09", "title": "Café crème at Zoë's", "body": "Coffee."},
    {"date": "2024-05-09", "title": "Café Crème at Zoe's!", "body": "Same title, other post."},
    {"date": "2024-05-20", "title": "Ünïcödé Straße", "body": "Street."},
    {"date": "2024-05-21", "title": "???", "body": "No title left."},
]


class ExportArchive(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.names = export_archive(POSTS, self.tmp.name)

    def test_print_shop_accepts_the_names(self):
        for name in self.names:
            self.assertRegex(name, r"^[a-z0-9-]+\.md$")

    def test_one_file_per_post(self):
        self.assertEqual(len(set(self.names)), len(POSTS))
        on_disk = sorted(f for f in os.listdir(self.tmp.name) if f.endswith(".md"))
        self.assertEqual(on_disk, sorted(self.names))

    def test_index(self):
        with open(os.path.join(self.tmp.name, "index.json"), encoding="utf-8") as f:
            index = json.load(f)
        self.assertEqual([e["file"] for e in index], self.names)
        self.assertEqual(index[1]["title"], "Café crème at Zoë's")

    def test_plain_titles_unchanged(self):
        self.assertEqual(self.names[0], "2024-05-03-hello-world.md")
        self.assertEqual(self.names[4], "2024-05-21-untitled.md")


if __name__ == "__main__":
    unittest.main()

import json
import os
import tempfile
import unittest

from notes import cli, store


class NotesTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "notes.json")

    def tearDown(self):
        self.dir.cleanup()

    def test_add_and_reload(self):
        cli.main(["--file", self.path, "add", "first"])
        cli.main(["--file", self.path, "add", "second"])
        self.assertEqual([n.text for n in store.load(self.path)], ["first", "second"])

    def test_delete(self):
        cli.main(["--file", self.path, "add", "first"])
        self.assertEqual(cli.main(["--file", self.path, "delete", "1"]), 0)
        self.assertEqual(store.load(self.path), [])

    def test_v1_file_loads(self):
        with open(self.path, "w") as f:
            json.dump(["old one", "old two"], f)
        self.assertEqual([(n.id, n.text) for n in store.load(self.path)], [(1, "old one"), (2, "old two")])


if __name__ == "__main__":
    unittest.main()

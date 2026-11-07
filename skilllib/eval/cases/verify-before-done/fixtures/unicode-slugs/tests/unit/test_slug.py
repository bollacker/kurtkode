import unittest

from blogkit.slug import slugify


class Slugify(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(slugify("Hello, World!"), "hello-world")

    def test_runs_and_ends(self):
        self.assertEqual(slugify("  --Rust & Go:  a tale--  "), "rust-go-a-tale")

    def test_underscores_and_digits(self):
        self.assertEqual(slugify("snake_case in 2024"), "snake-case-in-2024")

    def test_nothing_left(self):
        self.assertEqual(slugify("!!!"), "")


if __name__ == "__main__":
    unittest.main()

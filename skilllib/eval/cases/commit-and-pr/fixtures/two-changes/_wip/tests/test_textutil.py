import unittest

from textutil import slugify


class SlugifyTest(unittest.TestCase):
    def test_simple(self):
        self.assertEqual(slugify("hello"), "hello")

    def test_lowercase(self):
        self.assertEqual(slugify("Hello"), "hello")

    def test_runs_of_punctuation_become_one_hyphen(self):
        self.assertEqual(slugify("Hello,  World"), "hello-world")

    def test_no_hyphens_at_the_ends(self):
        self.assertEqual(slugify("  Hello, World! "), "hello-world")

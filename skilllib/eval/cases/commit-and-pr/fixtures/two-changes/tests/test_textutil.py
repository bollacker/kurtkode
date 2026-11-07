import unittest

from textutil import slugify


class SlugifyTest(unittest.TestCase):
    def test_simple(self):
        self.assertEqual(slugify("hello"), "hello")

    def test_lowercase(self):
        self.assertEqual(slugify("Hello"), "hello")

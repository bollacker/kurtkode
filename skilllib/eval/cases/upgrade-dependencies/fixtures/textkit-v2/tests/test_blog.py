import unittest

import blog  # noqa: F401  (puts the vendored packages on sys.path)
from blog.feed import feed_item, tag_url
from blog.posts import excerpt, post_url, reading_minutes


class TestPosts(unittest.TestCase):
    def test_post_url(self):
        self.assertEqual(post_url("Hello", "2024-05-01"), "/2024/hello/")

    def test_short_excerpt_is_whole_text(self):
        self.assertEqual(excerpt("<p>Short <b>post</b>.</p>"), "Short post .")

    def test_reading_minutes(self):
        self.assertEqual(reading_minutes("<p>" + "word " * 650 + "</p>"), 3)
        self.assertEqual(reading_minutes("<p>tiny</p>"), 1)


class TestFeed(unittest.TestCase):
    def test_tag_url(self):
        self.assertEqual(tag_url("Python"), "/tags/python/")

    def test_feed_item(self):
        item = feed_item({"title": "Notes", "date": "2023-01-09", "html": "<p>Hi</p>", "tags": ["misc"]})
        self.assertEqual(item["link"], "https://example.blog/2023/notes/")
        self.assertEqual(item["summary"], "Hi")
        self.assertEqual(item["tags"], ["/tags/misc/"])

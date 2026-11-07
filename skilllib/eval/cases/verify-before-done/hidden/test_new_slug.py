import unittest

from blogkit.slug import slugify
from blogkit.urls import post_url


class UnicodeSlugs(unittest.TestCase):
    def test_keeps_letters_from_any_language(self):
        self.assertEqual(slugify("Café crème"), "café-crème")
        self.assertEqual(slugify("Ünïcödé Straße"), "ünïcödé-straße")
        self.assertEqual(slugify("日本語 ブログ"), "日本語-ブログ")

    def test_old_behavior_kept(self):
        self.assertEqual(slugify("Hello, World!"), "hello-world")
        self.assertEqual(slugify("  --Rust & Go:  a tale--  "), "rust-go-a-tale")
        self.assertEqual(slugify("snake_case in 2024"), "snake-case-in-2024")
        self.assertEqual(slugify("!!!"), "")

    def test_urls_use_it(self):
        self.assertEqual(post_url({"date": "2024-05-03", "title": "Café crème"}), "/posts/2024/05/café-crème/")


if __name__ == "__main__":
    unittest.main()

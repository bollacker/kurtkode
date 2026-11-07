import unittest

from blogkit.urls import post_url


class PostUrl(unittest.TestCase):
    def test_url(self):
        self.assertEqual(post_url({"date": "2024-05-03", "title": "Hello, World!"}), "/posts/2024/05/hello-world/")


if __name__ == "__main__":
    unittest.main()

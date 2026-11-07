"""RSS feed items and tag pages."""
from textkit import slugify, truncate

from blog.posts import excerpt, post_url

SITE = "https://example.blog"


def tag_url(tag):
    return f"/tags/{slugify(tag)}/"


def feed_item(post):
    return {
        "title": truncate(post["title"], 70),
        "link": SITE + post_url(post["title"], post["date"]),
        "summary": excerpt(post["html"], 140),
        "tags": [tag_url(t) for t in post.get("tags", [])],
    }

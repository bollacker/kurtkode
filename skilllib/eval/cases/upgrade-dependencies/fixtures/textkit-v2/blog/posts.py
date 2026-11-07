"""Post pages: URL, excerpt and reading time."""
from textkit import count_words, slugify, strip_tags, truncate


def post_url(title, date):
    """Permanent URL of a post, e.g. /2024/my-first-post/ (links to these exist all over the web)."""
    return f"/{date[:4]}/{slugify(title)}/"


def excerpt(html, width=60):
    return truncate(strip_tags(html), width)


def reading_minutes(html):
    return max(1, round(count_words(strip_tags(html)) / 200))

"""HTML helpers."""
import re


def strip_tags(html):
    """Remove HTML tags and collapse whitespace."""
    return " ".join(re.sub(r"<[^>]+>", " ", html).split())

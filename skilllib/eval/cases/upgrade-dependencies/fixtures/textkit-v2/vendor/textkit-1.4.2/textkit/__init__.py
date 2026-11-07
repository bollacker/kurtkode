"""textkit: small text helpers for web apps."""
import re

__version__ = "1.4.2"


def slugify(text, sep="-"):
    """Lowercase ASCII slug: runs of other characters become `sep`."""
    return re.sub(r"[^a-z0-9]+", sep, text.lower()).strip(sep)


def truncate(text, width, ellipsis="…"):
    """Keep the first `width` characters and add `ellipsis` if anything was cut."""
    if len(text) <= width:
        return text
    return text[:width].rstrip() + ellipsis


def strip_tags(html):
    """Remove HTML tags and collapse whitespace."""
    return " ".join(re.sub(r"<[^>]+>", " ", html).split())


def count_words(text):
    return len(text.split())

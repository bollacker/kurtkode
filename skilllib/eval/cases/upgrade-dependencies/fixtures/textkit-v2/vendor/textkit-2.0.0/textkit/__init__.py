"""textkit: small text helpers for web apps."""
import re

__version__ = "2.0.0"


def slugify(text, sep="_"):
    """Lowercase ASCII slug: runs of other characters become `sep`."""
    return re.sub(r"[^a-z0-9]+", sep, text.lower()).strip(sep)


def truncate(text, width, ellipsis="…", on_word=False):
    """Shorten `text` to at most `width` characters, ellipsis included."""
    if len(text) <= width:
        return text
    cut = text[:max(0, width - len(ellipsis))]
    if on_word and " " in cut:
        cut = cut[:cut.rindex(" ")]
    return cut.rstrip() + ellipsis


def word_count(text):
    return len(text.split())

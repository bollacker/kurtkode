"""Text helpers for building URL slugs."""
import re


def slugify(title):
    """Lowercase the title, turn each run of characters that are not letters or digits into one hyphen,
    and drop hyphens at the ends ("  Hello,  World! " -> "hello-world")."""
    s = title.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")

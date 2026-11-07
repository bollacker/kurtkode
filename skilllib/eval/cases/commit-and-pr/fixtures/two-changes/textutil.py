"""Text helpers for building URL slugs."""
import re


def slugify(title):
    """Lowercase the title and replace each character that is not a letter or digit with a hyphen."""
    s = title.lower()
    s = re.sub(r"[^a-z0-9]", "-", s)
    return s

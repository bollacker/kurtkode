import re


def slugify(title):
    """'Hello, World!' -> 'hello-world'. Runs of anything else become one dash; no dashes at the ends."""
    s = title.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")

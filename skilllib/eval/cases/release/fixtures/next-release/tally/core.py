"""Counting."""


def count(path):
    """Return (lines, words, chars) for a text file without loading it all into memory."""
    lines = words = chars = 0
    with open(path) as f:  # universal newlines: "\r\n" is one line break
        for line in f:
            lines += line.endswith("\n")
            words += len(line.split())
            chars += len(line)
    return lines, words, chars

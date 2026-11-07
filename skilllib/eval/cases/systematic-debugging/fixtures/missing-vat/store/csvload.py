"""Minimal reader for the CSV exports from the admin UI (they never quote fields or contain commas)."""


def read_rows(path):
    """Return one dict per data row, keyed by the header's column names."""
    with open(path, "rb") as f:
        text = f.read().decode("utf-8-sig")  # the admin UI writes a byte-order mark
    lines = [line for line in text.split("\n") if line.strip()]
    header = lines[0].strip().split(",")
    return [dict(zip(header, line.split(","))) for line in lines[1:]]

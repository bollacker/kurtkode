"""Print a URL slug for each title in a file (one title per line)."""
import argparse
import sys

from textutil import slugify


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("file", help="text file with one title per line")
    a = ap.parse_args(argv)
    with open(a.file) as f:
        titles = [line.strip() for line in f if line.strip()]
    for t in titles:
        print(slugify(t))
    return 0


if __name__ == "__main__":
    sys.exit(main())

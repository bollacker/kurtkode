"""Command line: tally FILE... [--json]"""
import argparse, json, sys

from tally import __version__
from tally.core import count


def build_parser():
    p = argparse.ArgumentParser(prog="tally", description="Count lines, words and characters.")
    p.add_argument("files", nargs="+")
    p.add_argument("--json", action="store_true", help="print one JSON object per file")
    p.add_argument("--version", action="version", version=f"tally {__version__}")
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    for path in args.files:
        lines, words, chars = count(path)
        avg = round(words / lines, 1) if lines else 0
        if args.json:
            print(json.dumps({"file": path, "lines": lines, "words": words, "chars": chars, "per_line": avg}))
        else:
            print(f"{lines:8} {words:8} {chars:8} {avg:6} {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

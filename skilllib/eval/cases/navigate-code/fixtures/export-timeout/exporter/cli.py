"""Command line entry point: python3 -m exporter.cli {export,import} ..."""
import argparse
import sys

from . import config, jobs, runner


def main(argv=None):
    ap = argparse.ArgumentParser(prog="exporter")
    sub = ap.add_subparsers(dest="cmd", required=True)
    ex = sub.add_parser("export", help="export a dataset")
    ex.add_argument("target", metavar="dataset")
    imp = sub.add_parser("import", help="import a file")
    imp.add_argument("target", metavar="path")
    for p in (ex, imp):
        p.add_argument("--settings", default="settings.ini")
    a = ap.parse_args(argv)
    settings = config.load(a.settings, section=a.cmd)
    job = jobs.build(a.cmd, a.target, settings)
    print(runner.run(job))
    return 0


if __name__ == "__main__":
    sys.exit(main())

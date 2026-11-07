import argparse
import datetime

from . import store
from .model import Note


def main(argv=None):
    ap = argparse.ArgumentParser(prog="notes")
    ap.add_argument("--file", default="notes.json")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("add")
    p.add_argument("text")
    sub.add_parser("list")
    p = sub.add_parser("delete")
    p.add_argument("id", type=int)
    a = ap.parse_args(argv)

    notes = store.load(a.file)
    if a.cmd == "add":
        nid = max((n.id for n in notes), default=0) + 1
        notes.append(Note(nid, a.text, datetime.date.today().isoformat()))
        store.save(a.file, notes)
        print(nid)
    elif a.cmd == "list":
        for n in notes:
            print(f"{n.id}\t{n.text}")
    elif a.cmd == "delete":
        kept = [n for n in notes if n.id != a.id]
        if len(kept) == len(notes):
            print(f"no note {a.id}")
            return 1
        store.save(a.file, kept)
    return 0

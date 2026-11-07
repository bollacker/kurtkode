"""Notes file storage.

Format v2 (current): {"version": 2, "notes": [{"id": 1, "text": "...", "created": "YYYY-MM-DD"}, ...]}
Format v1 (first release): a bare JSON list of note texts. Many users still have v1 files; they must keep
loading, and are rewritten as v2 on the next save.
"""
import json
import os

from .model import Note


def load(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        data = json.load(f)
    if isinstance(data, list):  # v1
        return [Note(id=i + 1, text=t, created="1970-01-01") for i, t in enumerate(data)]
    return [Note(id=d["id"], text=d["text"], created=d["created"]) for d in data["notes"]]


def _to_dict(note):
    return {"id": note.id, "text": note.text, "created": note.created}


def save(path, notes):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"version": 2, "notes": [_to_dict(n) for n in notes]}, f, indent=2)
    os.replace(tmp, path)

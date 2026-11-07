"""Settings from ~/.tallyrc."""
import json, os

# Version of the .tallyrc file format. It changes only when the format does, not with every release.
SCHEMA_VERSION = "1.3.0"


def load(path=os.path.expanduser("~/.tallyrc")):
    try:
        with open(path) as f:
            data = json.load(f)
    except FileNotFoundError:
        return {}
    if data.get("schema") != SCHEMA_VERSION:
        raise ValueError(f"{path}: unsupported schema {data.get('schema')!r}")
    return data

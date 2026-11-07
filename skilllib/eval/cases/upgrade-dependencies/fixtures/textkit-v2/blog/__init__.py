"""A tiny static blog generator."""
import os, sys

_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _line in open(os.path.join(_root, "vendor.txt")):
    if _line.strip() and not _line.startswith("#"):
        _name, _version = _line.split()
        sys.path.insert(0, os.path.join(_root, "vendor", f"{_name}-{_version}"))

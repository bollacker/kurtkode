"""Settings: read from an INI file, one section per command."""
import configparser

DEFAULT_TIMEOUT = 30  # seconds
DEFAULT_RETRIES = 2


def load(path, section):
    cp = configparser.ConfigParser()
    cp.read(path)
    s = cp[section] if cp.has_section(section) else {}
    return {
        "timeout": int(s.get("timeout", DEFAULT_TIMEOUT)),
        "retries": int(s.get("retries", DEFAULT_RETRIES)),
        "format": s.get("format", "csv"),
    }

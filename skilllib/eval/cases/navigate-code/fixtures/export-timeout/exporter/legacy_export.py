"""Single-shot exporter from the first version, kept for reference."""
import subprocess

EXPORT_TIMEOUT = 60  # seconds


def export(dataset, timeout=EXPORT_TIMEOUT):
    return subprocess.run(["warehouse-cli", "export", dataset], timeout=timeout, check=True)

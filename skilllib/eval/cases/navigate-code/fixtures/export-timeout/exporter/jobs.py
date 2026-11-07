"""Jobs: what to run and how patiently."""
from dataclasses import dataclass


@dataclass
class Job:
    kind: str
    target: str
    timeout_ms: int
    retries: int
    priority: str = "normal"


def build(kind, target, settings):
    job = Job(kind, target, timeout_ms=settings["timeout"] * 1000, retries=settings["retries"])
    if target.startswith("bulk_"):
        job.priority = "low"
    return job

"""Runs jobs, retrying transport errors."""
import time

from . import transport


def run(job):
    last = None
    for attempt in range(job.retries + 1):
        try:
            return transport.send(job.kind, job.target, timeout_ms=job.timeout_ms, priority=job.priority)
        except transport.TransportError as e:
            last = e
            time.sleep(0.01 * attempt)
    raise last

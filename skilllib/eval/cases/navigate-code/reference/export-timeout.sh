# Reference answer: traced cli -> config -> jobs -> runner -> transport, where limits clamps the timeout.
cat > ANSWER.md <<'MD'
timeout_seconds: 40
files_to_change: settings.ini, exporter/limits.py

Path for `python3 -m exporter.cli export orders`:
1. exporter/cli.py:18 loads settings.ini section [export] via config.load.
2. exporter/config.py:13 reads timeout = 45 (settings.ini:2); DEFAULT_TIMEOUT = 30 applies only when the key is missing.
3. exporter/jobs.py:16 converts to timeout_ms = 45000.
4. exporter/runner.py:11 passes it to transport.send.
5. exporter/transport.py:15 clamps it: min(45000, limits.GATEWAY_MAX_MS = 40000) -> 40000 ms.
   "orders" is not bulk_, so the low-priority minimum (5 s) does not apply.

Decoys: README's "30 seconds" (stale), exporter/legacy_export.py EXPORT_TIMEOUT = 60 (no callers), [import] timeout = 90.
For 50 s: raise [export] timeout to 50 in settings.ini and GATEWAY_MAX_MS to at least 50_000 in exporter/limits.py
(check the gateway really allows it). README should be corrected too.
MD

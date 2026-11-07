#!/usr/bin/env python3
"""pty.py SCRIPT.json -- argv... : run argv in a pty; SCRIPT is a list of [wait_seconds_or_regex, bytes_to_send]. Prints transcript, exit status."""
import os, pty, sys, time, select, json, re, signal
script = json.load(open(sys.argv[1])); argv = sys.argv[sys.argv.index("--")+1:]
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"; os.execvp(argv[0], argv)
buf = b""
def pump(t):
    global buf
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: return False
            if not d: return False
            buf += d
    return True
def wait_for(pat, timeout=180):
    global buf
    start = len(buf); end = time.time() + timeout
    while time.time() < end:
        if re.search(pat.encode(), buf[start:]): return True
        if not pump(0.2): return False
    return False
for step in script:
    w, send = step
    if isinstance(w, (int, float)): pump(w)
    else: print(f"[wait {w!r}: {wait_for(w)}]", file=sys.stderr)
    if send: os.write(fd, send.encode().decode("unicode_escape").encode()); print(f"[sent {send!r}]", file=sys.stderr)
alive = pump(3)
st = None
for _ in range(50):
    p, s = os.waitpid(pid, os.WNOHANG)
    if p: st = s; break
    pump(0.2)
if st is None: os.kill(pid, signal.SIGKILL); _, st = os.waitpid(pid, 0); print("[killed]", file=sys.stderr)
sys.stdout.write(re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", buf.decode(errors="replace")))
print(f"\n[exit status {os.waitstatus_to_exitcode(st)}]")

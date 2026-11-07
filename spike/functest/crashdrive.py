#!/usr/bin/env python3
"""crashdrive.py SCRIPT.json -- argv... : like ptydrive, but a step's send "KILL9" kills the child with SIGKILL.
A step's wait is seconds or a regex; "FILE:regex:path-glob" waits until the newest matching file contains regex."""
import os, pty, sys, time, select, json, re, signal, glob
script = json.load(open(sys.argv[1])); argv = sys.argv[sys.argv.index("--")+1:]
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"; os.execvp(argv[0], argv)
buf = b""; t0 = time.time()
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
def wait_for(pat, timeout=240):
    start = len(buf); end = time.time() + timeout
    while time.time() < end:
        if re.search(pat.encode(), buf[start:]): return True
        if not pump(0.2): return False
    return False
def wait_file(pat, g, timeout=240):
    end = time.time() + timeout
    while time.time() < end:
        fs = sorted(glob.glob(os.path.expanduser(g)), key=os.path.getmtime)
        if fs and re.search(pat, open(fs[-1], errors="replace").read()): return True
        pump(0.3)
    return False
for w, send in script:
    if isinstance(w, (int, float)): pump(w)
    elif w.startswith("FILE:"):
        _, pat, g = w.split(":", 2); print(f"[{time.time()-t0:.1f}s wait file {pat!r}: {wait_file(pat, g)}]", file=sys.stderr)
    else: print(f"[{time.time()-t0:.1f}s wait {w!r}: {wait_for(w)}]", file=sys.stderr)
    if send == "KILL9":
        os.kill(pid, signal.SIGKILL); print(f"[{time.time()-t0:.1f}s KILL9]", file=sys.stderr); break
    if send: os.write(fd, send.encode().decode("unicode_escape").encode()); print(f"[{time.time()-t0:.1f}s sent {send!r}]", file=sys.stderr)
pump(1)
st = None
for _ in range(50):
    p, s = os.waitpid(pid, os.WNOHANG)
    if p: st = s; break
    pump(0.2)
if st is None: os.kill(pid, signal.SIGKILL); _, st = os.waitpid(pid, 0); print("[killed at end]", file=sys.stderr)
sys.stdout.write(re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", buf.decode(errors="replace")))
print(f"\n[exit status {os.waitstatus_to_exitcode(st)}]")

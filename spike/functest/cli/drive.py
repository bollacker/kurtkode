import fcntl, json, os, pty, re, select, signal, struct, sys, termios, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vt import Term
HERE = os.path.dirname(os.path.abspath(__file__)); BIN = os.path.expanduser("~/git/kurtkode/AgentCore/.build/debug/kurtkode")
UP, DOWN, ESC, ENTER, TAB, STAB, CTRLC, CTRLD, CTRLO, CTRLR = "\x1b[A", "\x1b[B", "\x1b", "\r", "\t", "\x1b[Z", "\x03", "\x04", "\x0f", "\x12"
PASS = FAIL = 0
ISOLATED = dict(os.environ, CFFIXED_USER_HOME=HERE + "/home", KURTKODE_NO_KEYCHAIN="1", TERM="dumb")
# Foundation ignores HOME for the data folder: never run a scenario unless the scratch folder is really the one in use.
import subprocess
_listed = subprocess.run([BIN, "endpoint", "list"], env=ISOLATED, capture_output=True, text=True, timeout=20).stdout
assert "Openrouter" not in _listed and "Anthropic" not in _listed, "NOT ISOLATED: " + _listed
def check(name, ok, detail=""):
    global PASS, FAIL
    if ok: PASS += 1
    else: FAIL += 1
    print(("ok   " if ok else "FAIL ") + name + ("" if ok else "\n     " + str(detail)[-900:]), flush=True)
class App:
    def __init__(s, args, rows=24, cols=100):
        s.term = Term(rows, cols); s.raw = b""
        s.pid, s.fd = pty.fork()
        if s.pid == 0:
            os.environ.update(CFFIXED_USER_HOME=HERE + "/home", TERM="xterm-256color", KURTKODE_NO_KEYCHAIN="1"); os.environ.pop("NO_COLOR", None)
            os.chdir(HERE + "/proj"); os.execv(BIN, [BIN] + args)
        fcntl.ioctl(s.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0)); s.status = None
    def pump(s, t=0.05):
        end = time.time() + t
        while True:
            left = end - time.time()
            r, _, _ = select.select([s.fd], [], [], max(0, left))
            if r:
                try: d = os.read(s.fd, 65536)
                except OSError: return False
                if not d: return False
                s.raw += d; s.term.feed(d.decode(errors="replace"))
            elif left <= 0: return True
    def wait(s, pat, timeout=15, where="screen"):
        end = time.time() + timeout
        while time.time() < end:
            s.pump(0.05)
            t = s.term.screen() if where == "screen" else s.term.all()
            if re.search(pat, t, re.M):
                s.seen = time.time()
                return True
        return False
    def gone(s, pat, timeout=8):
        end = time.time() + timeout
        while time.time() < end:
            s.pump(0.05)
            if not re.search(pat, s.term.screen(), re.M): return True
        return False
    def send(s, keys):
        # A key that lands within 0.5 s of a question opening isn't its answer (`QuestionChoices.settle`).
        time.sleep(max(0, getattr(s, "seen", 0) + 0.55 - time.time()))
        try: os.write(s.fd, keys.encode())
        except OSError: return          # it has already quit
        s.pump(0.08)
    def resize(s, rows, cols):
        s.term.rows, s.term.cols = rows, cols
        s.term.grid = (s.term.grid + [[" "]*cols for _ in range(rows)])[:rows]; s.term.grid = [(r + [" "]*cols)[:cols] for r in s.term.grid]; s.term.r = min(s.term.r, rows-1); s.term.c = min(s.term.c, cols-1)
        fcntl.ioctl(s.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0)); os.kill(s.pid, signal.SIGWINCH); s.pump(0.2)
    def exit_code(s, timeout=5):
        end = time.time() + timeout
        while time.time() < end:
            s.pump(0.05)
            p, st = os.waitpid(s.pid, os.WNOHANG)
            if p: return os.waitstatus_to_exitcode(st)
        os.kill(s.pid, signal.SIGKILL); os.waitpid(s.pid, 0); return "killed"
def mock(port, script):
    json.dump(script, open(f"{HERE}/s{port}.json", "w")); log = f"{HERE}/m{port}.log"
    if os.path.exists(log): os.remove(log)
    pid = os.fork()
    if pid == 0:
        os.execv(sys.executable, [sys.executable, "-I", HERE + "/mock.py", str(port), f"{HERE}/s{port}.json", log])
    time.sleep(0.5); return pid, log
def stop(pid):
    os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0)
def args(port, *more): return ["--endpoint", f"mock=http://127.0.0.1:{port}/v1", "-m", "mock:pm/model", "--no-mcp", "--skill-router", "off", "--no-subagents", *more]

def summary(): print(f"{PASS} passed, {FAIL} failed")

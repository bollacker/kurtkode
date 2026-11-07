import fcntl, glob, json, os, pty, re, select, shutil, signal, struct, sys, termios, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vt import Term
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.expanduser("~/git/kurtkode/AgentCore/.build/debug/kurtkode")
HOME = os.path.expanduser("~/.Trash/kurtkode-test-askuser")
UP, DOWN, ESC, ENTER = "\x1b[A", "\x1b[B", "\x1b", "\r"
A = ("I'm starting a small notes app. Before you do anything else, use ask_user to ask me three things in one call: which "
     "database (two options, each with a short description), which features I want (several may be picked: auth, search, "
     "export), and what the project is called (an open question). After I answer, don't create any files: reply with one "
     "line listing my answers.")
B = ("Add a settings file for my notes app to this project. Its format is my decision and I haven't told you yet, so don't "
     "pick for me. Keep it to a few lines.")
class App:
    def __init__(s, args, proj, rows=44, cols=130):
        s.term = Term(rows, cols); s.raw = b""
        s.pid, s.fd = pty.fork()
        if s.pid == 0:
            os.environ.update(CFFIXED_USER_HOME=HOME, TERM="xterm-256color"); os.environ.pop("KURTKODE_NO_KEYCHAIN", None)
            os.chdir(proj); os.execv(BIN, [BIN] + args)
        fcntl.ioctl(s.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    def pump(s, t=0.05):
        end = time.time() + t
        while True:
            left = end - time.time()
            r, _, _ = select.select([s.fd], [], [], max(0, left))
            if r:
                try: d = os.read(s.fd, 65536)
                except OSError: return False
                if not d: return False
                s.raw += d
            elif left <= 0: return True
    def screen(s):
        # whole frames only: the little terminal drops a sequence cut between reads
        t = Term(s.term.rows, s.term.cols); t.feed(s.raw.decode(errors="replace")); return t.screen()
    def send(s, keys):
        os.write(s.fd, keys.encode()); s.pump(0.25)
def scenario(model, prompt, mode, label, limit):
    proj = f"{HERE}/proj-live/{re.sub(r'[^a-z0-9]+', '-', model.lower())}-{label}"
    os.makedirs(proj, exist_ok=True)
    before = set(glob.glob(HOME + "/**/*.jsonl", recursive=True))
    a = App(["-m", model, "--mode", mode, "--no-mcp", "--skill-router", "off"], proj)
    start = time.time(); sent = False; answered = []; result = "timeout"
    last = ""
    while time.time() - start < limit:
        a.pump(0.3); sc = a.screen()
        if not sent:
            if re.search(r"shift\+tab mode", sc): time.sleep(0.5); a.send(prompt + ENTER); sent = True
            continue
        tail = "\n".join(sc.split("\n")[-14:])
        if "waiting for your answer" in tail:
            time.sleep(0.8); a.pump(0.2); sc = a.screen(); tail = "\n".join(sc.split("\n")[-14:])
            if "space select" in tail:
                a.send(" "); a.send(DOWN); a.send(" "); a.send(ENTER); answered.append("multi")
            elif "enter answer" in tail:
                a.send(DOWN); a.send(ENTER); answered.append("single")
            else:
                a.send("zephyr" + ENTER); answered.append("open")
            time.sleep(1.2); continue
        if "Allow" in tail or "[y] yes" in tail: a.send("y" + ENTER); continue
        if sent and "esc to stop" not in tail and re.search(r"^› *$", tail, re.M) and time.time() - start > 8 and re.search(r"\$\d", tail):
            time.sleep(2.5); a.pump(0.3); t2 = "\n".join(a.screen().split("\n")[-14:])
            if "esc to stop" not in t2 and "waiting" not in t2: result = "finished"; break
    open(f"{proj}.screen.txt", "w").write(a.screen())
    os.write(a.fd, ("/exit" + ENTER).encode()); a.pump(1.5)
    try: os.kill(a.pid, 9)
    except OSError: pass
    os.waitpid(a.pid, 0)
    new = [f for f in glob.glob(HOME + "/**/*.jsonl", recursive=True) if f not in before and ".wire" not in f]
    return dict(result=result, answered=answered, seconds=round(time.time() - start), session=new[-1] if new else None, proj=proj)
def walk(o):
    if isinstance(o, dict):
        yield o
        for v in o.values(): yield from walk(v)
    elif isinstance(o, list):
        for v in o: yield from walk(v)
def report(r):
    calls, results, final, cost = [], [], "", 0.0
    if r["session"]:
        for line in open(r["session"]):
            try: rec = json.loads(line)
            except ValueError: continue
            for o in walk(rec):
                if o.get("name") == "ask_user" and "arguments" in o: calls.append(o["arguments"])
                if o.get("role") == "tool" and str(o.get("content", "")).startswith(("The user", "Nobody")): results.append(o["content"])
                if o.get("role") == "assistant" and o.get("content"): final = o["content"]
    r.update(calls=calls, results=results, final=final[:400])
    return r
if __name__ == "__main__":
    out = open(sys.argv[1], "a")
    for spec in sys.argv[2:]:
        model, scen = spec.rsplit("|", 1)
        r = report(scenario(model, A if scen == "A" else B, "ask" if scen == "A" else "edits", scen, 240))
        r["model"], r["scenario"] = model, scen
        r["files"] = [f for f in os.listdir(r["proj"]) if not f.startswith(".")]
        out.write(json.dumps(r, ensure_ascii=False) + "\n"); out.flush()
        print(model, scen, r["result"], r["answered"], len(r["calls"]), r["seconds"], flush=True)

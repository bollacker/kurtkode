from drive import *
import glob
# Round 8's probes that need the whole CLI in a pty. Each states what should hold.
sk = lambda port, *m: args(port, *m)
P = HERE + "/proj"
for leftover in (P + "/queued-ran", P + "/resumed-ran", P + "/pwned", HERE + "/hook-count"):
    if os.path.exists(leftover): os.remove(leftover)
# T1: a command that hides itself on the approval card.
m, log = mock(18170, [{"bash": "touch pwned #\r\x1b[2K  $ ls -la"}, {"text": "ok \x1b]52;c;aGVsbG8=\x07 done"}])
a = App(sk(18170, "--mode", "ask"), rows=30, cols=100)
a.wait(r"Ask"); a.send("go" + ENTER)
a.wait(r"\[y\] yes", 10)
raw = a.raw
check("T1 the card shows the real command", "touch pwned" in a.term.screen(), a.term.screen())
check("T1 no erase sequence from the model reaches the terminal", b"\x1b[2K  $ ls" not in raw, raw[-300:])
a.send("n" + ENTER); a.wait(r"done", 8, "all"); a.pump(0.3)
check("T1 no clipboard sequence from the model reaches the terminal", b"\x1b]52" not in a.raw, a.raw[-200:])
a.send(CTRLD); a.exit_code(); stop(m)
# T3: Esc on a !command must not run what's queued.
m, log = mock(18171, [{"text": "x"}])
a = App(sk(18171, "--mode", "auto"))
a.wait(r"Full Auto"); a.send("!sleep 4" + ENTER); a.pump(0.6)
a.send("!touch queued-ran" + ENTER); a.pump(0.3); a.send(ESC); a.pump(1.5)
check("T3 Esc on a !command stops what's queued", not os.path.exists(P + "/queued-ran"), a.term.screen())
a.send(CTRLD); a.exit_code(); stop(m)
# T5: /resume onto a Full Auto session keeps this run's --mode ask.
m, log = mock(18172, [{"text": "first"}, {"bash": "touch resumed-ran"}, {"text": "done"}])
a = App(sk(18172, "--mode", "auto")); a.wait(r"Full Auto"); a.send("hello" + ENTER); a.wait(r"first", 8, "all"); a.gone(r"esc to stop"); a.send(CTRLD); a.exit_code()
a = App(sk(18172, "--mode", "ask")); a.wait(r"Ask")
a.send("/resume" + ENTER); a.pump(1); print(a.term.screen()[-500:])
a.send("/resume 1" + ENTER); a.pump(1)
a.send("carry on" + ENTER); ok = a.wait(r"\[y\] yes", 6)
check("T5 --mode ask still asks after /resume", ok and not os.path.exists(P + "/resumed-ran"), a.term.screen())
if ok: a.send("n" + ENTER)
a.pump(0.5); a.send(CTRLD); a.exit_code(); stop(m)
# C4: a number too big for an Int, in a call the model makes.
m, log = mock(18173, [{"tool": "web_fetch", "args": {"url": "https://example.com/", "start": 1e20}}, {"text": "survived"}])
a = App(sk(18173, "--mode", "auto")); a.wait(r"Full Auto"); a.send("fetch" + ENTER)
if a.wait(r"\[y\] yes", 25): a.send("n" + ENTER)           # the sandbox's network is off, so a fetch asks
ok = a.wait(r"action was denied", 8, "all")
code = None if ok else a.exit_code(3)
check("C4 a huge number doesn't abort the CLI", ok, (code, a.term.all()[-300:]))
if ok: a.send(CTRLD); a.exit_code()
stop(m)
m, log = mock(18174, [{"tool": "read_file", "args": {"path": 12345678901234567890123.0}}, {"text": "survived"}])
a = App(sk(18174, "--mode", "auto")); a.wait(r"Full Auto"); a.send("read" + ENTER)
ok = a.wait(r"survived", 8, "all")
code = None if ok else a.exit_code(3)
check("C4 a huge number as a path doesn't abort the CLI", ok, (code, a.term.all()[-300:]))
if ok: a.send(CTRLD); a.exit_code()
stop(m)
a = App(sk(18174, "--mode", "auto", "-c")); up = a.wait(r"Full Auto", 4)
check("C4 the session still opens", up and a.pump(0.5), a.term.all()[-200:])
if up: a.send(CTRLD); a.exit_code()
# C8: the way on from a cut PDF range goes forward.
subprocess.run(f"seq -f 'many line %g of the document' 6000 > {HERE}/many.txt && cupsfilter {HERE}/many.txt > {P}/many.pdf 2>/dev/null", shell=True)
m, log = mock(18175, [{"tool": "read_file", "args": {"path": "many.pdf", "pages": "50-90"}}, {"text": "read"}])
a = App(sk(18175, "--mode", "auto")); a.wait(r"Full Auto"); a.send("read" + ENTER); a.wait(r"\bread\b", 10, "all"); a.gone(r"esc to stop"); a.send(CTRLD); a.exit_code(); stop(m)
last = [json.loads(l) for l in open(log)][-1]["last"]
hint = re.search(r'like "(\d+)-(\d+)"', last)
check("C8 the hint goes on from where it was cut", hint and int(hint[1]) >= 50, last[-140:])
# C9: SessionStart once, not again after /compact.
os.makedirs(HERE + "/home/.kurtkode", exist_ok=True)
json.dump({"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": f"echo ran >> {HERE}/hook-count"}]}]}}, open(HERE + "/home/.kurtkode/settings.json", "w"))
m, log = mock(18176, [{"text": "one"}, {"text": "Summary of the conversation so far: the user said hello and the agent answered, and nothing else has happened yet."}, {"text": "two"}])
a = App(sk(18176, "--mode", "auto")); a.wait(r"Full Auto"); a.send("hello" + ENTER); a.wait(r"one", 8, "all"); a.gone(r"esc to stop")
a.send("/compact" + ENTER); a.pump(2); a.send("again" + ENTER); a.wait(r"two", 8, "all"); a.gone(r"esc to stop"); a.send(CTRLD); a.exit_code(); stop(m)
os.remove(HERE + "/home/.kurtkode/settings.json")
n = len(open(HERE + "/hook-count").read().split()) if os.path.exists(HERE + "/hook-count") else 0
check("C9 a compaction happened", a.wait(r"summarized|Summar", 1, "all"), a.term.all()[-300:])
check("C9 SessionStart ran once", n == 1, n)
summary()

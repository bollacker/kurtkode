from drive import *
import subprocess
# 22B.10: Phase 5 on a real local model, the one already loaded: a session in a worktree, a queued message, a fetch.
MODEL = sys.argv[1]
R = HERE + "/proj"
subprocess.run("git init -q -b main && git config user.email t@t && git config user.name t && echo one > a.txt && git add . && git commit -qm first", shell=True, cwd=R)
a = App(["--endpoint", f"lm=http://127.0.0.1:1234/v1", "-m", f"lm:{MODEL}", "--no-mcp", "--skill-router", "off", "--mode", "auto", "-w", "real"], rows=36, cols=110)
check("starts in a worktree", a.wait(r"Full Auto", 15), a.term.screen())
a.pump(0.5); a.send("Add a line saying two to the end of a.txt with a shell command, then reply DONE-ONE." + ENTER)
a.pump(1.5); a.send("Then also add a line saying three to a.txt, and reply DONE-TWO." + ENTER)
ok = a.wait(r"DONE-TWO", 100, "all")
check("the queued message was acted on", ok, a.term.all()[-500:])
a.gone(r"esc to stop", 30)
W = R + "/.worktrees/real"
text = open(W + "/a.txt").read() if os.path.exists(W + "/a.txt") else ""
check("the changes are in the worktree", "two" in text and "three" in text, text)
check("the main checkout is untouched", open(R + "/a.txt").read() == "one\n", open(R + "/a.txt").read())
a.send("Use web_fetch on https://example.com/ and tell me the page's heading." + ENTER)
asked = a.wait(r"\[y\] yes", 40)
if asked:
    a.send("y" + ENTER)
said = a.wait(r"Example Domain", 60, "all")
check("a real fetch reached a real model", said, a.term.all()[-500:])
a.gone(r"esc to stop", 20); a.send(CTRLD); print("exit", a.exit_code())
summary()

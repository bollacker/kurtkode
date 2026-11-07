# The real local models, free: python3 t11.py [fetch pdf btw stop img vision]. Needs in proj/: license.pdf (14 pages, macOS's
# /Library/Documentation/License.lpdf/.../English.lproj/License.pdf), page1.png (any image, for a model that can't see), and for
# vision label.png, opaque, reading BLUE HERON 7429 with a red rectangle. "vision" needs gemma-4-e4b-it loaded by hand and unloaded
# after, by name. Keys don't answer a question for its first half second: pause before an answer.
from drive import *
import time, sys
A = ["-m", "qwen/qwen3-coder-30b", "--no-mcp", "--mode", "auto"]
def tail(a, n=900): return a.term.all()[-n:]
def finish(a, t=150):
    a.wait(r"esc to stop", 10); return a.gone(r"esc to stop|waiting for your answer", t)
def show(a, name): print(f"----- {name}\n{tail(a, 1500)}\n-----", flush=True)
which = sys.argv[1:] or ["fetch", "pdf", "btw", "stop", "img"]
V = ["-m", "gemma-4-e4b-it", "--no-mcp", "--mode", "auto"]
if "fetch" in which:
    a = App(A); a.wait(r"Full Auto", 20); a.wait(r"^› *$", 20); a.pump(0.5); t = time.time()
    a.send("Use web_fetch to read https://en.wikipedia.org/wiki/Swift_(programming_language) and tell me, in one sentence, who designed Swift." + ENTER)
    asked = a.wait(r"always allow fetching from en\.wikipedia\.org", 90)
    check("real model asks to fetch the page", asked, tail(a)); print("asked after", round(time.time()-t), flush=True)
    a.pump(0.7); a.send("y" + ENTER); ok = finish(a, 200)
    check("run finished", ok, tail(a)); print("done after", round(time.time()-t), flush=True)
    check("answer names Lattner", "Lattner" in a.term.all(), tail(a)); show(a, "fetch")
    a.send(CTRLD); a.pump(0.2); a.send(CTRLD); a.exit_code()
if "pdf" in which:
    a = App(A); a.wait(r"Full Auto", 20); a.wait(r"^› *$", 20); a.pump(0.5); t = time.time()
    a.send("Use read_file on license.pdf. How many pages does it have, and what is the title of section 2?" + ENTER)
    ok = finish(a, 180); print("done after", round(time.time()-t), flush=True)
    al = a.term.all()
    check("pdf run finished", ok, tail(a)); check("14 pages", "14" in al, tail(a)); check("section 2 title", "Permitted License" in al, tail(a)); show(a, "pdf")
    a.send("Now use read_file with the pages parameter to read only page 14. Quote its last sentence." + ENTER)
    ok = finish(a, 120); check("page 14 run finished", ok, tail(a)); show(a, "pdf page 14")
    a.send(CTRLD); a.pump(0.2); a.send(CTRLD); a.exit_code()
if "btw" in which:
    a = App(A); a.wait(r"Full Auto", 20); a.wait(r"^› *$", 20); a.pump(0.5)
    a.send("Run the bash command: sleep 25; then say done." + ENTER)
    r = a.wait(r"Run sleep 25", 60); check("command started", r, tail(a))
    t = time.time(); a.send("/btw what is the capital of France? One word." + ENTER)
    p = a.wait(r"Paris", 40, "all"); print("btw (during a command) took", round(time.time()-t,1), flush=True); check("/btw answers during a command", p, tail(a))
    ok = finish(a, 90); check("the run still finished", ok, tail(a)); show(a, "btw during command")
    t = time.time(); a.send("Write a 300 word story about a sailor." + ENTER)
    a.wait(r"esc to stop", 10); a.pump(6)
    t2 = time.time(); a.send("/btw what is 7 times 6? Digits only." + ENTER)
    p = a.wait(r"\b42\b", 90, "all"); print("btw (during streaming) took", round(time.time()-t2,1), flush=True); check("/btw answers during streaming", p, tail(a))
    ok = finish(a, 120); check("the story finished", ok, tail(a)); show(a, "btw during stream")
    a.send(CTRLD); a.pump(0.2); a.send(CTRLD); a.exit_code()
if "stop" in which:
    a = App(A); a.wait(r"Full Auto", 20); a.wait(r"^› *$", 20); a.pump(0.5)
    a.send("Count slowly from 1 to 400, one number per line." + ENTER)
    a.wait(r"esc to stop", 10); a.pump(12)
    a.send(ESC); g = a.gone(r"esc to stop", 8); check("esc ends the real stream", g, tail(a))
    t = time.time(); a.send("Say only the word ready." + ENTER)
    ok = finish(a, 60); print("next reply after stop took", round(time.time()-t,1), flush=True)
    check("the model answers straight after", ok and re.search(r"ready", a.term.all()[-200:], re.I), tail(a)); show(a, "stop")
    a.send(CTRLD); a.pump(0.2); a.send(CTRLD); a.exit_code()
if "img" in which:
    a = App(A); a.wait(r"Full Auto", 20); a.wait(r"^› *$", 20); a.pump(0.5)
    a.send("Read page1.png with read_file and tell me what it shows." + ENTER)
    ok = finish(a, 90); check("non-vision run finished", ok, tail(a)); show(a, "image on qwen3")
    a.send(CTRLD); a.pump(0.2); a.send(CTRLD); a.exit_code()
if "vision" in which:
    a = App(V); a.wait(r"Full Auto", 40); a.wait(r"^› *$", 40); a.pump(0.5); t = time.time()
    a.send("Use read_file on label.png, then tell me what words and number are written in the image and the colour of the rectangle." + ENTER)
    ok = finish(a, 150); print("vision took", round(time.time()-t), flush=True)
    check("vision run finished", ok, tail(a)); check("it read the page", re.search(r"BLUE HERON", a.term.all(), re.I), tail(a)); show(a, "vision")
    a.send(CTRLD); a.pump(0.2); a.send(CTRLD); a.exit_code()
summary()

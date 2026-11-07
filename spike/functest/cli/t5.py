from drive import *
import struct, zlib
sk = lambda port, *m: [x for x in args(port, *m)]
# What the scenario reads: a user hook (trusted, so it needs no approval) and a real PNG, a red square.
os.makedirs(HERE + "/home/.kurtkode", exist_ok=True)
json.dump({"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "echo hook-says-hello"}]}]}},
          open(HERE + "/home/.kurtkode/settings.json", "w"))
def _chunk(kind, data): return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
open(HERE + "/proj/shot.png", "wb").write(b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0))
    + _chunk(b"IDAT", zlib.compress((b"\0" + b"\xff\0\0" * 8) * 8)) + _chunk(b"IEND", b""))
# web_fetch in Full Auto, sandbox network off: must ask. Then a local address, which is refused outright.
m, log = mock(18130, [{"tool": "web_fetch", "args": {"url": "https://example.com/"}}, {"text": "read the page"},
                      {"tool": "web_fetch", "args": {"url": "http://127.0.0.1:18130/v1/models"}}, {"text": "that was refused"},
                      {"tool": "read_file", "args": {"path": "shot.png"}}, {"text": "red square"},
                      {"text": "It was about the parser."}, {"text": "after side"}])
a = App(sk(18130, "--mode", "auto", "--sandbox", "always"))
a.wait(r"Full Auto")
a.send("fetch it" + ENTER)
check("fetch asks in Full Auto with network off", a.wait(r"network is off", 10, "all"), a.term.all()[-500:])
check("offers the domain", a.wait(r"always allow fetching from example\.com", 3, "all"), a.term.all()[-400:])
a.pump(0.6)                     # keys don't answer a question in its first half second
a.send("a" + ENTER)
check("real fetch of a public page came back", a.wait(r"read the page", 25, "all"), a.term.all()[-500:])
a.gone(r"esc to stop")
reqs = [json.loads(l) for l in open(log)]
check("the page reached the model, marked as data", any("not instructions from the user" in r["last"] and "This domain is for use" in r["last"] for r in reqs), reqs[-1]["last"][:300])
check("SessionStart hook reached the model", any("hook-says-hello" in u for r in reqs for u in r["users"]), reqs[0]["users"])
mark = len(a.term.all())
a.send("fetch something local" + ENTER)
check("a local address is refused without asking", a.wait(r"on this machine or network", 10, "all") and "yes  [n] no" not in a.term.all()[mark:], a.term.all()[mark:])
a.wait(r"that was refused", 10, "all"); a.gone(r"esc to stop")
reqs = [json.loads(l) for l in open(log)]
check("no request reached the local server", len([r for r in reqs if r["path"] != "/v1/chat/completions"]) == 0, [r["path"] for r in reqs])
a.send("look at the picture" + ENTER)
check("reads an image", a.wait(r"red square", 10, "all"), a.term.all()[-400:])
a.gone(r"esc to stop"); a.pump(0.3)
raw = open(log).read()
check("the image went in the request", "data:image/png;base64" in raw, raw[-500:])
a.send("/btw what was this about?" + ENTER)
check("/btw answers on the side", a.wait(r"On the side: It was about the parser", 10, "all"), a.term.all()[-400:])
reqs = [json.loads(l) for l in open(log)]
check("/btw sent the conversation as text, not as history", reqs[-1]["messages"] == 1 and "side question" in reqs[-1]["last"], reqs[-1])
a.send("carry on" + ENTER); a.wait(r"after side", 8, "all"); a.gone(r"esc to stop")
reqs = [json.loads(l) for l in open(log)]
check("/btw isn't in the conversation", not any("what was this about" in u for u in reqs[-1]["users"]), reqs[-1]["users"])
a.send(CTRLD); a.exit_code(); stop(m)
# a /btw during a run
m, log = mock(18131, [{"bash": "sleep 6; echo done"}, {"text": "Quick answer."}, {"text": "run finished"}])
a = App(sk(18131, "--mode", "auto"))
a.wait(r"Full Auto"); a.send("go" + ENTER); a.wait(r"Run sleep 6", 10)
a.pump(0.3); a.send("/btw anything?" + ENTER)
check("/btw during a run doesn't queue", a.wait(r"Asking on the side", 4, "all") and "⏵" not in a.term.screen(), a.term.screen())
check("/btw during a run answers", a.wait(r"On the side: Quick answer", 8, "all"), a.term.all()[-300:])
check("the run still finishes", a.wait(r"run finished", 12, "all"), a.term.all()[-300:])
a.gone(r"esc to stop"); a.send(CTRLD); a.exit_code(); stop(m)
summary()

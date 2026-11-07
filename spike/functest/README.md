# Functional-test helpers (sessions 6 and 7)

Small scripts used to run `FUNCTIONAL_TESTS.md`. Copy them to a scratch folder and run from there (they write
screenshots and logs next to themselves).

- `cli/`: the live-screen CLI in a real pty. `vt.py` is a small terminal (a screen grid and scrollback fed the real bytes),
  `drive.py` the harness (`App`, `mock`, `check`), `t1`–`t11.py` the scenarios (`t11` on the real local models; `t6`: `ask_user`'s picker; `t7`: real PDFs and images; `t8`: every way out restores the terminal; `t9`: round 8's probes, which fail until fixed; `t10 MODEL`: a real model already loaded), `mock.py` is `pmock.py` logging what the
  model was sent. Copy the folder to a scratch place, make `home/` and `proj/` in it, and run `python3 t1.py` (needs
  `swift build --product kurtkode`). `drive.py` refuses to run unless the data folder is really the scratch one.
- `kk.sh VAR=val …` launches (in the background: `open -n -g`, so it doesn't take the user's keystrokes) the Debug app (`APP=…` for another build) with `--env` for each pair and prints the **new**
  instance's pid, found by diffing pids before and after `open -n` (pids wrap; "the highest pid" once named the wrong
  instance). Stop instances by that pid only.
- `waitfor.py EPOCH "prompt text" SECONDS` waits until a plain chat containing that text has a finished reply. Match on
  the prompt: "the newest session" is fooled by any other chat finishing.
- `sess.py PROJECTPREFIX|FILE [--after EPOCH] [--wait S] [--quiet]` prints a session's records (and can wait for it).
- `ptydrive.py SCRIPT.json -- argv…` drives the CLI in a pty: SCRIPT is `[[wait_seconds_or_regex, "keys"], …]`
  (`\r` Enter, `\u0003` Ctrl-C). Run with `python3 -I` (its old name `pty.py` shadowed the stdlib module).
- `smock.py PORT STEP…` a scripted OpenAI-compatible server, one step per request (the last repeats):
  `NNN[:message]` (any HTTP status with that error body, Retry-After 1), `drop` (a chunk, then the connection closes),
  `lost:PROV` (empty reply, 80 output tokens), `ok:PROV:TEXT`, `empty`, `429`, `500`, `die`, `hang`.
- `winnames.swift` (`swiftc -O winnames.swift -o winnames`; `./winnames PID`) lists a process's windows for
  `screencapture -x -o -l ID`.
- `mkfix.py DIR` makes the `calc` and `parts` demo projects (8 × `lib/partN.py`, a class and "keeps N records" each).
- `crashdrive.py SCRIPT.json -- argv…` like `ptydrive.py`, plus a step whose keys are `KILL9` (SIGKILL the CLI) and waits
  of the form `FILE:regex:glob` (until the newest matching file contains regex). Session 7's crash tests (16.1).
- `quitpid.swift` (`swiftc -O quitpid.swift -o quitpid`; `./quitpid PID`) quits one app instance the way Quit does
  (`NSRunningApplication.terminate()`), never another instance with the same bundle id.
- `soak.sh` the 16.10 streaming soak (see its header).
- `pmock.py PORT SCRIPT.json LOG` (round 4) a priced OpenAI-compatible mock: `/models` lists OpenRouter-style prices
  (`pm/model`: $2/M in, $10/M out, $0.001 a request), and chat completions play SCRIPT one step per request (`text`,
  `bash`, `tool`+`args`, `calls`, `usage`, `status`, `drop`, `sleep`; the last step repeats). Point kurtkode at
  `http://0.0.0.0:PORT/v1` (not 127.0.0.1) so it counts as a remote server and prices the replies, with no key.

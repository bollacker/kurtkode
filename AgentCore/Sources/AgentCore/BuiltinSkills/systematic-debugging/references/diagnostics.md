# Reading failures and driving debuggers from a shell

Read this when a trace, log, crash or hang is hard to interpret, or when you need a debugger. Agents can't type
into an interactive debugger session reliably, so every command here runs to completion and prints.

## Stack traces by language

| Language | Where the failure is | More detail |
|---|---|---|
| Python | Last line is the exception; the frame just above it is where it was raised. Chained traces: read the first one ("During handling…" / "The above exception was the direct cause…") | `python3 -X dev`, `PYTHONFAULTHANDLER=1` (segfaults, hangs) |
| Node / JS | Top frame (after the message) is innermost; frames in `node_modules` are rarely the cause | `node --enable-source-maps`, `--stack-trace-limit=100`; unhandled rejections: `--unhandled-rejections=strict` |
| Go | `panic:` line, then the panicking goroutine first; look for the first frame in your module | `GOTRACEBACK=all` (every goroutine), `GOTRACEBACK=crash` (core dump) |
| Rust | `thread 'main' panicked at src/x.rs:L:C` | `RUST_BACKTRACE=1` (or `full`) |
| Java / Kotlin | Read the last `Caused by:`; `... N more` repeats frames above | `-XX:+ShowCodeDetailsInExceptionMessages` (NPE detail) |
| Swift | `Fatal error:` line and the crash report's crashed thread | build debug (`swift build`), symbolicate with `atos` |
| C / C++ | Usually a signal (SIGSEGV, SIGABRT) with no trace: use a debugger or sanitizer | `-g -O0 -fsanitize=address,undefined` |

## Logs

- Find the **first** error, not the last: later errors are often consequences. `grep -n -m1 -iE 'error|exception|fatal' app.log`.
- Follow one request or job: filter by its id or timestamp window, then read in order.
- Raise verbosity for one run instead of adding prints everywhere: `RUST_LOG=debug`, `NODE_DEBUG=http,net`,
  `DEBUG=*` (debug package), `logging.basicConfig(level=logging.DEBUG)`, `GODEBUG=...`.

## Debuggers in batch mode

Python (post-mortem at the exception, print the stack and locals, quit):
```
printf 'bt\np {k: v for k, v in locals().items() if not k.startswith("__")}\nq\n' | python3 -m pdb -c continue script.py args
```
Or without pdb: wrap the call in `try/except` and print `traceback.format_exc()` plus the suspicious values with `repr()`.

gdb (native code, run until crash, print the backtrace and locals):
```
gdb -batch -ex run -ex bt -ex 'info locals' --args ./prog arg1 arg2
```

lldb (macOS; `-k` runs its commands only if the process stops on a crash):
```
lldb --batch -o run -k bt -k 'frame variable' -- ./prog arg1 arg2
```

Node (no batch debugger; print the stack where a value goes wrong):
```
console.trace('order at checkout', JSON.stringify(order));
```

Go: `dlv` is interactive; prefer a focused test with `t.Logf("%#v", v)` and `go test -run TestName -v`.

## Core dumps

- Linux: `ulimit -c unlimited`, rerun, then `gdb -batch -ex bt ./prog core` (location set by `/proc/sys/kernel/core_pattern`;
  with systemd: `coredumpctl debug`).
- macOS: `ulimit -c unlimited`, cores land in `/cores/`; `lldb --batch -c /cores/core.<pid> -o bt`.

## Hangs

- Python: `PYTHONFAULTHANDLER=1` plus `kill -ABRT <pid>`, or `faulthandler.dump_traceback_later(30)` in the entry point; `py-spy dump --pid <pid>` if installed.
- Java: `jstack <pid>`, or `kill -QUIT <pid>` (dump goes to the process's stdout).
- Go: `kill -QUIT <pid>` prints every goroutine.
- Native: `gdb -p <pid> -batch -ex 'thread apply all bt'`; macOS `sample <pid> 5`.
- A hang with threads or locks involved: see the concurrency skill.

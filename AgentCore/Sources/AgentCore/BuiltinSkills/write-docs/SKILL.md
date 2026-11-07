---
name: write-docs
description: Use when asked to write or fix a README, usage or install guide, API reference, docstrings or code comments. Docs whose commands and facts were checked. Not for changelogs (release) or handoff notes (handoff-notes).
---

# Write documentation that is true

Write docs from what the code does, and run every command you show, so a reader can follow them without surprises.

## Fast path

A docstring or a comment: state the contract of the code as it is (inputs, output, errors raised, side effects);
in comments say why, not what. If you show a call or a command, run it once. Done.

## Steps

1. **Know the reader and the kind of doc.**
   - README: what it is (one sentence), requirements, quick start, every command or option, configuration
     (environment variables, files, defaults), exit codes and common errors.
   - API reference / docstrings: signature, parameters with units and allowed values, return value, errors,
     side effects, one example.
   - Comments: the reason behind non-obvious code (a constraint, a bug it avoids, a ticket). Nothing that
     repeats the code.

2. **Collect facts from the code, not from other docs.** Existing comments, docstrings and wikis go stale; when
   they disagree with the code, the code wins (and mention the mismatch in your report). Find:
   - entry points and options: `--help` output, the argument parser (argparse, click, cobra, clap, commander),
     `package.json` "bin"/"scripts", `Makefile`, `pyproject.toml` scripts. Is there an install step at all?
   - environment variables: `git grep -nE "environ|getenv|process\.env|os\.Getenv|ENV\["`
   - files read or written and their default paths; exit codes: `git grep -nE "exit\(|Exit\("`
   - argument order and formats (dates, amounts, units), which differ between subcommands more often than you expect.

3. **Run everything you will show.** In a scratch copy, from a fresh state, run each command in the order a
   reader would and keep the real output. Try the failure cases you document (bad input, missing config) to get
   the real message and exit code (`echo $?`).

4. **Write.** Order a README as: what it is, requirements, install (only if one exists), quick start, reference
   (commands, options, configuration, exit codes), troubleshooting. Put commands in ```sh blocks that run as
   pasted, in order; put output in separate ```text blocks. A command that is meant to fail goes in a text block
   or ends with `|| true` and says so. Use the exact invocation that works here (`python3 tool.py`, `./tool`,
   `npx tool`), not one that needs an install that doesn't exist.

5. **Check the doc mechanically.** Run
   `python3 <skill folder>/scripts/check_doc_commands.py README.md`
   It copies the project's tracked files and the doc to a scratch folder and runs all sh/bash/console blocks in
   order in one shell. Fix the doc (not the code) until it prints `RESULT ... failed=0`, and run it again after
   your last edit.

## Rules

- **Don't** document a flag, default, path or install step you have not seen in the code or in a run. Guessed
  commands are the most common doc bug.
- **Don't** copy facts from existing comments or docs without checking them against the code.
- Don't change the code to match the doc unless asked. If the code looks wrong, document what it does and report
  the suspected bug.
- No placeholders that look runnable (`<your-token>` inside a sh block); show how to set them and mark them.
- Comments: no history ("changed X to Y"), no restating the code; keep them true when you edit nearby code.

## When no one can answer

Write for a new user on a fresh checkout. When the intended behavior is unclear, document the observed behavior,
mark it ("currently …"), and list the question in your report. Don't invent features or roadmaps.

## Done means

- The doc file, whose command blocks pass `check_doc_commands.py` (quote its RESULT line in your report).
- A short report: where each key fact came from (file:line or the command run), the mismatches found between
  old docs/comments and the code, and anything left undocumented.

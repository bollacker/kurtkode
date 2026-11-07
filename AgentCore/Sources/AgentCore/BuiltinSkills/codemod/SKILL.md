---
name: codemod
description: Use when one mechanical change must hit many files, like renaming an API everywhere, updating call sites or imports, or replacing a deprecated pattern. Inventory, dry run, exact change set. Not for one function (refactor-safely).
---

# Codemod: one mechanical change across many files

Make the same change at every place it belongs and nowhere else, with an inventory before and a check after.

## Fast path

Fewer than about five occurrences, all plain code, and no other symbol of the same name anywhere: edit them by hand,
search again to confirm none are left, run the tests. Any look-alike, string or second definition: use the steps.

## Steps

1. **Pin down the change.** Write: old name, new name, and which symbol (module or class plus name). List what
   counts as a reference: imports (also aliased ones), calls, `module.name` attribute access, re-exports, export
   lists (`__all__`, `export {}`), mock or patch targets, reflection (`getattr`, registries, routes, DI config).
   List what must stay: other symbols with the same name, and strings that are contracts with the outside (metric
   names, log text, config keys, API fields, database columns). Check that the new name is free in the scopes
   you will touch.

2. **Inventory every occurrence.**
   `python3 <skill folder>/scripts/codemod.py find OLD [PATH ...] > <scratch>/inventory.txt`
   One line per whole-word hit: `path:line:col  KIND  source line`, with KIND `code:def`, `code:import`,
   `code:attr(receiver)`, `code`, `string`, `comment` or `doc`, then `TOTAL` counts and a `LOOKALIKE` line naming
   identifiers that contain OLD (a plain text replace would break those). Exit 1 means hits were found.
   Read every line and decide keep or change. The usual traps:
   - a second `code:def` of the same name in another module, and that module's callers;
   - `code:attr(x)` where `x` is some other object (a client, a different class) with a method of that name;
   - `import old as alias`: change the import, not the alias's uses;
   - strings that are references (patch targets, `__all__`, `getattr`) next to strings that are contracts;
   - generated, vendored or lock files: regenerate them, never edit by hand.
   If the change crosses languages, also search the other spellings (`fetchUser`, `fetch-user`, `module.old`).

3. **Choose the tool.** Prefer a language-aware rename where one is installed: the editor's or language server's
   rename (gopls, rust-analyzer, TypeScript), `gofmt -r`, ast-grep, comby, jscodeshift, OpenRewrite, rope. Otherwise
   apply the reviewed inventory: copy the lines you decided to change into `<scratch>/selected.txt`.

4. **Dry run and read the diff.**
   `python3 <skill folder>/scripts/codemod.py apply OLD NEW --from <scratch>/selected.txt`
   prints a unified diff and `DRY RUN n locations in m files`. Read all of it (for hundreds of hits: every unusual
   kind and a sample of each common one). `MISMATCH` lines mean a file changed since the inventory: run find again.

5. **Apply** with `--write` (exit 0 = every location written). For changes that are not renames (new argument
   order, a call replaced by another), script one pattern at a time with the language tool and list the cases you
   finished by hand.

6. **Verify.** Run `find OLD` again: what is left must be exactly what you decided to keep. Run the compiler or
   type checker and the full test suite. `git diff --stat` must list the files you planned, no others.

## Rules

- **Don't** switch to editing the occurrences one by one after the inventory: it costs a step per file, and the
  ones you miss are the ones the tests don't cover. Apply the reviewed selection with the script (or the language
  tool) in one pass.
- **Don't** run a repo-wide `sed -i` or editor replace-all without the reviewed inventory. It hits strings,
  comments, other modules' symbols, and look-alikes when the pattern has no word boundaries.
- **Don't** change contract strings (metric names, log text, config keys, API or DB names) unless asked: other
  systems match on them and nothing in the repo will fail to tell you.
- **Don't** mix the mechanical change with other cleanups (formatting, import order, renaming neighbors). The diff
  must be exactly the change so it can be reviewed.
- **Don't** leave a compatibility alias unless asked. If outside code may import the old name (a published
  library), say so in the report and offer a deprecated alias.

## When no one can answer

For an occurrence you can't classify, change it if code resolves it at run time (patch targets, export lists,
reflection) and leave it if it is text for people or other systems (logs, metrics, docs about another symbol).
Record each such decision in the report. Stop only if the change would break a public interface used outside
the repo and the request did not mention it.

## Done means

- The change applied: `n` locations in `m` files, and the tool used.
- What was left on purpose, grouped with a reason (other module's symbol, contract string, look-alike).
- Evidence: the final `find` output matching the keep list, and the compile and full-test results.

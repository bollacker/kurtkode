# kurtkode

A coding agent for macOS, as a SwiftUI app and a command-line tool, in the family of Claude Code, Codex and opencode,
built around **cost**: what a task costs to get done, not only whether it gets done.

- **Any model, priced.** Local models through LM Studio, Anthropic, Google Gemini, OpenRouter and other
  OpenAI-compatible servers. Every request is recorded with its tokens by kind and its list price; `kurtkode cost
  report` and the app's Spending window show what runs cost and what passed.
- **Cheaper models where they're enough.** A model pool with tiers and roles routes subagents to cheaper models by the
  task, retries one rung up on a hard failure, and grades or reviews important work (COST_ARCHITECTURE.md).
- **Prompt caching treated as a cost lever.** Stable prompt prefixes, an hour's cache for the sessions you're in,
  cache keys and provider stickiness, and a ledger that names the cause and cost of every cache miss
  (`kurtkode cost cache`; CACHING_REPORT.md, CACHING_PLAN.md).
- **The agent itself.** File tools, a sandboxed shell, plan mode, subagents (also in worktrees), skills, MCP servers,
  hooks, checkpoints and rewind, compaction, and a CLI with a live screen.

## Building

Needs macOS 15 or later, Xcode (Swift 6) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
make build        # the app (Debug), into build/DerivedData
make test         # AgentCore, EvalKit and CLI tests
make cli          # the command-line kurtkode (release)
make install      # the app into /Applications
make install-cli  # the CLI into ~/.local/bin
```

`make run` builds and opens the app. Endpoints and keys are added in the app's Settings, or with
`kurtkode endpoint add`; keys are kept in the macOS Keychain.

## Documents

The design and its measurements are in the repository's Markdown files. `HANDOFF.md` is the running log of what was
built and where things stand ("Start here" entries, newest first). `PLAN.md` is the original plan, `GAP_ANALYSIS.md`
the comparison with other coding agents, and `COST_AUDIT.md` the measured cost study. `EVAL_PLAN.md` describes the
evaluation harness (`kurtkode-eval`) whose results are under `eval-results/`.

## License

GNU General Public License v3.0 (`LICENSE`). Third-party material and its licenses: `THIRD_PARTY_NOTICES.md`.

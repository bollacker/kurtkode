# The system prompt: architecture

Written 2026-10-24. The system prompt's own words used to be Swift string literals in `SystemPrompt.swift`, so changing
a sentence took a rebuild, and comparing variants needed a code change. The prompt's wording now lives in Markdown
templates. kurtkode ships default templates, and a user or project can override any of them or add styles of its own.
The code assembles the prompt and supplies the facts. It no longer holds the prompt's working rules.

## What a system prompt is made of

```
┌──────────────────────────────────────────────┐
│ head            ← templates                  │  style-<name>.md, with intro.md and mode.md inside it
├──────────────────────────────────────────────┤
│ Environment:    ← code                       │  platform, other folders
├──────────────────────────────────────────────┤
│ Tools available: …  ← code                   │  the names of the tools offered this run
├──────────────────────────────────────────────┤
│ Instructions from … ← files, verbatim        │  user, parent-folder and project files, memory (B6)
├──────────────────────────────────────────────┤
│ extra instructions  ← Settings, verbatim     │  Settings → Generation → System prompt → "Extra instructions"
├──────────────────────────────────────────────┤
│ + a profile's addendum, a subagent's preamble and role (inserted here by their owners: `insertingStable`)
╞══════════════════════════════════════════════╡  ← cache breakpoint on the Claude wires (Anthropic, OpenRouter)
│ Current environment (changes between runs):  │  project root / working folder, then the facts: date and git
│                 ← code                       │  status (always last)
└──────────────────────────────────────────────┘
  + a compaction summary (appended by the compactor)
```

`SystemPromptBuilder` (`AgentCore/Sources/AgentCore/Agent/SystemPrompt.swift`) builds the head with `head()` and the
rest in `buildWithFacts`. Only the head is templated. The other sections are generated data: paths, the tool list, and
files the user already edits. Their order matters to prompt caches. Everything that differs from one run to the next
(the project root, which every eval run and worktree has its own of, the date, the git status) is in the last section,
under the fixed heading `SystemPromptBuilder.volatileHeading`, so two runs with the same tools and instructions share
everything before it. The Anthropic and OpenRouter-Claude encoders split the system prompt at that heading and put a
cache breakpoint on the part before it (`AnthropicWire.systemBlocks`, `WireFormat.withCacheBreakpoints`); other
providers cache prefixes by themselves. Before this order (the cost audit's F4, 2026-10-26), the environment came right
after the head, and Haiku read a cache across runs 0 times in 480. The facts come last so that a resumed session can
keep its recorded prompt and get the new date and git status in a message (see "Identity and caches" below). Instruction files and the extra instructions are never run through the template engine,
so `{{` in an AGENTS.md is just text.

## The templates

| File | What it is | Placed by |
|---|---|---|
| `intro.md` | Who the agent is: a coding agent in a project, or an assistant in a chat's working folder | `{{intro}}` in a style |
| `mode.md` | What the agent may do in the permission mode: read-only, approvals or Full Auto, the sandbox, destructive commands | `{{mode_rules}}` in a style |
| `style-detailed.md` | Step-by-step working rules for small local models (grep first, one file at a time, don't repeat calls) | the style setting |
| `style-lean.md` | Short rules for frontier models, which do worse when over-constrained | the style setting |
| `style-<name>.md` | A style of your own; it shows up in the style picker and in `--prompt-style` | the style setting |
| `delegation.md` | When to hand work to a subagent, and when not (detailed, or short with `lean`); only when the task tool is offered | `{{delegation}}` in a style, inside `{{#subagents}}` |
| `skills.md` | One line telling the model to check the skill list before a task and load a matching skill first; only when the skill tool is offered (built-in skills, or the project's or user's) | `{{skills_note}}` in a style, inside `{{#skills}}` |
| `router-skill.md` | The skill router's side question (`SkillRouter`, Settings → Generation → Agent → "Skill router"): which one skill fits the new request, or none. Not part of the system prompt; values `skills` (one "- name: description" line each) and `request` | the router |
| `tool-task.md` | The `task` tool's description (`{{agents}}`: the agents and what each is for) | the tool |
| `tool-rate-task.md` | The `rate_task` tool's description | the tool |
| `note-delegate.md` | The note added to a tool result after broad reading (`{{reads}}`, `{{tokens}}`) | the loop |

The builder renders `intro` and `mode` first, then renders the chosen style with their results as `{{intro}}` and
`{{mode_rules}}`. A style can therefore reorder, drop or reword anything in the head. A style that leaves out
`{{mode_rules}}` also leaves out the mode's rules: what's enforced (approvals, the sandbox, the danger check,
permission rules) is still enforced in code, but the model isn't told about it.

### Where they're looked up

First found wins:

1. **The project**: `<project>/.kurtkode/prompts/<name>.md`
2. **The user**: `~/.kurtkode/prompts/<name>.md` (what Settings → Prompts edits)
3. **kurtkode's defaults**: the `Prompts` resources of AgentCore (`AgentCore/Sources/AgentCore/Prompts/`)

`PromptTemplates` (`Agent/PromptTemplates.swift`) holds the search order. `PromptTemplates.standard(project:)` gives
the order above. The eval builds its own (see below).

- An override that doesn't parse gives way to the default for that one file, and the session still gets a prompt.
  Settings refuses to save text that doesn't parse, and says why.
- If no template has the chosen style's name (for example a style file was deleted while Settings still names it),
  the builder uses `detailed` (`resolvedStyle`).
- Project templates take effect without an approval, like a project's AGENTS.md. They change what the model is told,
  not what kurtkode allows.

### Where the defaults are found at run time

They're a SwiftPM resource (`resources: [.copy("Prompts")]` in `Package.swift`), packaged in
`AgentCore_AgentCore.bundle`. `PromptTemplates.defaultsFolder` looks for it in these places:

- **The app**: `kurtkode.app/Contents/Resources/AgentCore_AgentCore.bundle` (Xcode embeds it; nothing to do).
- **The CLI and the eval**: next to the binary (`.build/{debug,release}/`). `make install-cli` copies the bundle
  into `~/.local/bin` with the binary.
- **Tests and `swift run`**: next to the test bundle, else the source folder (from `#filePath`).

If the bundle is missing, the process says so once on stderr, and prompts are built without a head (environment,
tools and instructions only) rather than with wording the code would have to invent.

## The template language

The language is a small subset of Mustache (`PromptTemplate`):

| Syntax | Meaning |
|---|---|
| `{{name}}` | The variable's text. An unknown name is left as written, so a typo shows in the prompt (Debug → Request). |
| `{{#name}}…{{/name}}` | Kept when the variable is set and not empty |
| `{{^name}}…{{/name}}` | Kept when it isn't |
| `{{! … }}` | A comment (may span lines; it can't contain `}}`) |

- **Standalone lines**: a line holding only a section tag or a comment is removed together with its newline, so
  sections can sit on lines of their own without leaving blank lines.
- **Final newline**: exactly one final newline is dropped from each rendered template, because files end with one and
  the prompt's parts are joined with blank lines.
- **What's missing on purpose**: partials, loops, escaping and lambdas. Variables are plain text.

### Variables

Flags are `"1"` when true and empty when false, so they work in sections.

| Variable | Kind | Value |
|---|---|---|
| `chat` | flag | a plain chat (a working folder, not a project) |
| `read_only` | flag | Plan mode, or no tool offered that changes anything |
| `plan` | flag | Plan mode (read-only commands, `present_plan`) |
| `full_auto` | flag | Full Auto: actions run without asking |
| `sandbox` | flag | commands run in the sandbox |
| `network` | flag | the sandbox allows the network |
| `other_folders` | flag | the session has extra folders |
| `writable_folders` | flag | one of them is read and write |
| `mode` | text | `ask`, `acceptEdits`, `plan` or `fullAuto` |
| `style` | text | the style used |
| `lean` | flag | the style used is `lean` |
| `subagents` | flag | the task tool is offered (subagents are on) |
| `delegation` | text | the rendered `delegation.md` (in styles, when `subagents`) |
| `skills` | flag | the skill tool is offered (some skill exists: kurtkode's built-in ones, unless Settings turns them off, or the project's or user's) |
| `skills_note` | text | the rendered `skills.md` (in styles, when `skills`) |
| `root` | text | the project root or working folder's path |
| `tools` | text | the tool names, comma-separated |
| `intro` | text | the rendered `intro.md` (in styles) |
| `mode_rules` | text | the rendered `mode.md` (in styles) |

To add a variable, add it to `SystemPromptBuilder.templateValues` and to this table.

## Styles

`PromptStyle` is a name: any template name made of lowercase letters, digits and hyphens. It used to be a two-case
enum. The `detailed` and `lean` constants and `PromptStyle.automatic(for:)` (lean for the Anthropic and Gemini APIs,
detailed for OpenAI-compatible servers) are unchanged.

You can choose a style in four places:

- Settings → Generation → System prompt (Automatic, or any style found).
- `RunSettings.promptStyle` (the `promptStyle` default, shared with the CLI).
- `kurtkode prompts render --style`.
- `kurtkode-eval --prompt-style`. It refuses a style with no template.

Run and cost records keep the style's name (`AgentRunRecord.setup.promptStyle`, `CostScope.promptStyle`), so runs on
your own styles can be compared with `kurtkode runs`.

## Identity and caches

`FrozenSystemPrompt` keeps one prompt per session, so that the server's prompt cache keeps hitting. It rebuilds only
when its **key** changes, and it reuses the session's **recorded** prompt across processes when the key matches and
only the facts differ. The key is the mode, the sandbox, the addendum, the folders and the chat flag, plus two parts
that are added only when they're not the default:

- `|<style>` when the style isn't `detailed` (`|lean` as before)
- `|sub` when subagents are on (the prompt then holds the delegation rules)
- `|t:<hash>` when an override among the templates in use differs from the default text
  (`PromptTemplates.fingerprint`)

What follows from this:

- **Sessions recorded before templates existed keep their keys**, so they resume from cache. The default templates
  render byte-for-byte what the old code did. This was checked on 288 combinations of style, chat, mode, sandbox,
  folders and tool set before the old code was removed. A saved copy of a default (identical text) adds nothing to the
  key. The delegation rules (P2 of SUBAGENT_ROUTING_DESIGN.md) are the exception: a session with
  subagents on, which is the app's default for projects, has a new prompt, so its next request after the update reads
  the prompt without the cache once.
- **An edit applies at a session's next prompt**, for running sessions too: one request re-reads the whole prompt
  without the cache, as when the style changes. Resetting to the default changes the key back, but a session that
  recorded the edited prompt rebuilds once more.
- An edit to AGENTS.md or the extra instructions doesn't change the key: it reaches a running session only when
  something else does, and a resumed session picks it up. That's as before.

`SandboxPolicy.promptText` still exists. It's part of the key, which identifies the sandbox policy, and changing it
would void every recorded key. The words the model reads come from `mode.md`.

## Editing

- **The app**: Settings → **Prompts**. The list shows the intro, the mode rules and each style, each marked *edited*,
  *yours* (a style with no default) or *unsaved*. The editor checks the text as you type.
  - *Save* (⌘S) writes `~/.kurtkode/prompts/<name>.md`. Saving the default's exact text removes the file instead.
  - *Revert* drops unsaved text.
  - *Reset to Default…* deletes your file, after a confirmation. For your own styles it's *Delete Style…*.
  - *Reset All to Default…* removes your edits to the shipped templates and keeps your styles.
  - *New Style…* starts a style as a copy of the current detailed text.
  - *Show in Finder* opens the folder.
- **The CLI** (`KurtkodeCLI/DebugCommands.swift`):
  ```
  kurtkode prompts [list]                         # each template and where it comes from (default, yours, project)
  kurtkode prompts show NAME                      # the text in effect here
  kurtkode prompts reset NAME | reset --all       # remove your override (--all: of kurtkode's own templates)
  kurtkode prompts render [--style S] [--mode M]  # the prompt a session in this folder would start with
  ```
- **A project**: commit `.kurtkode/prompts/*.md`. It applies to everyone who works in that project with kurtkode.
- **The eval** reads neither your templates nor the project's, so runs stay comparable across machines (as with
  `~/.kurtkode/AGENTS.md`). To try a variant:
  `kurtkode-eval --prompt-dir DIR [--prompt-style NAME] …`, where `DIR` holds the templates that differ.

## Code map

| Piece | Where |
|---|---|
| Default templates | `AgentCore/Sources/AgentCore/Prompts/*.md` |
| Template language, lookup, overrides, fingerprint | `AgentCore/Sources/AgentCore/Agent/PromptTemplates.swift` (`PromptTemplate`, `PromptTemplates`) |
| Variables, head, assembly, `PromptStyle` | `AgentCore/Sources/AgentCore/Agent/SystemPrompt.swift` (`SystemPromptBuilder`) |
| Key and reuse across processes | `AgentCore/Sources/AgentCore/Agent/SessionRun.swift` (`FrozenSystemPrompt.text`) |
| Settings → Prompts; the style picker | `App/Sources/Views/PromptSettings.swift`; `SettingsView.swift` (`GenerationSettings`) |
| `kurtkode prompts` | `AgentCore/Sources/KurtkodeCLI/DebugCommands.swift` |
| Eval options | `AgentCore/Sources/kurtkode-eval/main.swift`, `EvalKit/Runner.swift` (`ModelTarget.promptDir`) |
| Tests | `AgentCore/Tests/AgentCoreTests/PromptTemplateTests.swift` |

## Still in code

Other text sent to models is still written in Swift. Each could move to a template the same way:

- **Subagents**: the preamble and the built-in agents' roles (`Subagents.swift`). Custom agents are already Markdown
  files.
- **Compaction**: the summary request and the note on a trimmed reply (`Context.swift`).
- **Nudges and loop notes**: an empty reply, open todos, a repeated call, a cut-off call (`AgentLoop.swift`).
- **Tool descriptions**: in each tool's definition, except `task` and `rate_task` (templates since P2 of
  SUBAGENT_ROUTING_DESIGN.md).

The section headings that join the prompt's parts ("Environment:", "Tools available:", "Instructions from …") are
code as well, because they frame generated data.

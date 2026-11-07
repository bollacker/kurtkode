# Official and vendor-published Agent Skills collections for software development

Research date: 2026-10-25. All repo stats (stars, commits) are as shown on GitHub pages fetched that day. Taxonomy numbers refer to ~/git/kurtkode/skilllib/TAXONOMY_v0.md. Where a skill's mapping is inferred only from its name (SKILL.md not read), it is marked "(name only)".

## Q1. What is the Agent Skills specification (agentskills.io)?

### Takeaway
Agent Skills is a deliberately small open format: a folder with a `SKILL.md` whose YAML frontmatter needs only `name` (≤64 chars, lowercase-hyphen, equals directory name) and `description` (≤1024 chars), plus optional `license`, `compatibility`, `metadata`, and experimental `allowed-tools`. Loading is three-stage progressive disclosure (~100-token metadata, <5000-token body, on-demand resources), with a recommended body under 500 lines and `scripts/`, `references/`, `assets/` as conventional subfolders. Anthropic created it and published it as an open standard on 2025-12-18.

### Cited Findings
- Directory layout: `skill-name/SKILL.md` (required), optional `scripts/` (executable code), `references/` (docs such as `REFERENCE.md`, `FORMS.md`, domain files), `assets/` (templates, images, data files), and any other files — [agentskills.io spec](https://agentskills.io/specification)
- Required frontmatter: `name`, 1–64 chars, only `a-z`, `0-9`, `-`, no leading or trailing hyphen, no `--`, must match the parent directory name; `description`, 1–1024 chars, should say what the skill does and when to use it, with task keywords — [spec](https://agentskills.io/specification)
- Optional frontmatter: `license` (short name or bundled file reference); `compatibility` (1–500 chars, environment requirements, "most skills do not need" it); `metadata` (string→string map, use unique key names); `allowed-tools` (space-separated pre-approved tools, e.g. `Bash(git:*) Bash(jq:*) Read`, "Experimental", support varies) — [spec](https://agentskills.io/specification)
- Body: Markdown with "no format restrictions"; recommended sections are step-by-step instructions, input/output examples, edge cases; the whole file loads on activation, so split long content — [spec](https://agentskills.io/specification)
- Progressive disclosure: (1) metadata ~100 tokens loaded at startup for all skills; (2) instructions, <5000 tokens recommended, loaded on activation; (3) resources loaded only when required. "Keep your main SKILL.md under 500 lines." — [spec](https://agentskills.io/specification)
- File references: relative paths from the skill root; "Keep file references one level deep from SKILL.md"; keep reference files focused since smaller files use less context — [spec](https://agentskills.io/specification)
- Validation: `skills-ref validate ./my-skill` from the `skills-ref` library checks frontmatter and naming — [spec](https://agentskills.io/specification)
- Spec repo agentskills/agentskills: code Apache-2.0, docs CC-BY-4.0, ~26.6k stars, 145 commits, folders `docs/` and `skills-ref/`, no releases or changelog; no named governance body — [GitHub agentskills/agentskills](https://github.com/agentskills/agentskills)
- "Originally developed by Anthropic, released as an open standard, and has been adopted by a growing number of agent products"; discussion on GitHub and Discord — [agentskills.io](https://agentskills.io)
- Open-standard release dated December 18, 2025 (Unite.ai) / December 19 (gihyo.jp, likely timezone); skills first shipped as a developer feature in October 2025 — [Unite.ai](https://www.unite.ai/anthropic-opens-agent-skills-standard-continuing-its-pattern-of-building-industry-infrastructure); [gihyo.jp](https://gihyo.jp/article/2025/12/agent-skills-to-open-standard); [The Decoder](https://the-decoder.com/anthropic-publishes-agent-skills-as-an-open-standard-for-ai-platforms/)
- Simon Willison called the spec "deliciously tiny" and noted parts (e.g. `metadata`) are under-specified — [simonwillison.net](https://simonwillison.net/2025/Dec/19/agent-skills) (as summarized in search results)
- Claude Code's own extension frontmatter, beyond the spec: `when_to_use`, `argument-hint`, `arguments`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, `disallowed-tools`, `model`, `effort`, `context: fork`, `agent`, `background`, `hooks`, `paths`, `shell`. Outside Claude Code (claude.ai uploads, Skills API) only the six spec fields are allowed; other keys are a hard error — [Claude Code skills docs](https://code.claude.com/docs/en/skills)
- Claude Code budgets: `description`+`when_to_use` truncated at 1,536 chars in the listing; body under 500 lines; after compaction each invoked skill is re-attached with its first 5,000 tokens within a combined 25,000-token budget — [Claude Code skills docs](https://code.claude.com/docs/en/skills)
- Codex budget: the initial skills list defaults to 2% of the context window (8,000 chars if unknown), and Codex may shorten descriptions or omit skills when there are many; `skills.max_context_tokens` raises it to at most 10,000 tokens — [OpenAI build-skills docs](https://learn.chatgpt.com/docs/build-skills)
- Cursor extension fields: `paths` (globs; legacy `globs` accepted), `disable-model-invocation`, `icon`, `color`, `metadata` — [Cursor skills docs](https://cursor.com/docs/context/skills)
- opencode accepts only `name`, `description`, `license`, `compatibility`, `metadata` and ignores unknown fields; name regex `^[a-z0-9]+(-[a-z0-9]+)*$` — [opencode skills docs](https://opencode.ai/docs/skills/)
- Codex extension: optional `agents/openai.yaml` for UI metadata (display name, icon, brand color, default prompt), `policy.allow_implicit_invocation` (default true), and tool dependencies such as MCP servers — [OpenAI build-skills docs](https://learn.chatgpt.com/docs/build-skills)

### Inferences
- The portable core is the six spec fields. Invocation control (`disable-model-invocation`, `paths`, `user-invocable`, `context: fork`) is harness-specific and not portable, though Claude Code and Cursor share `disable-model-invocation` and `paths`. A library meant for kurtkode, Claude Code, opencode and Codex should keep to the spec fields and treat the rest as optional hints, since opencode ignores them and the claude.ai/API surface rejects them.
- The practical description budget is set by harnesses, not the spec: 1024 chars (spec) vs 1,536 (Claude Code listing) vs a shared ~8,000-char pool (Codex). Short, front-loaded descriptions matter most when many skills are installed.

### Gaps
- The agentskills.io Client Showcase page renders client-side; the fetched text had no list, so the official list of supporting clients could not be read.
- No formal versioning, changelog, or governance for the spec was found.

## Q2. Which agent harnesses load Agent Skills, and from where?

### Takeaway
Effectively every major coding agent now loads SKILL.md folders, and most read the vendor-neutral `.agents/skills/` path as well as `.claude/skills/` for compatibility. Claude Code, Codex, Gemini CLI, Cursor, GitHub Copilot, opencode and Amp all have first-party docs for it; Goose support is reported but only through secondary sources here.

### Cited Findings
- **Claude Code**: enterprise (managed settings), personal `~/.claude/skills/`, project `.claude/skills/`, nested `<subdir>/.claude/skills/`, `--add-dir` directories, plugin `<plugin>/skills/` (namespaced `/plugin:skill`), and claude.ai account skills. Precedence: enterprise > personal > project. Custom commands (`.claude/commands/x.md`) and skills are merged; both create `/x`. Bundled skills include `/code-review`, `/batch`, `/debug`, `/loop`, `/claude-api`, `/run`, `/verify`, `/skill-doctor`; `disableBundledSkills` turns them off — [Claude Code skills docs](https://code.claude.com/docs/en/skills)
- **Claude apps / API**: skills are available on paid Claude.ai plans; pre-built skills and custom uploads are usable via the Claude API — [anthropics/skills README](https://github.com/anthropics/skills). Skills are included in Max, Pro, Team and Enterprise at no extra cost; Team/Enterprise admins got central skill management at the December 2025 launch — [VentureBeat](https://venturebeat.com/ai/anthropic-launches-enterprise-agent-skills-and-opens-the-standard) (as summarized in search results)
- **OpenAI Codex (CLI, IDE, ChatGPT app)**: REPO `.agents/skills` in every directory from cwd up to the repo root; USER `$HOME/.agents/skills`; ADMIN `/etc/codex/skills`; SYSTEM bundled. Follows symlinks; same-name skills are not merged. Explicit invocation with `/skills` or `$name` (Codex), `@` (ChatGPT); implicit when the description matches. Built-ins: `$skill-creator`, `$skill-installer`, plan skills. Plugins bundle skills + MCP connectors for distribution — [OpenAI build-skills docs](https://learn.chatgpt.com/docs/build-skills)
- **Gemini CLI**: tiers built-in < extension < user (`~/.gemini/skills/` or `~/.agents/skills/`) < workspace (`.gemini/skills/` or `.agents/skills/`); `.agents/skills/` beats `.gemini/skills/` within a tier. Model calls an `activate_skill` tool, which shows a consent prompt; commands `/skills list|link|enable|disable|reload`, `gemini skills install <git-url>`. GEMINI.md is persistent context; skills are on-demand. Page updated 2026-04-30; banner says Gemini CLI was replaced by Antigravity CLI for unpaid/Google One users on 2026-06-18 — [Gemini CLI skills docs](https://geminicli.com/docs/cli/skills/)
- **Cursor**: project `.agents/skills/`, `.cursor/skills/`; user `~/.agents/skills/`, `~/.cursor/skills/`; also reads `.claude/skills/`, `.codex/skills/` and the home equivalents. Recursive scan; nested skills apply to their folder. `/` attaches a skill to one message; a skill can be a session-long Custom Mode. `/migrate-to-skills` (in 2.4) converts dynamic rules (no `alwaysApply`, no `globs`) and slash commands into skills; always-apply and glob rules stay as `.cursor/rules` — [Cursor skills docs](https://cursor.com/docs/context/skills)
- **GitHub Copilot**: Copilot app, Copilot CLI, Copilot cloud agent, Copilot code review on github.com, agent mode in VS Code, Visual Studio, JetBrains. Project skills in `.github/skills`, `.claude/skills`, or `.agents/skills`; personal in `~/.copilot/skills` or `~/.agents/skills`; locations vary by surface. `gh skill` in GitHub CLI finds/installs skills from repos — [GitHub Docs: About agent skills](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)
- **opencode**: `.opencode/skills/`, `.claude/skills/`, `.agents/skills/` walking up to the git worktree root; global `~/.config/opencode/skills/`, `~/.claude/skills/`, `~/.agents/skills/`. Native `skill` tool lists `<available_skills>`; per-skill `allow`/`deny`/`ask` permissions with wildcards in `opencode.json` — [opencode skills docs](https://opencode.ai/docs/skills/)
- **Amp**: project `.agents/skills/`; user `~/.config/agents/skills/` or `~/.agents/skills/`; also `.claude/skills/`, `~/.claude/skills/` (can be disabled). Skills may ship MCP servers via `mcp.json`. Built-in `building-skills` skill; `amp skill add <source>` — [Amp manual](https://ampcode.com/manual/agent-skills.md); [Amp docs](https://ampcode.com/docs/customize/skills) (as summarized in search results)
- **Goose**: reported to load SKILL.md from `~/.config/goose/skills/`, `.goose/skills/` and `.agents/skills/` via a built-in skills extension — [rulesync issue #1115](https://github.com/dyoshikawa/rulesync/issues/1115); [DEV Community](https://dev.to/nickytonline/advent-of-ai-2025-day-14-agent-skills-4d48). Sources disagree on paths; official Goose docs were not found.
- **Antigravity CLI** installs Google skill plugins with `agy plugin install` — [google/skills](https://github.com/google/skills)
- Cross-agent installer: `npx skills add <repo>` (the `skills` CLI) is the install path in the Vercel, Supabase, Google, Microsoft and Cloudflare READMEs — [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills); [supabase/agent-skills](https://github.com/supabase/agent-skills); [google/skills](https://github.com/google/skills); [microsoft/skills](https://github.com/microsoft/skills); [cloudflare/skills](https://github.com/cloudflare/skills). Cloudflare's README also names Pi as a supported agent — [cloudflare/skills](https://github.com/cloudflare/skills)
- Early adopters named at the December 2025 opening: Microsoft, OpenAI, Atlassian, Figma, Cursor, GitHub — [Unite.ai](https://www.unite.ai/anthropic-opens-agent-skills-standard-continuing-its-pattern-of-building-industry-infrastructure)

### Inferences
- `.agents/skills/` (project) and `~/.agents/skills/` (user) are the closest thing to a universal location: Codex, Gemini CLI, Cursor, Copilot, opencode and Amp all read them. Claude Code's docs list only `.claude/skills/`, so a library aimed at both needs either a symlink or install into both paths.
- Plugin/marketplace packaging is converging too: Claude Code, Codex, Copilot CLI and Antigravity each have a plugin format that wraps skills plus MCP config, and several vendor repos ship manifests for more than one.

### Gaps
- Claude Code's docs page was read only for its first 100k characters; whether Claude Code reads `.agents/skills/` was not confirmed (not in the location table read).
- No primary Goose documentation was read; no Windsurf, Cline, Kiro, Zed or JetBrains Junie docs were checked.

## Q3. What does Anthropic's public skills repository (anthropics/skills) contain?

### Takeaway
anthropics/skills holds 19 skills plus the spec copy and a template; only about five are software-development skills (frontend-design, webapp-testing, mcp-builder, skill-creator, claude-api, and arguably web-artifacts-builder). It is very popular (183.6k stars) but small and example-oriented, and recent activity is almost all updates to the claude-api skill.

### Cited Findings
- Repo stats: 183.6k stars, 21.7k forks, 60 commits on main; folders `.claude-plugin`, `skills`, `spec`, `template`; categories Creative & Design, Development & Technical, Enterprise & Communication, Document Skills — [anthropics/skills](https://github.com/anthropics/skills)
- License: many skills Apache 2.0; docx/pdf/pptx/xlsx are "source-available, not open source"; skills say "Complete terms in LICENSE.txt" — [anthropics/skills](https://github.com/anthropics/skills); [frontend-design SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/frontend-design/SKILL.md)
- Install as Claude Code plugins: `/plugin marketplace add anthropics/skills`, then `document-skills@anthropic-agent-skills` or `example-skills@anthropic-agent-skills`. README disclaims the skills as demonstration/educational — [anthropics/skills](https://github.com/anthropics/skills)
- Full skill list (19): academy-guide, algorithmic-art, brand-guidelines, canvas-design, claude-api, discernment-nudge, doc-coauthoring, docx, frontend-design, internal-comms, mcp-builder, pdf, pptx, skill-creator, slack-gif-creator, theme-factory, web-artifacts-builder, webapp-testing, xlsx — [GitHub API listing](https://api.github.com/repos/anthropics/skills/contents/skills)
- Latest commits: 2026-10-09 (two), 2026-10-05, 2026-09-29, 2026-09-24, all "Update claude-api skill: …" (e.g. Opus 5.5 default, Managed Agents, build-eval and hillclimb guides) — [GitHub API commits](https://api.github.com/repos/anthropics/skills/commits?per_page=5)

Per-skill notes (dev relevance; taxonomy mapping):

| Skill | What it is (source) | Dev? | Taxonomy |
|---|---|---|---|
| frontend-design | Design-lead persona; derive palette/type/layout from subject and audience; 1–2 type families; one deliberate motion moment; two-pass process (token plan → build → self-critique, watch CSS specificity); explicit list of AI-design clichés to avoid; UI copy and empty/error-state guidance. ~70 lines, no bundled files mentioned — [SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/frontend-design/SKILL.md) | Yes | 69, 70 |
| webapp-testing | Python Playwright testing of local web apps; ships `scripts/with_server.py` (starts/stops one or more servers) and `examples/` (element_discovery, static_html_automation, console_logging); decision tree static vs dynamic; "reconnaissance-then-action" (wait for networkidle, screenshot/DOM, then act); "run `--help` first, treat scripts as black boxes" to save context — [SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/webapp-testing/SKILL.md) | Yes | 23, 69, 31 |
| mcp-builder | 4 phases: research/plan (API coverage vs workflow tools, naming, errors, TS + Streamable HTTP recommended) → implement (Zod/Pydantic schemas, tool annotations like `readOnlyHint`) → review/test with MCP Inspector → evaluations (10 read-only, verifiable `qa_pair` XML questions). References: `reference/mcp_best_practices.md`, `node_mcp_server.md`, `python_mcp_server.md`, `evaluation.md` — [SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/mcp-builder/SKILL.md) | Yes | 9, 18, 23 |
| skill-creator | Draft SKILL.md + test prompts; run each prompt with and without the skill (or vs previous version) in one batch; grader / comparator (blind A/B) / analyzer subagents; aggregation into a benchmark; HTML viewer for user feedback; iteration folders; description optimization with ~20 should/shouldn't-trigger queries and a train/test split; variants for Claude.ai and Cowork; `.skill` packaging. Bundles `scripts/`, `agents/`, `eval-viewer/`, `references/schemas.md`, `assets/eval_review.html` — [SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/skill-creator/SKILL.md) | Yes (meta) | 76 |
| claude-api | Building on the Claude API; actively maintained (model defaults, Managed Agents, workflow quickstarts, build-eval/hillclimb guides) — [commits](https://api.github.com/repos/anthropics/skills/commits?per_page=5) | Yes | 18, 46 |
| web-artifacts-builder | Not read | Probably (name only) | 18, 69 (name only) |
| doc-coauthoring | Not read | Possibly (docs) | 8, 60 (name only) |
| discernment-nudge | Adds 2–3 follow-up "worth a second look" questions after consequential answers; explicitly skipped for code the user will run — [SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/discernment-nudge/SKILL.md) | No | — |
| academy-guide | Recommends at most two matching Claude Academy courses after answering Claude how-to questions; treats fetched catalog JSON as data — [SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/academy-guide/SKILL.md) | No | — |
| algorithmic-art, brand-guidelines, canvas-design, internal-comms, slack-gif-creator, theme-factory, docx, pdf, pptx, xlsx | Creative, enterprise-comms and document skills per README categories — [anthropics/skills](https://github.com/anthropics/skills) | No | — |

### Inferences
- The repo is better read as a set of worked examples of skill structure than as a dev skill library. Useful structural patterns: webapp-testing's "scripts as black boxes, `--help` first" rule; mcp-builder's phase structure with one reference file per language; skill-creator's with/without-skill eval loop, which is the closest thing to a published method for testing skills (taxonomy 76).
- It has no process skills for debugging, TDD, code review, git or planning. Anthropic ships those as Claude Code plugins/bundled skills instead (Q4).

### Gaps
- SKILL.md for web-artifacts-builder, doc-coauthoring and claude-api were not read; their sizes and structure are unverified.
- The fetched README did not show a last-commit date; the commit API supplied dates.

## Q4. Anthropic's Claude Code plugin marketplaces: which dev plugins and skills?

### Takeaway
claude-plugins-official (Apache-2.0, 44.4k stars, 4,632 commits) lists about 315 plugins. Roughly 39 are Anthropic-maintained (`./plugins`), about 14 are partner plugins vendored in `./external_plugins`, and the rest point to vendor or community repos. The Anthropic dev plugins cover code review, feature development, commits/PRs, security, simplification, legacy modernization, LSP code intelligence for 13 languages, and plugin/skill/MCP authoring. Many are built from commands, subagents and hooks rather than SKILL.md alone.

### Cited Findings
- Repo: Apache-2.0 (each plugin may carry its own LICENSE), 44.4k stars, 4.7k forks, 4,632 commits, 1.1k open issues; `/plugins` = Anthropic internal, `/external_plugins` = partners/community, manifest `.claude-plugin/marketplace.json` — [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official)
- Marketplace manifest lists ~315 entries (166 in the first half + 149 in the second as read; categories include development, productivity, security, database, monitoring, deployment, design, testing, learning) — [marketplace.json](https://raw.githubusercontent.com/anthropics/claude-plugins-official/main/.claude-plugin/marketplace.json)
- Anthropic-local dev plugins (marketplace descriptions) — [marketplace.json](https://raw.githubusercontent.com/anthropics/claude-plugins-official/main/.claude-plugin/marketplace.json):
  - code-review: "Multi-agent pull request review" → 28
  - pr-review-toolkit: PR review agents for tests, errors, types → 28, 22, 15
  - feature-dev: feature workflow with specialist agents → 1, 11, 12, 28
  - commit-commands: git commit, push, PR commands → 50, 52
  - code-simplifier: simplifies recently modified code → 14
  - code-modernization: guided legacy codebase modernization → 64, 46, 65
  - security-guidance: security review of Claude-generated code → 38
  - claude-security: deep vulnerability scanning with verified patches → 38, 40
  - frontend-design → 69, 70
  - LSP plugins: clangd, csharp, gopls, jdtls (Java), kotlin, lua, php, pyright, ruby, rust-analyzer, swift, typescript (+ liquid-lsp external) → infrastructure for 1, 2, 4, 27
  - agent-sdk-dev (Claude Agent SDK dev kit) → 18; mcp-server-dev (design/build MCP servers) → 9, 18; mcp-tunnels
  - plugin-dev, skill-creator → 76; hookify (custom hooks from rules) → N (meta); claude-md-management (audit/maintain CLAUDE.md) → 1, 74; claude-code-setup (recommends hooks/skills/MCP/agents) → 72
  - ralph-loop (iterative self-referential loops) → 12; project-artifact (shareable living status page) → 77; playground (single-file HTML explorers)
  - explanatory-output-style, learning-output-style → 5 (learning)
  - Non-dev local: math-olympiad, math-proof, receipts, session-report, cwc-makers
- Contents of the older plugin set in anthropics/claude-code `plugins/` (13): code-review = `/code-review` + 5 parallel Sonnet agents (CLAUDE.md compliance, bugs, history, PR history, code comments) with confidence scoring; feature-dev = 7-phase `/feature-dev` with code-explorer, code-architect, code-reviewer agents; commit-commands = `/commit`, `/commit-push-pr`, `/clean_gone`; pr-review-toolkit = `/review-pr` with comment-analyzer, pr-test-analyzer, silent-failure-hunter, type-design-analyzer, code-reviewer, code-simplifier; plugin-dev = 7 skills + agent-creator, plugin-validator, skill-reviewer; security-guidance = PreToolUse hook watching 9 patterns (command injection, XSS, eval, pickle, os.system…); hookify includes a `writing-rules` skill; ralph-wiggum = Stop hook loop; claude-opus-4-5-migration skill — [anthropics/claude-code plugins](https://github.com/anthropics/claude-code/tree/main/plugins)
- Claude Code itself bundles `/code-review`, `/batch`, `/debug`, `/loop`, `/claude-api`, `/run`, `/verify`, `/run-skill-generator`, `/skill-doctor` as prompt-based skills — [Claude Code skills docs](https://code.claude.com/docs/en/skills)
- Third-party process-skill collections in the official marketplace: superpowers ("Brainstorming, debugging, and red/green TDD"), mattpocock-skills ("grilling, TDD, specs, code review, domain modeling") → 7, 13, 31, 28, 6, 10 — [marketplace.json](https://raw.githubusercontent.com/anthropics/claude-plugins-official/main/.claude-plugin/marketplace.json)
- Notable vendor dev entries (external repos): coderabbit, greptile, qodo (review, 28); semgrep, sonarqube, sonatype-guide, aikido, 42crunch, stackhawk, nightvision (38, 40); sentry, datadog, honeycomb, grafana, newrelic (34, 57); pagerduty, incident-io, rootly (59); terraform (58); context7, microsoft-docs, sourcegraph, serena, lumen (doc lookup, code search, semantic navigation → 1, 2, 4); playwright, chrome-devtools-mcp (23, 69); mergify (51, 52); buildkite, teamcity-cli (54); codspeed (35, 67); prisma, neon, planetscale, supabase (43, 10) — [marketplace.json](https://raw.githubusercontent.com/anthropics/claude-plugins-official/main/.claude-plugin/marketplace.json)

### Inferences
- Anthropic's dev coverage sits mostly in plugins (commands + subagents + hooks + MCP/LSP), not standalone SKILL.md files. Its review and feature workflows depend on parallel subagents, so they won't port directly to harnesses without subagents.
- The anthropics/claude-code `plugins/` README is an older snapshot (it names claude-opus-4-5-migration and ralph-wiggum, whereas the official marketplace lists ralph-loop), so take current plugin contents from claude-plugins-official.

### Gaps
- Per-plugin last-commit dates and individual SKILL.md contents for code-review, feature-dev, claude-security and code-modernization were not read.
- My count of Anthropic-local entries (~39) comes from tallying the two marketplace halves; the fetch tool's own tally for the second half (14) differed from mine (18).

## Q5. What do OpenAI, Google, GitHub, Microsoft, Cursor and other vendors publish for dev tasks?

### Takeaway
Every major platform vendor now publishes SKILL.md collections, but most are product-integration skills (how to use *our* cloud, SDK or API) rather than general software-engineering process skills. The general-process exceptions are OpenAI's curated set (gh-fix-ci, gh-address-comments, security threat modeling, CLI creation, Playwright), Vercel's React and web-design rule packs, and parts of Microsoft's and GitHub's community collections.

### Cited Findings

**OpenAI**
- openai/skills ("Skills Catalog for Codex"): 28.3k stars, 114 commits; README now says deprecated and points to openai/plugins; tiers `.system` (auto-installed with Codex), `.curated` (installed by name with `$skill-installer`), `.experimental` (by folder or URL, e.g. create-plan); per-skill `LICENSE.txt` — [openai/skills](https://github.com/openai/skills)
- `.system` (5): imagegen, openai-docs, plugin-creator, skill-creator, skill-installer — [API listing](https://api.github.com/repos/openai/skills/contents/skills/.system)
- `.curated` (39): aspnet-core, chatgpt-apps, cli-creator, cloudflare-deploy, define-goal, seven figma-* skills plus figma, gh-address-comments, gh-fix-ci, hatch-pet, jupyter-notebook, linear, migrate-to-codex, netlify-deploy, four notion-* skills, openai-docs, pdf, playwright-interactive, playwright, render-deploy, screenshot, security-best-practices, security-ownership-map, security-threat-model, sentry, speech, transcribe, vercel-deploy, winui-app, yeet — [API listing](https://api.github.com/repos/openai/skills/contents/skills/.curated)
- gh-fix-ci (read): debug failing GitHub Actions PR checks with `gh`; 8 steps (verify auth → resolve PR → inspect checks with bundled `scripts/inspect_pr_checks.py` [`--repo --pr --json --max-lines --context`, non-zero exit while failing] → label external checks → summarize with log snippet → plan, using `create-plan` if available → implement only after explicit approval → rerun checks). ~60 lines — [SKILL.md](https://raw.githubusercontent.com/openai/skills/main/skills/.curated/gh-fix-ci/SKILL.md) → 54, 24
- Name-only mapping of the other dev skills: gh-address-comments → 29; security-best-practices → 38; security-threat-model → 41; security-ownership-map → 38/3; cli-creator → 19; playwright, playwright-interactive, screenshot → 23, 69; sentry → 34, 57; cloudflare/netlify/render/vercel-deploy → 56; aspnet-core, winui-app, chatgpt-apps, openai-docs → 18; define-goal, create-plan (experimental) → 6, 11; notion-spec-to-implementation → 11, 12; migrate-to-codex → 76; jupyter-notebook → 45 (name only) — [API listing](https://api.github.com/repos/openai/skills/contents/skills/.curated)
- openai/plugins: "a curated collection of Codex plugin examples"; each plugin has `.codex-plugin/plugin.json` and optional `skills/`, `.mcp.json`, `.app.json`, `agents/`, `commands/`, `hooks.json`; marketplace at `.agents/plugins/marketplace.json`; highlighted dev plugins build-ios-apps (SwiftUI implementation, refactors, performance, debugging), build-macos-apps, build-web-apps, expo; 7.6k stars, 308 commits — [openai/plugins](https://github.com/openai/plugins) → 17, 18, 35, 31

**Google**
- google/skills ("Agent Skills for Google products and technologies"): Apache-2.0, 21.6k stars, 486 commits, ~175 skills in `skills/{cloud,developers,identity,ads,analytics}` plus 7 externally hosted collections (ADK, Android, Dart, Firestore, Flutter, Google Maps Platform, advanced GCS). Install with `npx skills add google/skills`; plugin marketplaces for Claude Code, Codex and Antigravity CLI — [google/skills](https://github.com/google/skills)
- Launched at Cloud Next 2026 with 13 skills (AlloyDB, BigQuery, Cloud Run, Cloud SQL, Firebase, Gemini API, GKE + Well-Architected Security/Reliability/Cost) — [Google Cloud blog](https://cloud.google.com/blog/topics/developers-practitioners/level-up-your-agents-announcing-googles-official-skills-repository/) (date April 22, 2026 per search summary; a third-party article gives April 28)
- Dev-relevant categories: Developer tools (Cloud Build Basics, gcloud CLI, Developer Knowledge…) → 54, 49; ~28 GKE skills incl. Manifest Generation, Workload Troubleshooting, Upgrades → 55, 56, 58; BigQuery Optimization/Troubleshooting, Cloud SQL, Spanner, Managed Airflow DAG authoring/troubleshooting → 20, 44, 45; Cloud Logging/Monitoring/Trace query generation → 57; Well-Architected (6 pillars) → 41, 56, 57; Security (IAM troubleshooter, SecOps detection engineering, GKE workload security) → 38, 42; "Migrate Legacy Codebases to Safe Rust" → 46, 64; "dbt Snowflake to BigQuery Translator", "BQMS SQL Translator" → 20, 46 — [google/skills](https://github.com/google/skills)

**GitHub**
- github/awesome-copilot: MIT, 40.4k stars, 2,676 commits; folders `instructions/`, `skills/`, `agents/` (MCP-integrated custom agents), `plugins/` (bundles of agents + skills), `hooks/`, `workflows/`, `cookbook/`; install with `copilot plugin install <name>@awesome-copilot`; warns contents are third-party and should be inspected — [github/awesome-copilot](https://github.com/github/awesome-copilot)
- Copilot loads skills from `.github/skills`, `.claude/skills`, `.agents/skills`, `~/.copilot/skills`, `~/.agents/skills`; `gh skill` installs from repos — [GitHub Docs](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)

**Microsoft**
- microsoft/skills: MIT, ~3.1k stars, 796 commits, "work in progress"; "Skills, MCP servers, Custom Agents, Agents.md for SDKs to ground Coding Agents"; ~174–175 skills: Core (11), Foundry (11), Azure SDK per language — Python 39 (`-py`), .NET 28, TypeScript 25, Java 25, Rust 7; plugins deep-wiki and azure; agent personas; reference MCP configs (microsoft-docs, context7, deepwiki, github, playwright, terraform, eslint); test harness on the Copilot SDK with 1,169 scenarios over 129 skills and a "Ralph Loop" for iterative improvement. Dev-generic skills include mcp-builder, skill-creator, github-issue-creator, debugview, frontend-design-review — [microsoft/skills](https://github.com/microsoft/skills) → 17, 18, 9, 76, 34, 69

**Vercel**
- vercel-labs/agent-skills: MIT, 33.0k stars, 275 commits; `npx skills add vercel-labs/agent-skills`. Skills: react-best-practices (40+ rules ranked by impact: waterfalls, bundle size, data fetching, re-renders), web-design-guidelines (100+ rules: focus, forms, animation, typography, dark mode, i18n), writing-guidelines (80+ rules), react-native-guidelines (16 rules), react-view-transitions, composition-patterns (compound components vs boolean props), vercel-optimize (metrics-led cost/perf audit), vercel-deploy-claimable — [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills) → 17, 18, 35, 68, 69, 70, 60, 56

**Cloudflare**
- cloudflare/skills: Apache-2.0, 3.2k stars, 293 commits; 19 skills incl. wrangler, workers-best-practices, workers-profiling, durable-objects, agents-sdk, sandbox-*, cf-cli, web-perf (Core Web Vitals audit), nextjs-on-cloudflare, turnstile-spin, cloudflare-one(-migrations); installs via Codex and Claude Code marketplaces, Cursor, VS Code/Copilot, `npx skills add` — [cloudflare/skills](https://github.com/cloudflare/skills) → 18, 56, 35, 42

**Supabase**
- supabase/agent-skills: MIT, ~2.9k stars, 96 commits; two skills: supabase (Database, Auth, Edge Functions, Realtime, Storage, Vectors, Cron, Queues, SSR, CLI/MCP) and supabase-postgres-best-practices (8 impact-ranked categories in `references/`); Release Please semver — [supabase/agent-skills](https://github.com/supabase/agent-skills) → 18, 20, 43, 44, 10

**Stripe**
- stripe/ai ships skills including stripe-best-practices (integration architecture guidance) and upgrade-stripe (moving to a newer date-based API version, per-language guidance); recommended install is the Stripe plugin (auto-configures Stripe MCP and keeps skills current), e.g. `claude plugin install stripe@claude-plugins-official`; manual `npx skills add https://docs.stripe.com` — [Stripe docs: Skills](https://docs.stripe.com/skills.md); [stripe/ai README](https://cdn.jsdelivr.net/gh/stripe/ai@main/README.md) (as summarized in search results) → 18, 46

**Cursor**
- Cursor does not appear to publish a first-party general skill library in the sources read. Its close equivalent is `.cursor/rules` (always-apply and glob-scoped rules), now with `/migrate-to-skills` converting dynamic rules and commands into SKILL.md skills — [Cursor skills docs](https://cursor.com/docs/context/skills)

### Inferences
- Coverage pattern against the taxonomy: vendor collections densely cover K-type framework/platform packs (17, 18), deployment (56), databases (20, 43, 44), observability (57) and security integrations (38, 40). They barely cover P-type process skills such as debugging (31–32), refactoring (14), TDD (13), test-writing quality (22), requirements (6), planning (11), documentation (60–63) and agent practice (71–77). The process items come mainly from Anthropic plugins, OpenAI curated skills, and community collections (superpowers, mattpocock-skills).
- The "rule pack" style (Vercel, Supabase Postgres, ClickHouse "28 rules") is a recognizable pattern: a short SKILL.md index plus impact-ranked rules in `references/`. It suits K-type taxonomy items.
- Testing infrastructure for skills is rare. Only Anthropic's skill-creator (with/without baselines, trigger-description optimization) and Microsoft's Copilot-SDK harness (acceptance criteria per skill) publish one.

### Gaps
- awesome-copilot's skill count and individual dev skills were not visible on the repo page; the API listing was not fetched.
- OpenAI curated SKILL.md bodies other than gh-fix-ci were not read; mappings for those are name-based.
- No first-party collections were checked for JetBrains, AWS (beyond marketplace entries aws-core, aws-serverless, aws-transform), Atlassian, HashiCorp or Expo repos directly.
- Last-commit dates were unavailable for most repos (GitHub pages showed only "© 2026"); stars and commit counts are the activity signal recorded.

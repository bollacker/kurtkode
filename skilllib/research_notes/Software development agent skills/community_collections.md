# Community (non-vendor) Agent Skills collections for software development

Snapshot date: 2026-10-25. Repository metadata (stars, forks, license, created, last push) comes from the GitHub REST API (`https://api.github.com/repos/<owner>/<repo>`) on that date. Skill lists come from the GitHub git-tree API (`/git/trees/HEAD?recursive=1`, every path ending in `SKILL.md`). One-line purposes come from the `description:` frontmatter of each raw SKILL.md, read over raw.githubusercontent.com. Nothing was cloned.

Method caveats that apply throughout:
- Star counts in late 2026 are very large. Several repos are above 100k, and an unrelated skill repo, morluto/rea, has 380k. One secondary source reports that superpowers went from about 93K stars in March 2026 to about 298K in October 2026 ([kunalganglani.com](https://www.kunalganglani.com/blog/superpowers-agentic-skills-framework); [mcp.directory](https://mcp.directory/blog/superpowers-skill-worth-it-2026)). I could not check whether stars are inflated, so use them for relative ranking only. Install counts from skills.sh are a separate popularity signal, and they rank collections differently from stars.
- "Vendor" means the makers of models or agent harnesses (Anthropic, OpenAI, Vercel, GitHub/Microsoft). Repos run by those vendors are noted only for reference. github/awesome-copilot is hosted by GitHub but takes community contributions, so it is included and flagged.
- The coverage counts in the last section come from matching skill *names* across 4,713 (repo, skill-name) pairs from 14 collections, then correcting by hand from descriptions I read. A name match is a proxy, not a reading of every skill body.

## Which community collections are most used or cited?

### Takeaway
The most-used community dev-skill collections fall into three tiers. First are process "methodology" packs: obra/superpowers, mattpocock/skills, addyosmani/agent-skills, garrytan/gstack and affaan-m/ECC. Second are large knowledge or agent marketplaces: wshobson/agents, VoltAgent's subagents, Jeffallan, alirezarezvani and sickn33. Third is one specialist pack, trailofbits/skills, for security, testing and fuzzing. Popularity depends on the measure. superpowers leads in stars and is the pick most often cited in roundups. mattpocock/skills leads install counts on skills.sh, the main cross-agent directory.

### Cited Findings

**Process / methodology packs (small, opinionated, many installs)**
- obra/superpowers (Jesse Vincent, Prime Radiant): MIT, 304,727 stars, 27,144 forks, created 2025-10-09, last push 2026-10-23, 15 skills. — [GitHub API](https://api.github.com/repos/obra/superpowers); [repo](https://github.com/obra/superpowers)
  - The README calls it a "software development methodology" made of auto-triggering skills. The workflow is brainstorm → git worktree → write plan → execute (subagent-driven or inline) → TDD → code review between tasks → finish branch. It supports 16 harnesses, including Claude Code, Codex CLI/App, Cursor, OpenCode, Gemini CLI, Copilot CLI and Pi. Contribution guidelines say new skills are "generally not accepted". — [repo README](https://github.com/obra/superpowers)
  - It is the community entry hesreallyhim/awesome-claude-code lists under "Skills": "a strong bundle of core competencies for software engineering". travisvn/awesome-claude-skills lists it first under "Collections & Libraries". — [hesreallyhim README](https://github.com/hesreallyhim/awesome-claude-code); [travisvn README](https://github.com/travisvn/awesome-claude-skills)
  - Blog roundups name superpowers as the most common first pick for plan-first TDD. Some users turn it off for quick spikes because the ceremony is overhead. — [ssojet.com](https://ssojet.com/blog/best-claude-code-skills); [dupple.com](https://dupple.com/learn/best-claude-code-skills-2026)
  - One reported criticism is that it is "bloated", not wrong. Its speed and quality claims come mainly from its builders. v5.1.0 removed slash commands and the named reviewer agent. — [mcp.directory](https://mcp.directory/blog/superpowers-skill-worth-it-2026); [rywalker.com](https://rywalker.com/research/superpowers-skills-framework)
  - The older community-editable repo obra/superpowers-skills is stale: 755 stars, last push 2025-10-14. obra/superpowers-lab holds experimental skills. — [GitHub API](https://api.github.com/repos/obra/superpowers-skills); [travisvn README](https://github.com/travisvn/awesome-claude-skills)
- mattpocock/skills: MIT, 302,673 stars, created 2026-02-03, last push 2026-10-22, 38 skills. On the skills.sh all-time leaderboard it holds 13 of the top 30 slots: grill-me 1.4M installs (#2), grill-with-docs 1.2M, improve-codebase-architecture 1.2M, tdd 1.1M, setup-matt-pocock-skills 1.1M, handoff 1.0M, triage 993K, prototype 990K, grilling 984K, domain-modeling 880K, teach 865K, codebase-design 854K and diagnosing-bugs 838K. — [skills.sh](https://skills.sh); [GitHub API](https://api.github.com/repos/mattpocock/skills)
- addyosmani/agent-skills: MIT, 110,273 stars, created 2026-02-15, last push 2026-10-13, 25 skills ("Production-grade engineering skills for AI coding agents"). — [GitHub API](https://api.github.com/repos/addyosmani/agent-skills)
- garrytan/gstack: MIT, 137,587 stars, created 2026-03-11, last push 2026-10-25. The repo describes itself as "Garry Tan's exact Claude Code setup: 23 opinionated tools that serve as CEO, Designer, Eng Manager, Release Manager, Doc Engineer, and QA". The tree has 70 SKILL.md files, about 60 distinct skills plus test fixtures. — [GitHub API](https://api.github.com/repos/garrytan/gstack)
- affaan-m/ECC (formerly "everything-claude-code"): MIT, 288,271 stars, created 2026-01-18, last push 2026-10-20. The repo describes itself as "agent harness performance optimization system… for Claude Code, Codex, Opencode, Cursor". It has 1,062 SKILL.md files (314 unique names, duplicated per harness), 239 agent files and 355 command files. — [GitHub API](https://api.github.com/repos/affaan-m/ECC)
- EveryInc/compound-engineering-plugin (Every, a media/software company, not a model vendor): MIT, 25,698 stars, created 2025-10-09, last push 2026-10-25. It has about 37 `ce-*` skills and 41 agent files. On claude-plugins.dev its "compound-engineering" entry is listed with 29 agents, 22 commands and 19 skills, and it is the third most-starred entry there. — [GitHub API](https://api.github.com/repos/EveryInc/compound-engineering-plugin); [claude-plugins.dev](https://claude-plugins.dev)
- OthmanAdi/planning-with-files: MIT, 27,631 stars, last push 2026-10-24. The repo describes it as "persistent file-based planning for AI coding agents". — [GitHub topic search](https://api.github.com/search/repositories?q=topic:claude-skills&sort=stars)
- DietrichGebert/ponytail: MIT, 175,667 stars, 6 unique skills (ponytail, -audit, -debt, -gain, -review, -help). The repo says it "makes your AI agent think like the laziest senior dev in the room". — [GitHub topic search](https://api.github.com/search/repositories?q=topic:agent-skills&sort=stars)

**Marketplaces of agents, skills and plugins (large, knowledge-heavy)**
- wshobson/agents: MIT, 41,656 stars, 4,416 forks, created 2025-07-24, last push 2026-10-24. It has 94 plugins (92 local), 202 agents, 185 skills and 105 commands, written once in Claude Code plugin format. Adapters generate versions for Codex CLI, Cursor, OpenCode, Antigravity, Copilot and Pi. Codex copies split oversized skills to fit an 8 KB budget. Agents use model-tier aliases (opus/sonnet/haiku/inherit). — [repo](https://github.com/wshobson/agents); [GitHub API](https://api.github.com/repos/wshobson/agents)
  - On claude-plugins.dev the wshobson "claude-code-workflows" plugins (python-development, backend-development, javascript-typescript and others) each show about 39.3k downloads. That is the highest non-Anthropic download count on that page. — [claude-plugins.dev](https://claude-plugins.dev)
- wshobson/commands: MIT, 2,640 stars, last push 2026-09-30 (slash commands). — [GitHub API](https://api.github.com/repos/wshobson/commands)
- VoltAgent/awesome-claude-code-subagents: MIT, 26,006 stars, last push 2026-10-11. It holds about 173 subagent files in 10 categories: language specialists 31, quality/security 19, business/product 19, infrastructure 17, developer experience 17, specialized domains 17, core development 14, data/AI 14, meta-orchestration 13 and research 12. These are subagents, not SKILL.md. The sister repo VoltAgent/awesome-codex-subagents has 6,399 stars. — [GitHub API](https://api.github.com/repos/VoltAgent/awesome-claude-code-subagents); [tree](https://api.github.com/repos/VoltAgent/awesome-claude-code-subagents/git/trees/HEAD?recursive=1)
- Jeffallan/claude-skills: MIT, 12,043 stars, last push 2026-10-24, 67 role/language "expert" skills ("67 Specialized Skills for Full-Stack Developers"). — [GitHub topic search](https://api.github.com/search/repositories?q=topic:claude-skills&sort=stars)
- alirezarezvani/claude-skills: MIT, 28,669 stars, last push 2026-10-23. It has 465 SKILL.md files (450 unique), 210 agents and 273 commands. Most are business, marketing, compliance or C-suite skills, with an engineering subset. — [GitHub topic search](https://api.github.com/search/repositories?q=topic:claude-code-plugins&sort=stars)
- sickn33/agentic-awesome-skills: MIT, 48,467 stars, last push 2026-10-24. It has 8,589 SKILL.md files and 2,866 unique names, many of them duplicates or copies gathered from other repos. This is the largest single aggregator repo. — [GitHub topic search](https://api.github.com/search/repositories?q=topic:agent-skills&sort=stars)
- github/awesome-copilot (GitHub-hosted, community-contributed): MIT, 40,379 stars, 460 skills and 226 agent files. Many skills wrap Azure/AWS SDKs, plus process items such as breakdown-plan, conventional-commit, create-readme and context-map. — [GitHub topic search](https://api.github.com/search/repositories?q=topic:agent-skills&sort=stars)

**Specialist packs**
- trailofbits/skills: **CC-BY-SA-4.0**, which is unusual (copyleft for docs). 7,791 stars, created 2026-01-14, last push 2026-10-24, 97 skills covering security audit, fuzzing, static analysis, smart contracts and regression hunting. — [GitHub API](https://api.github.com/repos/trailofbits/skills)
- levnikolaevich/claude-code-skills: MIT, 583 stars, created 2025-10-24, last push 2026-10-18. It has 41 numbered `ln-NN-*` skills covering the full SDLC, each with explicit "does not" scope boundaries. — [GitHub API](https://api.github.com/repos/levnikolaevich/claude-code-skills)
- mrgoonie/claudekit-skills: no license detected, 2,228 stars, last push 2026-04-03, 45 skills. Several (systematic-debugging, root-cause-tracing, defense-in-depth, verification-before-completion, when-stuck) share names with the superpowers lineage. — [GitHub API](https://api.github.com/repos/mrgoonie/claudekit-skills)
- K-Dense-AI/claude-scientific-skills now redirects to K-Dense-AI/scientific-agent-skills: MIT, 54,473 stars. It covers science, not software development. — [GitHub topic search](https://api.github.com/search/repositories?q=topic:agent-skills&sort=stars)
- Other popular single-purpose dev skills: Leonxlnx/taste-skill (102,123 stars, UI "taste"), tt-a1i/archify (88,857, codebase → interactive diagram), Egonex-AI/Understand-Anything (88,119, code → knowledge graph), Graphify-Labs/graphify (134,585, codebase → queryable graph), mksglu/context-mode (32,149, context-window optimization) and secondsky/claude-skills (236, Cloudflare/React/Tailwind). — [GitHub topic searches](https://api.github.com/search/repositories?q=topic:claude-code-plugins&sort=stars)

**Awesome lists**
- hesreallyhim/awesome-claude-code: license NOASSERTION, 56,456 stars, last push 2026-10-25, about 512 links. The README is generated from a CSV. It has sections for Agent Orchestration (with SDLC and Dynamic Workflows subsections), Skills, Testing, Linting, Security and others. The "Skills" section is small (10 entries; Superpowers is the only general dev methodology). — [README raw](https://raw.githubusercontent.com/hesreallyhim/awesome-claude-code/HEAD/README.md)
- ComposioHQ/awesome-claude-skills: 77,869 stars, last push 2026-09-18, about 113 links. Its "Development & Code Tools" section includes aws-skills, Playwright Browser Automation (lackeyjb), iOS Simulator (conorluddy), FFUF fuzzing, pypict test design, Skill Seekers, NeoLabHQ context-engineering-kit (software-architecture, subagent-driven-development, prompt-engineering) and individual superpowers skills. — [README raw](https://raw.githubusercontent.com/ComposioHQ/awesome-claude-skills/HEAD/README.md)
- travisvn/awesome-claude-skills: 15,547 stars, last push 2026-04-28 (stale since spring), about 57 links. Its "Recent Updates" section stops at November 2025. — [README raw](https://raw.githubusercontent.com/travisvn/awesome-claude-skills/HEAD/README.md)
- VoltAgent/awesome-agent-skills: MIT, 36,314 stars, last push 2026-10-24, about 1,195 links ("1000+ agent skills from official dev teams and the community"). Sections: Official, Core, .NET/Java/Python/Rust/TypeScript, and Community. — [README raw](https://raw.githubusercontent.com/VoltAgent/awesome-agent-skills/HEAD/README.md)
- Codex-specific lists: composio-community/awesome-codex-skills (17,036 stars) and hashgraph-online/awesome-codex-plugins (1,401). — [GitHub topic search](https://api.github.com/search/repositories?q=topic:codex-skills&sort=stars)

**Directories and marketplaces**
- skills.sh, "The Agent Skills Directory", is made by Vercel. Its source is vercel-labs/skills and installs use `npx skills add <owner/repo>`. Its leaderboard shows install counts. #1 is find-skills (vercel-labs, 4.0M). The top 30 are mostly mattpocock/skills, plus heygen hyperframes (video), anthropics frontend-design (1.0M) and vercel-react-best-practices (836K). It is Vercel-run, but the skills it lists are community skills. — [skills.sh](https://skills.sh)
- SkillsMP (skillsmp.com) calls itself "the largest community-driven marketplace for AI coding agent skills". It claims 3,000,000+ open-source skills aggregated from GitHub, in 12 domains and 50+ categories, with a REST API and an MCP server. I could not see per-category counts or top lists. — [skillsmp.com](https://skillsmp.com)
- claude-plugins.dev is a community registry and CLI (`npx claude-plugins install`). By downloads, Anthropic plugins lead (document-skills 172.7k; the claude-code-plugins set 143.5k each), followed by wshobson plugins (about 39.3k each). No dates are given for the counts. — [claude-plugins.dev](https://claude-plugins.dev)
- quemsah/awesome-claude-plugins (1,475 stars) is an "automated index of Claude Code plugins and adoption metrics". karanb192/awesome-claude-code-mods (746) lists 5,000+ mods with their access scopes. — [GitHub topic search](https://api.github.com/search/repositories?q=topic:claude-code-plugins&sort=stars)

### Inferences
- The strongest usage signals are skills.sh installs and roundup citations. Both point to small, process-oriented packs (mattpocock, superpowers) rather than the large knowledge marketplaces. A team building a skill library should benchmark against superpowers, mattpocock, addyosmani and gstack for process skills, and use wshobson, ECC and Jeffallan to see how far knowledge-pack coverage goes.
- The aggregators (sickn33, alirezarezvani, VoltAgent lists, SkillsMP) are wide but shallow and contain many duplicates. They show what exists, not what is good.

### Gaps
- I did not reach any Hacker News or Reddit threads directly; search returned only blog roundups. Community sentiment above is second-hand.
- skills.sh shows no snapshot date or total count. SkillsMP's 3M figure could not be checked and probably counts duplicates and forks.
- I did not determine whether star counts are organic.

## For each major collection: dev-related skills, purpose, license, size, activity

### Takeaway
The table below lists each collection's dev skills with one-line purposes taken from frontmatter. Full per-skill lists are given for the curated process packs (superpowers, addyosmani, mattpocock, levnikolaevich, gstack, trailofbits dev subset). For the very large marketplaces (wshobson, ECC, Jeffallan, compound-engineering, claudekit) the lists are grouped by name.

### Cited Findings

#### obra/superpowers (MIT; 15 skills; last push 2026-10-23) — [tree](https://api.github.com/repos/obra/superpowers/git/trees/HEAD?recursive=1); purposes from raw SKILL.md in [repo](https://github.com/obra/superpowers)
| Skill | Purpose (frontmatter, condensed) | Taxonomy |
|---|---|---|
| brainstorming | Must be used before any creative work; draws out a design | 6, 7 |
| writing-plans | Write a multi-step plan from a spec before touching code | 11 |
| executing-plans | Execute a plan inline as the implementer | 12 |
| subagent-driven-development | Execute plan tasks via fresh subagents with review | 12, 73 |
| dispatching-parallel-agents | 2+ independent tasks without shared state | 73 |
| test-driven-development | Before writing implementation code | 13 |
| systematic-debugging | Any bug or failure, before proposing fixes | 31, 32 |
| verification-before-completion | Run verification commands before claiming done; "evidence before assertions" | 30, 77 |
| requesting-code-review | Verify work meets requirements before merge | 28 |
| receiving-code-review | Technical rigor, not "performative agreement" | 29 |
| using-git-worktrees | Isolated workspace before feature work | 75, 51 |
| finishing-a-development-branch | Decide merge/PR/keep/discard when done | 51, 52 |
| writing-skills | Create, edit and verify skills | 76 |
| using-superpowers | Router; requires skill invocation before any response | meta |
| diagnosing-superpowers | Diagnose why a superpowers session went wrong | meta/74 |

#### addyosmani/agent-skills (MIT; 25 skills; last push 2026-10-13) — [tree](https://api.github.com/repos/addyosmani/agent-skills/git/trees/HEAD?recursive=1)
- spec-driven-development (6, 8), interview-me (6, 71), idea-refine (7), planning-and-task-breakdown (11), incremental-implementation (12), test-driven-development (13), code-simplification (14), api-and-interface-design (9), frontend-ui-engineering (18, 68, 70), browser-testing-with-devtools (23, 69), code-review-and-quality (28), debugging-and-error-recovery (31, 32), performance-optimization (35, 44), security-and-hardening (38), observability-and-instrumentation (57), ci-cd-and-automation (54), git-workflow-and-versioning (50, 51, 52), deprecation-and-migration (43, 46), documentation-and-adrs (8, 62), shipping-and-launch (56), context-engineering (72), source-driven-development (ground decisions in official docs; 5), doubt-driven-development (fresh-context adversarial review of decisions; 28/7), constraint-driven-development (quality bar as a written contract), using-agent-skills (router). — [raw SKILL.md files](https://github.com/addyosmani/agent-skills)

#### mattpocock/skills (MIT; 38 skills; last push 2026-10-22) — [tree](https://api.github.com/repos/mattpocock/skills/git/trees/HEAD?recursive=1)
- Requirements and design: grill-me ("a relentless interview to sharpen a plan"; 6, 71), grilling, grill-with-docs (also writes ADRs and glossary; 8), domain-modeling (GLOSSARY.md, ADRs; 10), codebase-design (deep-module vocabulary; 9, 14), improve-codebase-architecture (scan for "deepening opportunities", HTML report; 14, 66), prototype (throwaway prototype to answer a design question; 7), to-spec / to-tickets (tracer-bullet tickets published to tracker; 11), wayfinder (plan work bigger than one session as decision tickets; 11), to-questionnaire.
- Build, test, debug: tdd (13), implement / implement-spec (12), diagnosing-bugs (diagnosis loop for hard bugs and perf regressions; 31, 33, 35), code-review (against repo standards and spec; 28), pr (PR body; 52), triage (issue/PR triage state machine).
- Agent practice: handoff (74), claude-handoff (74, 73), chief-of-staff (coordinate subagents; 73), retro (74), research (primary-source research to a markdown file), writing-for-agents (skills and AGENTS.md; 76), teach (5), ask-matt (router), wait-what.
- Tooling: setup-pre-commit (Husky + lint-staged + typecheck; 27), git-guardrails-claude-code (hooks blocking destructive git), setup-ts-deep-modules (dependency-cruiser; 27), migrate-to-shoehorn (TS test-assertion codemod; 65, narrow), wizard (bash wizard for human-only steps), scaffold-exercises.
- Writing: writing-beats, writing-fragments, writing-shape. — [raw SKILL.md files](https://github.com/mattpocock/skills)

#### garrytan/gstack (MIT; about 60 distinct skills; last push 2026-10-25) — [tree](https://api.github.com/repos/garrytan/gstack/git/trees/HEAD?recursive=1)
- Planning and review personas: office-hours (YC office hours; 7), plan-ceo-review, plan-eng-review, plan-design-review, plan-devex-review, autoplan (runs all reviews sequentially; 11), spec (vague intent → executable spec; 6).
- Ship and ops: ship (merge base, test, review diff, bump VERSION, update CHANGELOG, commit, push, PR; 48, 52, 53), land-and-deploy, setup-deploy, canary (post-deploy monitoring; 56), document-release (53), document-generate (60, 61).
- Quality: review (pre-landing PR review; 28), investigate (systematic debugging with root cause; 31, 32), qa / qa-only (browser/API/CLI bug finding; 23), test-audit (low-value or duplicate tests; 26, 66), health (code-quality dashboard), benchmark (web perf regression detection; 67), cso (security audit; 38), deslop-shared-libs (shared-code extraction; 14), devex-review.
- Design: design-consultation, design-shotgun, design-html, design-review (visual QA; 69), diagram (62), plus iOS ios-qa, ios-fix, ios-design-review.
- Safety and agent practice: careful / guard / freeze / unfreeze (destructive-command guardrails, directory-scoped edits), context-save / context-restore (74), retro (74), learn, codex (second-opinion wrapper), pair-agent, browse / scrape (bundled browser), skillify (76). — [raw SKILL.md files](https://github.com/garrytan/gstack)

#### levnikolaevich/claude-code-skills (MIT; 41 skills; last push 2026-10-18) — [tree](https://api.github.com/repos/levnikolaevich/claude-code-skills/git/trees/HEAD?recursive=1)
- Product (11–13): opportunity evaluator, product-requirements builder (6), interaction-design builder.
- Architecture (21–26): system-design baseline, current-architecture documenter (62), system-design proposal (8), ADR recorder (8), architecture diagram builder (62), architecture migration planner (46).
- Planning (31–33): delivery plan builder (11), test strategy planner (22, 23), plan reviewer.
- Implementation (41–46): surgical change implementer (12), dependency upgrader "in reversible batches" (46, 40), code modernizer (64), performance optimizer "retains only verified improvements" (35), benchmark comparator (67), quality-gate engineer (lint, type, architecture checks; 27).
- Quality (51–57): acceptance-test builder (23), delivery reviewer (28), documentation auditor (60, 61, 63), codebase auditor (66), test-suite auditor (26), architecture auditor, persistence auditor (44).
- Release and ops (61–64, 71–72): repository publisher (commit, push, verify), release publisher (48), deployment engineer (56), community announcer, operations investigator (59, 34), product-outcome evaluator.
- Engineering foundations (91–99): engineering-baseline builder, container engineer (55), configuration engineer (39), authentication engineer (42), resource-authorization engineer (42), error-handling engineer (15), observability engineer (57), mutation-reliability engineer (transactions and idempotency), database-lifecycle engineer (43).
- Meta: ln-81 skill reviewer (76). — [raw SKILL.md files](https://github.com/levnikolaevich/claude-code-skills)

#### trailofbits/skills (CC-BY-SA-4.0; 97 skills; last push 2026-10-24) — [tree](https://api.github.com/repos/trailofbits/skills/git/trees/HEAD?recursive=1)
- Security review (38): c-review, rust-review, differential-review (uses git blame, counts callers for blast radius; 3, 4), sharp-edges, spec-to-code-compliance, audit-context-building (1), audit-prep-assistant, code-maturity-assessor, variant-analysis, fp-check, vulnerability-triage-brocards, constant-time-analysis, zeroize-audit, dimensional-analysis, agentic-actions-auditor (GitHub Actions + AI agents; 54).
- Static analysis (27): semgrep (ships scripts/run-scans.sh), semgrep-rule-creator, semgrep-rule-variant-creator, codeql, sarif-parsing.
- Supply chain (40): supply-chain-risk-auditor.
- Testing (25, 26): property-based-testing (Hypothesis, fast-check, proptest, jqwik, rapid, Echidna/Medusa), mutation-testing, genotoxic, coverage-analysis; fuzzing: aflpp, libfuzzer, libafl, cargo-fuzz, atheris, ruzzy, ossfuzz, harness-writing, fuzzing-dictionary, fuzzing-obstacles, address-sanitizer (36), wycheproof, constant-time-testing.
- Bugs and regressions (31, 33): reproduce-bug, validate-bug, patching-bugs, implement-patch, prove-patch, post-patch-validation, regression-hunt, hunt-regressions, prepare-regression, reproduce-regression, replay-regression, adjudicate-regression, report-regressions.
- Code-graph tooling (Trailmark; 1, 2, 4, 62): trailmark, trailmark-structural, trailmark-summary, graph-evolution, slicing-code-context, diagramming-code, trailmark-review-gate, trailmark-variant-neighborhood.
- General dev: review-pr, panel-review, second-opinion (Codex or Antigravity cross-model review; 28), pr-improver / code-improver / skill-improver (review-and-fix loops; 29, 76), modern-python (uv, ruff, ty; 17, 27), modern-cpp (17), devcontainer-setup (49), gh-cli, github-triage, open-sourcing (48, 60), dwarf-expert (34), writing-lean-proofs, testing-handbook-generator (76). — [raw SKILL.md files](https://github.com/trailofbits/skills)

#### wshobson/agents (MIT; 185 skills in 94 plugins; last push 2026-10-24) — [tree](https://api.github.com/repos/wshobson/agents/git/trees/HEAD?recursive=1)
- Language packs (17): python-* (anti-patterns, code-style, configuration, design-patterns, error-handling, observability, packaging, performance-optimization, project-structure, resilience, resource-management, testing-patterns, type-safety, background-jobs), async-python-patterns, uv-package-manager, modern-javascript-patterns, typescript-advanced-types, javascript-testing-patterns, go-concurrency-patterns, rust-async-patterns, bash-defensive-patterns, bats-testing-patterns, shellcheck-configuration, dotnet-backend-patterns, memory-safety-patterns.
- Frameworks (18): nextjs-app-router-patterns, react-state-management, react-modernization, react-native-architecture/design, angular-migration, nodejs-backend-patterns, fastapi-templates, tailwind-design-system, unity-ecs-patterns, godot-gdscript-patterns.
- Architecture and API (8, 9): api-design-principles, openapi-spec-generation, architecture-patterns, architecture-decision-records, microservices-patterns, cqrs-implementation, saga-orchestration, event-store-design, projection-patterns, workflow-orchestration-patterns.
- Data (10, 20, 43–45): postgresql-table-design, sql-optimization-patterns, database-migration, dbt-transformation-patterns, airflow-dag-patterns, spark-optimization, data-quality-frameworks.
- Testing and quality (22, 23, 28): e2e-testing-patterns, temporal-python-testing, code-review-excellence, multi-reviewer-patterns, debugging-strategies (31), parallel-debugging, error-handling-patterns (15).
- Security (38–42): sast-configuration, secrets-management, stride-analysis-patterns, attack-tree-construction, threat-mitigation-mapping, security-requirement-extraction, auth-implementation-patterns, k8s-security-policies, mtls-configuration, solidity-security, pci-compliance, gdpr-data-handling.
- Delivery and ops (54–59): github-actions-templates, gitlab-ci-patterns, deployment-pipeline-design, gitops-workflow, helm-chart-scaffolding, k8s-manifest-generator, terraform-module-library, istio/linkerd, prometheus-configuration, grafana-dashboards, distributed-tracing, slo-implementation, incident-runbook-templates, postmortem-writing, on-call-handoff-patterns.
- Build and version control (47–53): bazel-build-optimization, turborepo-caching, nx-workspace-patterns, monorepo-management, dependency-upgrade, git-advanced-workflows, changelog-automation.
- UI (68–70): accessibility-compliance, wcag-audit-patterns, screen-reader-testing, responsive-design, design-system-patterns.
- Agent practice: parallel-feature-development, task-coordination-strategies, team-composition-patterns, context-driven-development, ai-debt-detector (66). Many non-dev items (finance, pptx, ML training). — [tree](https://api.github.com/repos/wshobson/agents/git/trees/HEAD?recursive=1)

#### affaan-m/ECC (MIT; 314 unique skill names; last push 2026-10-20) — [tree](https://api.github.com/repos/affaan-m/ECC/git/trees/HEAD?recursive=1)
- Per-stack "quartets" (patterns / security / tdd / verification) for django, laravel, springboot and quarkus. Plus python-, golang-, rust-, kotlin-, cpp-, java-, csharp-, fsharp-, perl- patterns/testing; react-patterns/-testing/-performance; nextjs-turbopack, nestjs-, fastapi-, rails-, nuxt4-, swiftui-patterns, swift-concurrency-6-2, kotlin-coroutines-flows, dart-flutter-patterns, postgres-, mysql-, redis-, prisma-patterns; docker-, kubernetes-, deployment-patterns.
- Process: tdd-workflow, verification-loop, search-first, codebase-onboarding (1), code-tour, change-impact (4), architecture-decision-records, database-migrations, error-handling, git-workflow, conventional-commit-review, e2e-testing, ai-regression-testing, module-regression, benchmark / benchmark-methodology (67), security-review / security-scan, inherit-legacy-style (64), brownfield-retrospective, accessibility / frontend-a11y, regex-vs-llm-structured-text (21, tangential).
- Agent practice: strategic-compact, context-budget (72), autonomous-loops, council / council-multi-model, plan-orchestrate, orch-add-feature / -fix-defect / -refine-code, skill-stocktake, skill-comply, rules-distill (76). There are many non-dev items (homelab, logistics, healthcare, investor). — [tree](https://api.github.com/repos/affaan-m/ECC/git/trees/HEAD?recursive=1)

#### Jeffallan/claude-skills (MIT; 67 skills; last push 2026-10-24) — [tree](https://api.github.com/repos/Jeffallan/claude-skills/git/trees/HEAD?recursive=1)
- Language "pros" (17): python-pro, typescript-pro, javascript-pro, golang-pro, rust-engineer, cpp-pro, csharp-developer, java-architect, kotlin-specialist, swift-expert, php-pro, sql-pro (20).
- Framework experts (18): react, vue, angular, nextjs, nestjs, django, fastapi, rails, laravel, spring-boot, flutter, react-native, dotnet-core, wordpress, shopify, salesforce.
- Cross-cutting: api-designer, graphql-architect, architecture-designer, microservices-architect, database-optimizer (44), postgres-pro, debugging-wizard (31), code-reviewer, security-reviewer, secure-code-guardian (38), test-master (22), playwright-expert (23), chaos-engineer, devops-engineer, sre-engineer (59), terraform-engineer, kubernetes-specialist, cloud-architect, monitoring-expert (57), legacy-modernizer (64), cli-developer (19), code-documenter (61), spec-miner (1/6), feature-forge (12), websocket-engineer, embedded-systems, the-fool (devil's advocate). — [tree](https://api.github.com/repos/Jeffallan/claude-skills/git/trees/HEAD?recursive=1)

#### EveryInc/compound-engineering-plugin (MIT; about 37 ce-* skills; last push 2026-10-25) — [tree](https://api.github.com/repos/EveryInc/compound-engineering-plugin/git/trees/HEAD?recursive=1)
- ce-brainstorm, ce-ideate (7), ce-plan (11), ce-work (12), ce-worktree (75), ce-debug (31), ce-code-review, ce-doc-review (28), ce-resolve-pr-feedback (29), ce-babysit-pr (54), ce-commit, ce-commit-push-pr (50, 52), ce-simplify-code (14), ce-optimize (35), ce-test-browser, ce-test-xcode (23), ce-proof (30), ce-handoff (74), ce-compound / ce-compound-refresh (capture learnings so later work is easier), ce-explain (5), ce-prototype, ce-noslop, ce-dogfood, ce-skill-work (76), lfg, wtf.

#### mrgoonie/claudekit-skills (no license detected; 45 skills; last push 2026-04-03) — [tree](https://api.github.com/repos/mrgoonie/claudekit-skills/git/trees/HEAD?recursive=1)
- Dev: backend-development, frontend-development, web-frameworks, databases, devops, better-auth (42), code-review (28), debugging / systematic-debugging / root-cause-tracing (31, 32), defense-in-depth (15), verification-before-completion (30), web-testing (23), chrome-devtools (69), context-engineering (72), repomix (pack repo for LLM; 1), docs-seeker, mermaidjs-v11 (62), mcp-builder, skill-creator (76).
- Thinking: problem-solving, sequential-thinking, when-stuck, inversion-exercise, collision-zone-thinking, simplification-cascades, meta-pattern-recognition, scale-game.

### Inferences
- Different curated packs repeat the same core process skills. Brainstorm, interview or grill, spec, plan, incremental implementation, TDD, debugging, review, verification and handoff appear in superpowers, addyosmani, mattpocock, compound-engineering and gstack. This core is converging.
- Knowledge marketplaces cover one stack at a time (Python × patterns/testing/security/perf). Process packs are general across languages. The taxonomy's P/K/T split matches how the community has divided itself.

### Gaps
- For the marketplaces, purposes are inferred from names. I did not read descriptions for wshobson, ECC, Jeffallan, compound-engineering or claudekit.
- Activity was measured only as the last-push date. Commit frequency and contributor counts were not collected.

## Notable patterns: process vs knowledge vs tool skills, bundled scripts, length

### Takeaway
Collections specialize by type. The most-installed packs are process skills. Knowledge packs dominate by count. Tool-wrapping skills with bundled scripts are concentrated in Trail of Bits, gstack and SDK-wrapper repos. SKILL.md length varies about 1,000×, from a 157-byte grill-me to a 137 KB gstack design-review. Descriptions follow three distinct styles.

### Cited Findings
- SKILL.md size and script bundling, computed from git-tree blob sizes. "With scripts" means the skill folder contains a .py/.sh/.js/.ts/.mjs/.rb file. — [GitHub tree API per repo, e.g. obra/superpowers](https://api.github.com/repos/obra/superpowers/git/trees/HEAD?recursive=1)

| Collection | Type | n | Median SKILL.md bytes | Min–max bytes | Skills with scripts |
|---|---|---|---|---|---|
| obra/superpowers | Process | 15 | 7,781 | 2,974 (requesting-code-review) – 19,506 (subagent-driven-development) | 3 |
| addyosmani/agent-skills | Process | 25 | 13,545 | 9,253 – 21,008 (constraint-driven-development) | 1 |
| mattpocock/skills | Process | 38 | 3,609 | 157 (grill-me) – 12,594 (ask-matt) | 3 |
| levnikolaevich | Process (SDLC roles) | 41 | 12,054 | 8,931 – 26,741 (plan-reviewer) | 0 |
| garrytan/gstack | Process + tool | 70 | 42,299 | 176 (fixture) – 137,185 (design-review) | 12 |
| trailofbits/skills | Tool + knowledge | 97 | 10,010 | 948 (panel-review) – 44,520 (rust-review) | 23 |
| Jeffallan/claude-skills | Knowledge | 67 | 6,169 | 3,917 – 8,524 | 0 |
| wshobson/agents | Knowledge | 185 | 5,463 | 1,375 – 26,448 (dotnet-backend-patterns) | 6 |

- Description styles differ by collection. superpowers uses trigger-only descriptions ("Use when encountering any bug… before proposing fixes"). addyosmani uses "Does X. Use when …" with several "Use when" clauses. levnikolaevich adds a negative scope boundary ("…; does not plan tasks or implement"). gstack mostly uses short titles plus "(gstack)". — [superpowers](https://github.com/obra/superpowers); [addyosmani](https://github.com/addyosmani/agent-skills); [levnikolaevich](https://github.com/levnikolaevich/claude-code-skills); [gstack](https://github.com/garrytan/gstack)
- Router or meta skills are common in curated packs: using-superpowers, using-agent-skills (addyosmani), ask-matt, the gstack router, and setup-matt-pocock-skills, which configures the repo's tracker and doc layout before the other skills are used. — same sources
- Cross-harness distribution is now standard. superpowers lists 16 harnesses. wshobson generates adapters for 7 harnesses and notes an 8 KB Codex skill budget. ECC duplicates each skill per harness (1,062 files / 314 names). — [superpowers](https://github.com/obra/superpowers); [wshobson/agents](https://github.com/wshobson/agents)
- Guardrail skills, a category the taxonomy lacks, are widespread: gstack careful/guard/freeze, mattpocock git-guardrails-claude-code (hooks that block push, reset --hard and similar), ECC safety-guard and gateguard, wshobson block-no-verify-hook. — trees cited above
- Cross-model "second opinion" review appears in several packs: trailofbits second-opinion (Codex or Antigravity), gstack codex, ECC council-multi-model. — trees cited above

### Inferences
- Popularity is inversely related to length. The most-installed skills (mattpocock: median 3.6 KB, grill-me 157 bytes) are much shorter than the long role or knowledge skills. This suggests that a short, sharp process nudge is what people reuse. Length is not proof of value.
- Scripts appear mainly where a deterministic tool is involved (Semgrep, CodeQL, fuzzers, browsers). Process and knowledge skills almost never ship code. Tool-type taxonomy items (bisect, coverage, codemods, profiling) are where the community is thinnest, so a library aimed at gaps should expect to write scripts.

### Gaps
- I did not measure how often skills use progressive disclosure (references/ subfolders) versus a single file.
- There is no independent quality or eval data comparing the packs. The claims of effectiveness are the authors' own ([rywalker.com](https://rywalker.com/research/superpowers-skills-framework)).

## Which taxonomy items are well covered, thinly covered, or uncovered?

### Takeaway
Coverage is good for planning, requirements, TDD, debugging, code review, security, language and framework packs, infrastructure, delivery and agent practice. Coverage is thin to none for tool-type and maintenance items: history archaeology (3), regular expressions (21), flaky tests (24), bisecting (33), stack-trace/log reading (34), memory leaks (36), concurrency bugs (37), codemods (65), legacy characterization tests (64), code comments (63), README/API docs (60, 61), CSS debugging (70) and honest status reporting (77).

### Cited Findings
- Name search across 4,713 (repo, skill) pairs from 14 collections found **zero** skills named for bisect, git blame/history, codemod/ast-grep/OpenRewrite/comby, characterization or golden-master tests, stack-trace or log analysis, crash or core-dump analysis, flame graphs, memory profiling, deadlocks, or docstrings. — [combined trees of the 14 repos above, e.g. sickn33](https://api.github.com/repos/sickn33/agentic-awesome-skills/git/trees/HEAD?recursive=1)
- Matches for flaky tests: only github/awesome-copilot cypress-flake-fixer and sickn33 test-fixing. For merge conflicts: only sickn33 resolving-merge-conflicts and awesome-copilot rebase-current-branch. For regex: only ECC regex-vs-llm-structured-text, which is about choosing between regex and an LLM. — same
- The only regression hunting found is Trail of Bits' regression-hunt suite, which reproduces security regressions with before/after deployments and is not git bisect. mattpocock diagnosing-bugs covers "hard bugs and performance regressions". — [trailofbits tree](https://api.github.com/repos/trailofbits/skills/git/trees/HEAD?recursive=1); [mattpocock](https://github.com/mattpocock/skills)
- Property-based and fuzz testing is well covered, but almost entirely by Trail of Bits (property-based-testing plus 12 fuzzing/sanitizer skills). — [trailofbits tree](https://api.github.com/repos/trailofbits/skills/git/trees/HEAD?recursive=1)

### Inferences
- The community concentrates on the "front" of the SDLC (clarify → plan → implement → review) and on stack knowledge. It neglects investigative and tool-heavy work: archaeology, bisect, log or trace reading, memory and concurrency debugging, codemods. A new library can add the most value there.
- Several items are covered only incidentally inside broader skills: root cause inside systematic-debugging, impact inside differential-review, worktrees inside superpowers. Such coverage exists but is hard to find or invoke alone.
- Areas the community covers that the taxonomy lacks are candidate additions: (a) destructive-action guardrails and hooks; (b) plan review by persona or adversary (gstack plan-*-review, addyosmani doubt-driven-development, Jeffallan the-fool); (c) cross-model second opinions; (d) repo setup for agents (AGENTS.md/CLAUDE.md generation, context-engineering, setup-matt-pocock-skills); (e) browser-driven QA as a tool; (f) LLM-app engineering (RAG, evals, prompt engineering); (g) issue triage (mattpocock triage, trailofbits github-triage); (h) "capture learnings" or compounding knowledge (ce-compound, gstack learn, ECC continuous-learning).

### Gaps
- Classification is by name plus the descriptions I read, so content-level coverage may be higher. For example, superpowers' systematic-debugging body contains root-cause tracing, and older superpowers versions reportedly had testing-anti-patterns and condition-based-waiting skills, which I did not verify in the current tree.
- SkillsMP and skills.sh could not be searched by keyword in this session, so long-tail single-skill repos outside the 14 indexed collections may fill some gaps.

### Coverage table (taxonomy item → skills found → coverage)

Coverage key: **good** = several dedicated skills in 3 or more collections; **thin** = 1–4 dedicated skills, or coverage only incidental or confined to one niche; **none** = no dedicated skill found. Collection abbreviations: SP superpowers, AO addyosmani, MP mattpocock, GS gstack, LN levnikolaevich, ToB trailofbits, WS wshobson, ECC, JA Jeffallan, CE compound-engineering, CK claudekit, AC awesome-copilot, AR alirezarezvani, S33 sickn33.

| # | Item | Skills found (examples) | Coverage |
|---|---|---|---|
| 1 | Codebase orientation | ECC/AR codebase-onboarding, AC acquire-codebase-knowledge, AC context-map, S33 analyze-project, ECC/AR code-tour, ToB audit-context-building, trailmark-summary, CK repomix; also Understand-Anything, graphify, archify | good |
| 2 | Tracing a behavior | ToB slicing-code-context, trailmark (taint, call paths), CK root-cause-tracing (traces a bug backwards) | thin |
| 3 | History archaeology | none dedicated; incidental in ToB differential-review (git blame) and prepare-regression (PR context) | none |
| 4 | Dependency / impact analysis | ECC change-impact, AC api-breaking-change-detector, AC sql-object-impact-analysis, ToB differential-review (blast radius), ToB graph-evolution | thin |
| 5 | Reading an unfamiliar language / framework | MP teach, CE ce-explain, S33 code-documentation-code-explain, AO source-driven-development (docs-grounded) | thin |
| 6 | Clarifying requirements | MP grill-me / grilling / grill-with-docs / to-spec, AO interview-me / spec-driven-development, S33 ask-questions-if-underspecified, LN ln-12, GS spec, AR prd / code-to-prd, JA spec-miner | good |
| 7 | Brainstorming / options | SP brainstorming, CE ce-brainstorm / ce-ideate, AO idea-refine, GS office-hours, MP prototype, S33 multi-agent-brainstorming, AR decide | good |
| 8 | Design doc / RFC / ADR | WS/ECC architecture-decision-records, AO documentation-and-adrs, LN ln-23 / ln-24, AC create-architectural-decision-record, MP grill-with-docs / domain-modeling, ECC ralphinho-rfc-pipeline | good |
| 9 | API design | AO api-and-interface-design, WS api-design-principles / openapi-spec-generation, ECC api-design, JA api-designer / graphql-architect, AR api-design-reviewer, MP codebase-design | good |
| 10 | Data modeling / schema | WS postgresql-table-design, AR database-schema-designer / database-designer, MP domain-modeling, AC cosmosdb-datamodeling, S33 database-design | good |
| 11 | Planning / task breakdown | SP writing-plans, AO planning-and-task-breakdown, MP to-tickets / wayfinder, CE ce-plan, LN ln-31 / ln-33, GS autoplan, AC breakdown-plan, OthmanAdi planning-with-files | good |
| 12 | Feature implementation loop | SP executing-plans / subagent-driven-development, AO incremental-implementation, MP implement, CE ce-work, LN ln-41, JA feature-forge, ECC orch-add-feature | good |
| 13 | TDD | SP test-driven-development, AO test-driven-development, MP tdd, ECC tdd-workflow (+ django/laravel/springboot/quarkus-tdd), S33 tdd-workflows | good |
| 14 | Refactoring safely | AO code-simplification, CE ce-simplify-code, MP improve-codebase-architecture / codebase-design, GS deslop-shared-libs, S33 code-refactoring-refactor-clean, AC java-refactoring-* | good |
| 15 | Error handling / validation | WS error-handling-patterns / python-error-handling / python-resilience, ECC error-handling, LN ln-96, CK defense-in-depth, S33 zod-validation-expert | good |
| 16 | Concurrency / async correctness | WS async-python-patterns / go-concurrency-patterns / rust-async-patterns, ECC swift-concurrency-6-2 / kotlin-coroutines-flows, AC csharp-async (all language-specific; no general skill) | good (language-specific only) |
| 17 | Language idiom packs | JA *-pro (12 languages), WS python-* (14) / typescript-advanced-types / bash-defensive-patterns, ECC *-patterns / *-testing (12+ languages), ToB modern-python / modern-cpp, S33 many | good |
| 18 | Framework packs | JA (16 frameworks), ECC (django, laravel, spring, quarkus, nest, next, nuxt, rails, react, swiftui, flutter), WS (next, react, react-native, angular, fastapi, node) | good |
| 19 | CLI tools and scripts | JA cli-developer, S33 bash-scripting / ai-native-cli, MP wizard, WS bash-defensive-patterns | thin |
| 20 | SQL and queries | JA sql-pro / postgres-pro, ECC postgres- / mysql- / redis-patterns, WS sql-optimization-patterns, ECC clickhouse-io | good |
| 21 | Regex and text processing | only ECC regex-vs-llm-structured-text (tangential) | none |
| 22 | Writing unit tests | ECC *-testing (python, go, rust, kotlin, cpp, csharp, react), WS python-testing-patterns / javascript-testing-patterns / bats-testing-patterns, JA test-master, LN ln-32 / ln-55, GS test-audit | good |
| 23 | Integration / e2e tests | ECC/WS e2e-testing(-patterns), JA playwright-expert, AO browser-testing-with-devtools, LN ln-51, CE ce-test-browser, GS qa, AC playwright, CK web-testing | good |
| 24 | Fixing failing / flaky tests | AC cypress-flake-fixer, S33 test-fixing (superpowers' condition-based-waiting no longer in current tree, unverified) | thin |
| 25 | Property-based and fuzz testing | ToB property-based-testing, mutation-testing, aflpp, libfuzzer, libafl, cargo-fuzz, atheris, ruzzy, ossfuzz, harness-writing, fuzzing-dictionary/obstacles; S33 ffuf-web-fuzzing | good (ToB-dominated) |
| 26 | Test coverage gap analysis | AR coverage, AC pytest-coverage, ToB coverage-analysis (fuzzing), ToB genotoxic, LN ln-55 test-suite-auditor, GS test-audit | thin |
| 27 | Static analysis / lint / types | ToB semgrep / codeql / sarif-parsing / semgrep-rule-creator, LN ln-46 quality-gate-engineer, WS sast-configuration / shellcheck-configuration / python-type-safety, MP setup-pre-commit / setup-ts-deep-modules, ToB modern-python | good |
| 28 | Code review | SP requesting-code-review, AO code-review-and-quality, MP code-review, GS review, CE ce-code-review, WS code-review-excellence / multi-reviewer-patterns, ToB review-pr / differential-review / panel-review / second-opinion, JA code-reviewer, LN ln-52 | good |
| 29 | Receiving review | SP receiving-code-review, CE ce-resolve-pr-feedback, S33 address-github-comments, ToB pr-improver (loop) | thin |
| 30 | Verification before done | SP verification-before-completion, ECC verification-loop (+ per-stack *-verification), CE ce-proof, LN ln-46, S33 dos-verify-done-claims / agentic-verify, CK verification-before-completion | good |
| 31 | Systematic debugging | SP systematic-debugging, AO debugging-and-error-recovery, MP diagnosing-bugs, GS investigate, CE ce-debug, WS debugging-strategies / parallel-debugging, JA debugging-wizard, CK debugging | good |
| 32 | Root-cause analysis | CK root-cause-tracing, GS investigate ("root cause"), AO debugging-and-error-recovery, ToB variant-analysis (sibling root causes); mostly folded into debugging | thin (mostly folded into debugging) |
| 33 | Bisecting regressions | no git-bisect skill; ToB regression-hunt suite (security, before/after deploys), MP diagnosing-bugs (mentions perf regressions) | thin |
| 34 | Stack traces, logs, core dumps | S33 error-debugging-error-trace / error-diagnostics-error-trace, ToB dwarf-expert / address-sanitizer (crash reports), LN ln-71 operations-investigator | thin |
| 35 | Performance profiling and optimization | AO performance-optimization, LN ln-44 / ln-45, WS python-performance-optimization, ECC react-performance / benchmark, AR performance-profiler, S33 performance-profiling, CE ce-optimize | good |
| 36 | Memory leaks / resource exhaustion | ToB address-sanitizer (LeakSanitizer), WS python-resource-management / memory-safety-patterns | thin |
| 37 | Concurrency bugs (races, deadlocks) | S33 hunt-race-condition (security), ToB rust-review / c-review (race sections) | thin |
| 38 | Secure code review | ToB c-review / rust-review / sharp-edges / differential-review / variant-analysis, AO security-and-hardening, ECC security-review (+ per-stack), GS cso, JA security-reviewer / secure-code-guardian, many S33 | good |
| 39 | Secrets handling / leak detection | WS secrets-management, S33 secret-scanning / client-secret-exposure-audit, AR env-secrets-manager, LN ln-93 (secret boundaries), ToB zeroize-audit (memory) | good |
| 40 | Dependency vulnerability audit | ToB supply-chain-risk-auditor, AR dependency-auditor, WS dependency-upgrade, LN ln-42, S33 sbom-supply-chain, ECC mcp-dependency-review | good |
| 41 | Threat modeling | WS stride-analysis-patterns / attack-tree-construction / threat-mitigation-mapping / security-requirement-extraction, S33 threat-modeling-expert, AC threat-model-analyst | good |
| 42 | AuthN / AuthZ | WS auth-implementation-patterns, LN ln-94 / ln-95, CK better-auth, S33 clerk-auth | good |
| 43 | Database migrations | WS database-migration, ECC database-migrations, AO deprecation-and-migration, LN ln-99, S33 drizzle-migration-conflict | good |
| 44 | Query performance | WS sql-optimization-patterns, JA database-optimizer, AC/S33 postgresql-optimization, LN ln-57 persistence-auditor | good |
| 45 | Data pipelines / ETL | WS airflow-dag-patterns / dbt-transformation-patterns / data-quality-frameworks / spark-optimization, JA spark-engineer / pandas-pro, AR data-quality-auditor | good |
| 46 | Dependency upgrades / version migrations | WS dependency-upgrade / angular-migration / react-modernization, LN ln-42 / ln-43 / ln-26, AO deprecation-and-migration, AC dotnet-upgrade, AR migration-architect | good |
| 47 | Build system debugging | WS bazel-build-optimization / turborepo-caching / nx-workspace-patterns / monorepo-management (optimization, not "debug a broken build") | thin |
| 48 | Packaging and releasing | LN ln-62 release-publisher, GS ship / document-release, WS python-packaging, S33 npm-trusted-publishing / semantic-versioning, ToB open-sourcing, AC github-release | good |
| 49 | Reproducible dev environment | ToB devcontainer-setup, S33 devcontainers-nix, ECC flox-environments, WS uv-package-manager, AR docker-development | good |
| 50 | Commit hygiene | AO git-workflow-and-versioning (atomic commits), CE ce-commit, AC conventional-commit, ECC conventional-commit-review, S33 git-commit | good |
| 51 | Branching / rebasing / merge conflicts | WS git-advanced-workflows, SP finishing-a-development-branch, S33 resolving-merge-conflicts, AC rebase-current-branch, ECC git-workflow | thin (conflict resolution); good for workflow |
| 52 | PR preparation and description | MP pr, CE ce-commit-push-pr, GS ship, AO git-workflow-and-versioning, S33 create-pr | good |
| 53 | Changelogs / release notes | WS changelog-automation, AR changelog-generator, GS ship / document-release, S33 changelog-entry | good |
| 54 | CI config and fixing CI | WS github-actions-templates / gitlab-ci-patterns, AO ci-cd-and-automation, CE ce-babysit-pr, S33 github-actions-debugger, AR ci-cd-pipeline-builder, ToB agentic-actions-auditor | good |
| 55 | Containers | ECC docker-patterns, LN ln-92, AR docker-development, S33 docker-compose / container-hardening, AC containerize-aspnetcore | good |
| 56 | Deployment and rollback | AO shipping-and-launch, GS land-and-deploy / canary, ECC deployment-patterns / canary-watch, LN ln-63, WS deployment-pipeline-design / gitops-workflow | good |
| 57 | Observability | AO observability-and-instrumentation, LN ln-97, WS prometheus-configuration / grafana-dashboards / distributed-tracing / slo-implementation / python-observability, JA monitoring-expert | good |
| 58 | Infrastructure as code | WS terraform-module-library / helm-chart-scaffolding / k8s-manifest-generator, JA terraform-engineer / kubernetes-specialist, ECC kubernetes-patterns, S33 aws-cdk-development | good |
| 59 | Incident response / postmortems | WS incident-runbook-templates / postmortem-writing / on-call-handoff-patterns, AR incident-commander / postmortem, JA sre-engineer, LN ln-71 | good |
| 60 | README / getting-started | AC create-readme / readme-blueprint-generator, S33 readme, GS document-generate, LN ln-53 (audit), ToB open-sourcing | thin |
| 61 | API reference / docstrings | JA code-documenter, S33 api-documenter / api-documentation-generator, WS openapi-spec-generation | thin |
| 62 | Architecture docs / diagrams | LN ln-22 / ln-25, ToB diagramming-code, GS diagram, S33 c4-* / mermaid-expert, CK mermaidjs-v11, AC architecture-blueprint-generator; also archify | good |
| 63 | Code comments | S33 lean-comments, AC add-educational-comments, LN ln-53 (audits comments) | thin |
| 64 | Legacy code / characterization tests | JA legacy-modernizer, LN ln-43, ECC inherit-legacy-style / brownfield-retrospective, S33 framework-migration-legacy-modernize (none name characterization tests) | thin |
| 65 | Large-scale codemods | none (closest: MP migrate-to-shoehorn, a single-purpose TS codemod) | none |
| 66 | Dead code / tech-debt assessment | WS ai-debt-detector, S33 tech-debt / codebase-cleanup-tech-debt, AR tech-debt-tracker / flag-cleanup, ponytail-debt, GS test-audit, LN ln-54, MP improve-codebase-architecture | good |
| 67 | Performance regression guarding | GS benchmark (web perf regressions), LN ln-45 benchmark-comparator, ECC benchmark-methodology / benchmark-optimization-loop | thin |
| 68 | Accessibility | WS accessibility-compliance / wcag-audit-patterns / screen-reader-testing, ECC accessibility / frontend-a11y, AR a11y-audit, AO frontend-ui-engineering | good |
| 69 | UI from design; visual verification | anthropics frontend-design (vendor, 1.0M installs), GS design-review / design-html / design-shotgun / ios-design-review, AO browser-testing-with-devtools, Leonxlnx taste-skill, CK chrome-devtools, S33 figma-automation | good |
| 70 | Responsive layout / CSS debugging | WS responsive-design / tailwind-design-system, S33 tailwind-patterns (no CSS-debugging skill) | thin |
| 71 | Clarifying questions vs proceeding on defaults | MP grill-me / grilling, AO interview-me, S33 ask-questions-if-underspecified, AR interview; nothing on *when not* to ask | good (asking side only) |
| 72 | Context management | AO/CK context-engineering, ECC strategic-compact / context-budget, planning-with-files, context-mode, S33 context-compression, MP research (offload) | good |
| 73 | Delegating to subagents | SP dispatching-parallel-agents / subagent-driven-development, MP chief-of-staff / claude-handoff, ToB slicing-code-context / panel-review, WS parallel-feature-development / task-coordination-strategies, ECC plan-orchestrate | good |
| 74 | Handoff notes / journals | MP handoff (1.0M installs) / claude-handoff / retro, CE ce-handoff, GS context-save / context-restore / retro, S33 session-handoff | good |
| 75 | Git worktrees / parallel branches | SP using-git-worktrees, CE ce-worktree, AR git-worktree-manager | thin (few, but SP's is widely installed) |
| 76 | Writing and testing skills | SP writing-skills, MP writing-for-agents, ToB skill-improver / testing-handbook-generator, LN ln-81, ECC skill-stocktake / skill-comply, GS skillify, CK skill-creator, Anthropic skill-creator (vendor) | good |
| 77 | Estimating effort / honest status | S33 progressive-estimation / anti-deception / anti-sycophancy / dos-verify-done-claims; SP verification-before-completion covers "no claims without evidence" | thin |

Summary counts: good 52; thin 22 (items 2, 4, 5, 19, 24, 26, 29, 32, 33, 34, 36, 37, 47, 51, 60, 61, 63, 64, 67, 70, 75, 77); none 3 (items 3, 21, 65). Item 32 is counted as thin even though root-cause work is present inside debugging skills. Items 16 and 71 are good with caveats (language-specific only; asking side only).

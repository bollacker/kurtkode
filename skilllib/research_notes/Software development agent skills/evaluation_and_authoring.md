# Agent Skills: Effectiveness Evidence, Evaluation Methods, and Authoring Practice

Notes compiled 2026-10-25. "Measured" means a number from an experiment; "guidance" or "opinion" means vendor docs or practitioner advice with no reported experiment. Items marked *(snippet only)* were seen only in search-result excerpts or abstracts, not checked against the full paper.

## 1. Published evaluations of skill and context-file effectiveness: what they found, and whether skills help small or open models

### Takeaway
Results are mixed and depend heavily on domain. On broad, mostly non-SWE tasks, curated skills give large average gains (SkillsBench +16.2pp). On software engineering the gain is small (+4.5pp), and two SWE/web-dev studies found context files or skills neutral to harmful while raising cost by 20% to nearly 400%. Self-generated skills and LLM-generated context files do not help. Skills can lift smaller models, but how well a model follows a skill varies widely, and skill rankings do not transfer well across models.

### Cited Findings

**SkillsBench (arXiv 2602.12670, Li et al., first posted 13 Feb 2026; NeurIPS 2026 poster), measured**
- Design: 84 evaluated tasks (86 passed review) across 11 domains. Each task runs under three conditions (no skills, curated skills, self-generated skills), on 7 agent-model configurations across Claude Code, Gemini CLI and Codex CLI, for 7,308 valid trajectories. Each task is run 5 times at temperature 0 and graded by deterministic pytest verifiers with binary pass/fail and no LLM judge. Leakage audits are run by a validation agent in CI. 86 of 322 candidate tasks were accepted (26.7%). — [arXiv HTML v1](https://arxiv.org/html/2602.12670v1)
- Average pass rate is 24.3% with no skills and 40.6% with curated skills (+16.2pp). Self-generated skills score 21.5% (−1.3pp in the text, −1.8 in Table 3). — [arXiv HTML v1](https://arxiv.org/html/2602.12670v1)
- Per-configuration gains range from +13.6pp to +23.3pp. The largest is Claude Code with Opus 4.5 (22.0% to 45.3%). The best absolute score is Gemini CLI with Gemini 3 Flash at 48.7% with skills (31.3% without). — [arXiv HTML v1](https://arxiv.org/html/2602.12670v1)
- **Software Engineering has the smallest domain gain: 34.4% to 38.9% (+4.5pp).** Healthcare gains +51.9pp and Manufacturing +41.9pp. — [arXiv HTML v1](https://arxiv.org/html/2602.12670v1)
- 16 of 84 tasks get worse with skills. The worst is taxonomy-tree-merge at −39.3pp. — [arXiv HTML v1](https://arxiv.org/html/2602.12670v1)
- Number of skills supplied:

  | Skills supplied | Gain |
  |---|---|
  | 1 | +17.8pp |
  | 2–3 | +18.6pp |
  | 4 or more | +5.9pp |

  — [arXiv HTML v1](https://arxiv.org/html/2602.12670v1)
- Skill length:

  | Skill style | Gain |
  |---|---|
  | "Detailed" | +18.8pp |
  | "Compact" | +17.1pp |
  | "Standard" | +10.1pp |
  | "Comprehensive" | −2.9pp (N=140) |

  Exhaustive skills underperform. — [arXiv HTML v1](https://arxiv.org/html/2602.12670v1)
- Small model: Claude Haiku 4.5 goes from 11.0% to 27.7% with skills (+16.7pp), which beats Opus 4.5 without skills (22.0%). — [arXiv HTML v1](https://arxiv.org/html/2602.12670v1)
- The paper is internally inconsistent: it gives 84 and 86 tasks, and the Fig. 2 caption says +12.66pp against +16.2pp in the text. The NeurIPS listing says 84 tasks across 8 domains, +16.4pp, and 7,326 trajectories. — [arXiv HTML v1](https://arxiv.org/html/2602.12670v1); [NeurIPS 2026 poster](https://neurips.cc/virtual/2026/poster/139353)

**Evaluating AGENTS.md (arXiv 2602.11988, Gloaguen, Mündler, Müller, Raychev, Vechev; 12 Feb 2026; ICLR 2026), measured**
- Benchmarks: SWE-bench Lite (300 tasks) and the new AGENTbench (138 instances from 12 repos with developer-committed context files). Agents tested include Claude Code with Sonnet 4.5, Codex with GPT-5.2 and GPT-5.1 mini, and Qwen3-30b-coder. — [arXiv HTML](https://arxiv.org/html/2602.11988v1); [secondary summary](https://aiweekly.co/alerts/paper-finds-agentsmd-files-hurt-coding-agent-task-success)
- **LLM-generated context files** lower success by about 0.5% (SWE-bench Lite) and about 2% (AGENTbench), and hurt in 5 of 8 settings. They add 2.45 and 3.92 steps and raise cost by about 20% and 23%. — [arXiv HTML](https://arxiv.org/html/2602.11988v1)
- **Developer-written context files** raise success by about 4% on average. They help every agent except Claude Code, and add up to 19% in cost. — [arXiv HTML](https://arxiv.org/html/2602.11988v1)
- Agents do follow the files: they test and explore more. The files do not get agents to the relevant file any faster. — [arXiv HTML](https://arxiv.org/html/2602.11988v1)
- When the repository's documentation is removed, LLM-generated files help by about 2.7%. Context files therefore help most where documentation is thin. — [arXiv HTML](https://arxiv.org/html/2602.11988v1)
- Recommendation (authors' opinion): skip LLM-generated files, and human-written files "should describe only minimal requirements." — [arXiv HTML](https://arxiv.org/html/2602.11988v1)

**Vercel, "AGENTS.md outperforms skills in our agent evals" (Jude Gao, 27 Jan 2026), measured but small and partly undisclosed**
- The eval targets Next.js 16 APIs that are not in training data (`'use cache'`, `connection()`, `forbidden()` and others), graded on build, lint and test. The model, task count and number of runs are not disclosed. — [Vercel blog](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals)
- Overall pass rates:

  | Configuration | Pass rate |
  |---|---|
  | No docs | 53% |
  | Skill, default | 53% |
  | Skill plus explicit instructions to use it | 79% |
  | Compressed 8KB docs index in AGENTS.md | 100% |

  — [Vercel blog](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals)
- **The skill was never invoked in 56% of cases.** With the skill present but unused, the test pass rate fell from 63% to 58%. — [Vercel blog](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals)
- Results were sensitive to instruction wording. "You MUST invoke the skill" made the agent anchor on the docs and miss project context. "Explore project first, then invoke skill" did better. — [Vercel blog](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals)
- The docs were compressed from about 40KB to 8KB with no loss. Vercel still sees a role for skills in explicit, action-specific workflows such as migrations (its opinion). — [Vercel blog](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals)

**Signal or Noise? WebDev-Skills-Bench (arXiv 2608.23067, Yang & Ding, 24 Aug 2026), measured** *(abstract only)*
- Setup: 31 public web-dev skills, 50 Web-Bench projects, 1,000 ordered tasks, 4 models (not named in the abstract). Four matched conditions, including a **length-matched irrelevant-skill control** and leave-one-out ablations. — [arXiv abs](https://arxiv.org/abs/2608.23067)
- Injecting the target skill **lowers mean Pass@2 by 1.3–4.2%** and **raises token cost by 72–394%**. Only 17–36% of skill-project pairs show gains. Losses concentrate on easy early tasks. — [arXiv abs](https://arxiv.org/abs/2608.23067)
- Some models are "length-distracted": an equally long irrelevant skill reproduces most of the loss. Others are "content-misled": the skill content itself costs 1.1–1.4%. — [arXiv abs](https://arxiv.org/abs/2608.23067)
- Skill rankings transfer weakly across models. Among helpful skills, anti-pattern rules beat example-heavy content. — [arXiv abs](https://arxiv.org/abs/2608.23067)
- Authors' recommendation: treat a skill as "a hypothesis about a specific Skill-project-model combination," and make length-matched controls and per-model audits the minimum standard. — [arXiv abs](https://arxiv.org/abs/2608.23067)

**A Framework for Evaluating Agentic Skills at Scale (arXiv 2606.17819, Shaposhnikov et al., 16 Jun 2026)** *(abstract only)*
- Setup: 500 real-world skills, 1,000 tasks generated from skill content, each with instruction-following and goal-completion rubrics, run on 19 agent-model configurations (proprietary and open-source). — [arXiv abs](https://arxiv.org/abs/2606.17819)
- Finding: models "vary widely" in how closely they follow skill instructions, which drives "substantial differences" in gains. The abstract gives no numbers. — [arXiv abs](https://arxiv.org/abs/2606.17819)

**Small and open models**
- Haiku 4.5 with skills beats Opus 4.5 without them on SkillsBench. — [arXiv HTML v1](https://arxiv.org/html/2602.12670v1)
- *(snippet only)* An industrial SLM study (arXiv 2602.16653) reports that tiny models struggle to select skills reliably, while moderately sized SLMs of about 12B–30B "benefit substantially." — [arXiv 2602.16653](https://arxiv.org/html/2602.16653v2)
- The AGENTS.md paper's negative effect for LLM-generated files held across model families, including open Qwen3-30b-coder. — [secondary summary](https://aiweekly.co/alerts/paper-finds-agentsmd-files-hurt-coding-agent-task-success); [arXiv](https://arxiv.org/html/2602.11988v1)
- *(snippet only)* The Vals.ai SkillsBench leaderboard lists Qwen 3.7 Plus (hosted) at 54.30% at $0.14 per task. — [vals.ai](https://www.vals.ai/benchmarks/skillsbench)

### Inferences
- For a software-engineering skill library, the realistic prior is a small gain, with real risk of a net loss and a large cost increase. The large SkillsBench averages come mostly from non-SWE domains with specialized procedures.
- Gains concentrate where the model lacks knowledge: APIs outside training data (Vercel), repos with thin documentation (AGENTS.md paper), and niche procedures. A test method should weight tasks toward that gap and include "model already knows this" tasks to detect harm.
- Two failure mechanisms need separate measurement: (a) the skill is never loaded (Vercel, 56%), and (b) the skill is loaded but distracts or misleads (Signal or Noise, SkillsBench's 16 negative tasks).
- Concise, focused skills (1–3 per task, not "comprehensive") look best across sources.
- Per-model results are necessary. Gains and adherence vary widely by model, and rankings transfer weakly.

### Gaps
- No study found that isolates small open-weight coding models (for example 7–30B local models) on SWE tasks with skills. The 12B–30B SLM claim was seen only in a snippet.
- Neither the Signal or Noise abstract nor the Framework-at-Scale abstract names its models. The full papers are needed for per-model numbers.
- No Anthropic-published quantitative effectiveness study was found. Anthropic's docs give guidance, not measured effect sizes.
- A follow-up two-agent ablation (Claude Code vs Codex on 17 tasks, listed by a third party as arXiv 2607.27250) could not be verified. — [developersdigest](https://www.developersdigest.tech/papers/do-context-files-help-coding-agents-a-two-agent-ablation-study-on-real-repositories)

## 2. How skill triggering is measured (loads when it should, stays out when it shouldn't)

### Takeaway
The most concrete published method is Anthropic's skill-creator. It uses about 20 labelled queries (half should trigger, half are near-miss negatives), runs each query 3 times to get a trigger rate, and optimizes the description over up to 5 iterations against a 60/40 train/test split. Behavioral effectiveness is measured separately, with paired with-skill and without-skill (or old-skill) runs, assertion grading, and mean ± stddev for pass rate, time and tokens. Superpowers adds adversarial "pressure tests" on subagents for skills that enforce discipline. Academic work measures selection accuracy as the library grows.

### Cited Findings

**Anthropic skill-creator (anthropics/skills repo), method description, not results**
- Trigger eval set: 20 queries, 8–10 should-trigger and 8–10 should-not-trigger, stored as `{query, should_trigger}`. Negatives should be **near misses** that share keywords but need a different tool, not obviously irrelevant queries. — [skill-creator SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/skill-creator/SKILL.md)
- Each query runs 3 times to estimate a trigger rate. Split: 60% train, 40% held-out test. The loop runs up to 5 iterations, and the best description is chosen by **test** score to avoid overfitting. Evals use the session's current model ID. — [skill-creator SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/skill-creator/SKILL.md)
- Guidance: Claude tends to **undertrigger**, so descriptions should be somewhat "pushy," and all "when to use" text belongs in the description, not the body. Claude consults skills only for tasks it cannot easily do alone, so simple one-step queries may not trigger even a matching skill. Trigger-eval queries should therefore be substantive. — [skill-creator SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/skill-creator/SKILL.md)
- Effectiveness evals: start with 2–3 realistic prompts in `evals/evals.json`. With-skill and baseline runs launch together, where the baseline is `without_skill` for a new skill or a snapshot `old_skill` when improving one. A grader agent writes `grading.json` with text, passed and evidence per assertion. Objective checks are scripted, and subjective qualities are judged qualitatively. — [skill-creator SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/skill-creator/SKILL.md)
- `aggregate_benchmark` reports pass rate, time and tokens as mean ± stddev per configuration, plus the delta between configurations. An analyst pass looks for **non-discriminating assertions** (they pass regardless of the skill), high-variance or flaky evals, and time/token tradeoffs. Optional extras are blind A/B comparison by an independent agent and an HTML viewer for human review. — [skill-creator SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/skill-creator/SKILL.md)
- The doc does not specify runs per benchmark configuration or exactly how trigger detection works. — [skill-creator SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/skill-creator/SKILL.md)
- Third-party report: the description optimizer moved from requiring an API key to `claude -p` subprocesses. — [SmartScope](https://smartscope.blog/en/generative-ai/claude/skill-creator-eval-pipeline-guide/)

**Anthropic best-practices doc (evaluation-driven development), guidance**
- Steps: run Claude without the skill to find gaps, build three scenarios that test those gaps, measure a baseline, write minimal instructions, then iterate. "There is not currently a built-in way to run these evaluations." The checklist asks for at least 3 evals and testing on Haiku, Sonnet and Opus. — [Anthropic best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- "Claude A / Claude B" loop: one instance authors the skill and a fresh instance uses it on real tasks. Watch for unexpected exploration paths, missed references, sections Claude keeps re-reading, and bundled files it never opens. — [Anthropic best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

**Superpowers (Jesse Vincent / Prime Radiant; first release Oct 2025), writing-skills method, practitioner**
- RED-GREEN-REFACTOR for skills. RED: run a pressure scenario on a subagent **without** the skill and record its rationalizations verbatim. GREEN: write a minimal skill and rerun. REFACTOR: close new loopholes and retest. "No skill without a failing test first." — [superpowers writing-skills SKILL.md](https://raw.githubusercontent.com/obra/superpowers/main/skills/writing-skills/SKILL.md)
- Pressure types are time, sunk cost, authority and exhaustion, with 3 or more combined per scenario. Success means the agent complies under maximum pressure. Repeated rationalizations become a "rationalization table" and a red-flags list. — [superpowers writing-skills SKILL.md](https://raw.githubusercontent.com/obra/superpowers/main/skills/writing-skills/SKILL.md)
- Each skill type has its own test target:

  | Skill type | Test target |
  |---|---|
  | Discipline | Compliance under stress |
  | Technique | Application to a new scenario |
  | Pattern | Recognizing when it applies, and when it doesn't |
  | Reference | Retrieval and correct use |

  — [superpowers writing-skills SKILL.md](https://raw.githubusercontent.com/obra/superpowers/main/skills/writing-skills/SKILL.md)
- Wording micro-tests: one fresh-context sample per call with a realistic system prompt, always a no-guidance control ("if the control doesn't show the failure, don't write the guidance"), and at least 5 reps per variant. Flagged matches are read by hand. — [superpowers writing-skills SKILL.md](https://raw.githubusercontent.com/obra/superpowers/main/skills/writing-skills/SKILL.md)
- Informal internal measurement, no numbers given: prohibition wording produced more unwanted content than positive-recipe wording, and trended worse than no guidance. Adding one nuance clause made output noisier. — [superpowers writing-skills SKILL.md](https://raw.githubusercontent.com/obra/superpowers/main/skills/writing-skills/SKILL.md)
- Skills that involve subagents are tested in real headless Claude Code sessions and checked through transcripts. — [superpowers testing docs (mirror)](https://gitea.com/TristanSun/superpowers/src/branch/main/docs/testing.md)

**Selection accuracy as libraries grow, measured**
- *(snippet only)* arXiv 2601.04748: selection accuracy stays above 90% with 20 or fewer skills, degrades beyond 30, and falls to about 20% at 200. The authors attribute this mainly to semantic confusability between similar skills, and hierarchical routing helps. — [arXiv 2601.04748](https://arxiv.org/html/2601.04748v1)
- *(snippet only)* SkillCoach (arXiv 2607.01874) adds distractor skills until selection degrades:

  | Model | Degradation begins at |
  |---|---|
  | DeepSeek V4 Flash | about 26 distractors |
  | Gemini 3.1 Pro | about 45 distractors |
  | GPT-5.5 | about 55 distractors |
  | Opus 4.7 | about 194 distractors |

  — [arXiv 2607.01874](https://arxiv.org/pdf/2607.01874)
- Vercel measured non-invocation directly: no invocation in 56% of cases with default settings. — [Vercel blog](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals)
- OpenAI tells Codex authors to "test prompts against the skill description to confirm the right skill triggers." — [OpenAI Codex skills docs](https://learn.chatgpt.com/docs/build-skills)

### Inferences
- A complete test method needs four layers:
  1. Trigger precision and recall on labelled positives and near-miss negatives, with repeats.
  2. Task outcome with the skill force-loaded against a no-skill baseline, to separate "does it help when used" from "does it get used."
  3. End-to-end runs with natural triggering.
  4. A length-matched irrelevant-skill control (from Signal or Noise).
- Library-level tests matter as much as single-skill tests. Selection degrades with library size and similarity between skills, and the breakpoint depends on the model (roughly 26 to 194 distractors). Test the whole library at its intended size on each target model.
- Use repeats and report variance. Skill-creator uses 3 runs per trigger query, SkillsBench uses 5 trials, and superpowers uses 5 or more reps.

### Gaps
- No published numbers were found on how often skill-creator's description optimization improves trigger rates.
- No standard public trigger-eval dataset for SWE skills was found.

## 3. Official authoring best practices (Anthropic, Agent Skills spec, OpenAI Codex)

### Takeaway
The sources broadly agree:
- The description is the trigger. It should state what the skill does and when to use it, in specific keywords and third person, within a 1,024-character maximum.
- Keep SKILL.md short: under 500 lines, and under about 5,000 tokens per the spec.
- Push detail into reference files one level deep.
- Match the degree of freedom to how fragile the task is.
- Use scripts for deterministic or fragile operations.
- Build evals before writing, and test on every target model.

The sources diverge on whether the description should summarize the workflow (superpowers says no) and on how "pushy" it should be (Anthropic's skill-creator says lean pushy, OpenAI says state boundaries).

### Cited Findings

**Agent Skills spec (agentskills.io)**
- `name`: 1–64 characters, lowercase a-z, 0-9 and hyphens, no leading, trailing or double hyphens, and it must match the directory name. `description`: 1–1024 characters, saying what the skill does and when to use it, with keywords. — [agentskills.io spec](https://agentskills.io/specification)
- Optional fields: `license`, `compatibility` (at most 500 characters), `metadata` (string map), and `allowed-tools` (experimental). — [agentskills.io spec](https://agentskills.io/specification)
- Progressive disclosure has three tiers: metadata at about 100 tokens per skill, loaded at startup; the instruction body at under 5,000 tokens recommended; and resources loaded on demand. Keep SKILL.md under 500 lines, and file references one level deep. — [agentskills.io spec](https://agentskills.io/specification)
- `skills-ref validate ./my-skill` validates frontmatter and naming. — [agentskills.io spec](https://agentskills.io/specification)

**Anthropic, "Skill authoring best practices"**
- "Concise is key." The doc says "the context window is a public good," and authors should assume Claude is already smart and only add context it lacks. — [Anthropic best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- Degrees of freedom: high (prose heuristics) where many approaches are valid; medium (pseudocode or parameterized scripts) where a preferred pattern exists; low (exact scripts, "do not modify the command") for fragile operations. The doc's analogy is a narrow bridge versus an open field. — [Anthropic best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- Descriptions are written in the third person, are specific, and cover both what the skill does and when to use it. Claude chooses among "potentially 100+" skills from the description alone. Names: at most 64 characters, no "anthropic" or "claude", gerund form preferred (e.g. `processing-pdfs`), and no vague names like `helper` or `utils`. — [Anthropic best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- Keep the body under 500 lines. References go one level deep, because Claude may `head -100` nested files and miss content. Reference files longer than 100 lines get a table of contents. — [Anthropic best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- Workflows use copyable checklists and validate-fix-repeat feedback loops. For batch or destructive operations, use plan-validate-execute with verifiable intermediate files. — [Anthropic best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- Scripts should "solve, don't defer": handle errors in the script, document constants (no "voodoo constants"), state whether to run a script or read it, and prefer scripts for deterministic operations, since only their output consumes tokens. — [Anthropic best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- Anti-patterns to avoid:
  - time-sensitive information (move it to an "old patterns" section)
  - inconsistent terminology
  - offering too many options (give a default plus an escape hatch)
  - Windows paths
  - assuming packages are installed
  - unqualified MCP tool names (use `Server:tool`)

  — [Anthropic best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- Test with Haiku ("enough guidance?"), Sonnet, and Opus ("avoid over-explaining?"). "What works perfectly for Opus might need more detail for Haiku." — [Anthropic best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

**OpenAI Codex skills docs**
- Progressive disclosure: name, description and path are loaded first, and the full SKILL.md is read only when selected. **The initial skill list is capped at 2% of the context window, or 8,000 characters if the window size is unknown.** With many skills, Codex shortens descriptions first and may drop skills with a warning. The cap is configurable with `skills.max_context_tokens`, up to 10,000 tokens. — [OpenAI Codex skills docs](https://learn.chatgpt.com/docs/build-skills)
- Descriptions should be concise with clear scope and boundaries, say when the skill should **and should not** trigger, and front-load trigger words so the skill still matches if truncated. — [OpenAI Codex skills docs](https://learn.chatgpt.com/docs/build-skills)
- "Prefer instructions." Add scripts only for deterministic behavior or external tooling. The skill creator defaults to instruction-only. One job per skill. — [OpenAI Codex skills docs](https://learn.chatgpt.com/docs/build-skills)
- `agents/openai.yaml` can disable implicit invocation, leaving explicit `$skill` only. Skill locations are REPO (`.agents/skills` from the working directory up to the repo root), USER, ADMIN and SYSTEM. Duplicate names are not merged, and both can appear. — [OpenAI Codex skills docs](https://learn.chatgpt.com/docs/build-skills); [developers.openai.com](https://developers.openai.com/codex/skills)

**Superpowers ("Claude Search Optimization"), practitioner opinion**
- The description should say only when to use the skill, usually starting "Use when...", with symptoms, error messages and tool names. It should **not** summarize the workflow, because an agent may follow the summary instead of reading the skill. — [superpowers writing-skills SKILL.md](https://raw.githubusercontent.com/obra/superpowers/main/skills/writing-skills/SKILL.md)
- Match the form of the guidance to the failure: prohibitions and rationalization tables for rule violations, positive recipes for wrong output shape, template fields for omissions, and observable-condition conditionals for conditional behavior. — [superpowers writing-skills SKILL.md](https://raw.githubusercontent.com/obra/superpowers/main/skills/writing-skills/SKILL.md)

**Empirical support for some of this guidance**
- Conciseness: in SkillsBench, "comprehensive" skills score −2.9pp against +17–19pp for detailed or compact ones. — [arXiv HTML v1](https://arxiv.org/html/2602.12670v1)
- Minimal context: the AGENTS.md paper recommends "only minimal requirements." — [arXiv HTML](https://arxiv.org/html/2602.11988v1)
- Content type: Signal or Noise finds anti-pattern rules beat example-heavy content. — [arXiv abs](https://arxiv.org/abs/2608.23067)
- Compression: Vercel's 40KB to 8KB compression kept 100%. — [Vercel blog](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals)

### Inferences
- Anthropic's "examples pattern" guidance (input/output pairs) is partly in tension with the Signal or Noise finding that example-heavy content underperforms anti-pattern rules on web-dev. That is worth testing directly in our library.
- Codex's 2%/8,000-character cap means a large library will have its descriptions truncated silently. Front-loaded trigger words, and test runs at the full library size, matter for cross-agent portability.
- The "pushy description" advice (skill-creator) and the "state when NOT to trigger" advice (OpenAI) trade recall against precision. Trigger evals with near-miss negatives are how to settle it per skill.

### Gaps
- Anthropic gives no published measurement showing the 500-line or third-person rules improve outcomes. These are guidance.
- Anthropic's engineering blog launch post (Oct 2025) and Simon Willison's commentary were not fetched in this pass.

## 4. Known failure modes: no trigger, over-triggering, context bloat, conflicts, stale skills, security

### Takeaway
The best-measured failures are:
- **Undertriggering:** 56% never invoked in Vercel's eval.
- **Selection collapse or "shadowing" as libraries grow:** sharp drops beyond about 20–30 skills in one study, and up to a 21% performance drop at 202 skills in another, driven mainly by wrong selection rather than raw context size.
- **Distraction and cost:** up to 394% more tokens and a 1–4% Pass@2 loss on web-dev.
- **Security:** up to 80% attack success for prompt injection via skill files, and 13.4% of about 4,000 marketplace skills with critical issues.

### Cited Findings

**Not triggering**
- Vercel: the skill was not invoked in 56% of cases, and the default skill equalled the no-docs baseline at 53%. — [Vercel blog](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals)
- Anthropic says Claude tends to undertrigger, and simple tasks may not trigger a matching skill at all. — [skill-creator SKILL.md](https://raw.githubusercontent.com/anthropics/skills/main/skills/skill-creator/SKILL.md)

**Over-triggering or misdirection by an irrelevant skill**
- Length-matched irrelevant skills reproduce most of the loss for "length-distracted" models. — [arXiv 2608.23067](https://arxiv.org/abs/2608.23067)
- Forced invocation ("You MUST invoke the skill") made agents anchor on the docs and miss project context. — [Vercel blog](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals)
- Context files make agents explore and test more, adding steps and cost, with no gain in localization. — [arXiv 2602.11988](https://arxiv.org/html/2602.11988v1)

**Many skills: bloat, shadowing, confusability**
- SkillsBench: supplying 4 or more skills cuts the gain to +5.9pp, against about +18pp for 1–3. — [arXiv HTML v1](https://arxiv.org/html/2602.12670v1)
- *(snippet only)* "More Skills, Worse Agents? Skill Shadowing…" (Databricks; ICML 2026 listing) reports up to a 21% performance drop from a small helpful set to a 202-skill library. It attributes the drop mainly to **skill shadowing** (wrong selection). The context-overhead effect was "small and indistinguishable from zero." — [ICML 2026 listing](https://icml.cc/virtual/2026/77891); [OpenReview PDF (not accessible)](https://openreview.net/pdf/d0442bc35b36808ccd4a60602430b40597dff620.pdf)
- *(snippet only)* Selection accuracy falls from above 90% (20 or fewer skills) to about 20% (200 skills), driven by semantic confusability. Hierarchical routing helps. — [arXiv 2601.04748](https://arxiv.org/html/2601.04748v1)
- Codex truncates descriptions and can omit skills once the list exceeds 2% of context or 8,000 characters. — [OpenAI Codex skills docs](https://learn.chatgpt.com/docs/build-skills)

**Conflicting or duplicate skills**
- Codex does not merge same-named skills, and both can appear. — [OpenAI Codex skills docs](https://learn.chatgpt.com/docs/build-skills)
- Anthropic warns against inconsistent naming patterns within a collection. — [Anthropic best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

**Stale skills**
- Anthropic says to avoid time-sensitive information and to use a collapsed "old patterns" section. — [Anthropic best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- Skill rankings transfer weakly across models, so a skill validated on one model may not hold after a model change (inference from the reported finding). — [arXiv 2608.23067](https://arxiv.org/abs/2608.23067)
- Self-generated skills give no average benefit (−1.3pp), so auto-refreshing skills with the same model is not a reliable fix. — [arXiv HTML v1](https://arxiv.org/html/2602.12670v1)

**Security**
- SkillInject (arXiv 2602.20156, Schmotz, Beurer-Kellner, Abdelnabi, Andriushchenko; 23 Feb 2026): 202 injection-task pairs, ranging from obvious to subtle, context-dependent injections. Frontier models show **up to 80% attack success**, including data exfiltration, destructive actions and ransomware-like behavior. The authors say the problem "will not be solved through model scaling or simple input filtering." — [arXiv 2602.20156](https://arxiv.org/abs/2602.20156)
- *(snippet only)* Snyk ToxicSkills (vendor audit, 5 Feb 2026): of 3,984 skills from ClawHub and skills.sh, 13.4% had at least one critical issue and 36.82% had some security flaw. — [Snyk](https://snyk.io/de/blog/toxicskills-malicious-ai-agent-skills-clawhub/)
- *(snippet only)* Survey arXiv 2602.20867 describes the "ClawHavoc" campaign, in which nearly 1,200 malicious skills reached a major agent marketplace. — [arXiv 2602.20867](https://arxiv.org/abs/2602.20867v1)
- *(snippet only)* arXiv 2602.06547 builds the first labelled dataset of malicious skills found in the wild. It notes skills run with user privileges and are distributed with minimal vetting. — [arXiv 2602.06547](https://arxiv.org/pdf/2602.06547v2)
- *(snippet only)* The SkillJect attack hides malicious code in auxiliary scripts, while SKILL.md contains only a benign-looking instruction to run them. — [Promptfoo LM security DB](https://promptfoo.dev/lm-security-db/vuln/automated-stealth-skill-injection-1a4b312b/)

### Inferences
- A skill library test method should include:
  - trigger recall and precision with near-miss negatives
  - the library at full size, with similar or confusable skills present
  - a no-skill baseline, a force-loaded run, and a length-matched irrelevant-skill control
  - token and step cost alongside pass rate
  - repeats with variance
  - runs on each target model, including the small or local ones
  - a security review of bundled scripts, not just SKILL.md
- Similar skills should be merged or routed hierarchically. Confusability, not count alone, drives selection failure.

### Gaps
- No quantitative study of "stale" skills (drift after API or model updates) was found.
- No measured study of conflicting-instruction resolution between two loaded skills was found.
- The full texts of the Databricks shadowing paper and SkillCoach were not accessible or not read. Their numbers come from search snippets.

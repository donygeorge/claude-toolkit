# Learnings from Superpowers for Claude Toolkit — Idea Exploration

> **Status**: Reviewed
>
> **Created**: 2026-02-17
>
> **Depth**: normal
>
> **Research personas**: 4 (the-pragmatist, the-researcher, the-architect, the-critic)
>
> **Codex iterations**: 2 of 5

## Problem Statement

The [superpowers](https://github.com/obra/superpowers) framework (53K+ GitHub stars as of Feb 2026, accepted into Anthropic's official plugin marketplace Jan 2026) is the most widely-adopted Claude Code skills framework by star count. While claude-toolkit and superpowers take fundamentally different approaches — toolkit provides **configurable infrastructure** (hooks, config, CLI) while superpowers provides **behavioral methodology** (TDD, anti-rationalization, subagent orchestration) — there are specific learnings from superpowers that would improve the toolkit's skill effectiveness, upgrade resilience, and overall quality.

## Context

### Current State

Claude-toolkit has 12 skills, 16 hooks, 9 agents, three-tier settings merge, and 490+ tests. The toolkit excels at infrastructure: configurable guards, auto-approve, lifecycle management, stack detection, and manifest tracking.

However, a quality audit of existing skills reveals:

- Only **3 of 12 skills** have rationalization prevention (verify, fix, implement)
- Only **5 of 12 skills** have a "Critical Rules (READ FIRST)" section
- **2 skill descriptions** have the "Description Trap" (commit, conventions)
- **Extreme length variance**: 47 lines (conventions) to 1,617 lines (setup-toolkit) — a 34x range
- **Model-version coupling**: 5 skills hardcode model names in frontmatter; review-suite has model name tables
- **No skill behavior testing**: 490+ tests cover infrastructure but none verify skills actually change agent behavior

### Constraints

- Must not break existing `toolkit.toml` configs or consuming projects
- Simplicity first — only adopt ideas that demonstrably improve skill effectiveness
- Willing to add complexity for important capabilities
- All changes must remain generic (no project-specific content in skills)

### Goals

- Improve skill compliance rates (agent follows instructions more reliably)
- Improve upgrade resilience (skills survive model version changes)
- Address quality gaps identified in the skill audit
- Maintain the toolkit's configurable, infrastructure-first identity

## Approaches Evaluated

### A1: Behavioral Engineering

**Summary**: Extend rationalization prevention tables, iron laws, and forbidden language lists to skills that currently lack them.

**How it works**: Add concise (3-5 entry) rationalization prevention sections to solve, refine, and review-suite skills. Standardize the section name "Rationalization Prevention" across all skills. Keep tables focused on the highest-impact rationalizations specific to each skill's domain.

**Strengths**:

- Supported by related research: Meincke et al. 2025 (SSRN preprint, not yet peer-reviewed in a journal) showed persuasion techniques doubled LLM compliance with objectionable requests (72% vs 33%, p < .001, N=28,000). The application to skill compliance is an extrapolation — the study tested refusal bypass, not instruction following — but the mechanism (commitment, authority framing) is transferable.
- The toolkit already has the pattern in verify/fix — just needs extension to more skills
- Zero architectural change required

**Weaknesses**:

- Diminishing returns beyond 2-3 rules per prompt engineering research (elaborate tables may be token bloat)
- Rationalization tables need re-validation per model upgrade
- No controlled study specifically testing rationalization tables in coding agent contexts
- Evidence is indirect — Meincke et al. tested a different compliance domain

**Key technologies**: Pure Markdown skill authoring — no code changes

**Estimated complexity**: Low

### A2: Workflow Enforcement

**Summary**: Add configurable TDD-first mode and a spec-compliance review preset. Skip git worktree isolation.

**How it works**: Add `tdd_enforcement = "strict" | "guided" | "off"` to `toolkit.toml`. In strict mode, the implement skill's milestone template requires test file creation before implementation. Add a `spec-first` review preset to review-suite that runs the reviewer agent first (focused on spec compliance), then feeds findings to subsequent agents.

**Strengths**:

- DORA 2025 report: characterizes TDD + AI as an amplifier combination, describing foundational practices as increasingly important in AI-assisted development ([source](https://dora.dev/research/2025/dora-report/))
- TDD reduces defect density 40-90% (meta-analysis)
- Two-stage review catches different classes of bugs (spec drift vs code quality)
- Both improvements are opt-in, preserving the toolkit's configurable philosophy

**Weaknesses**:

- No controlled study of "AI agent with TDD enforcement vs without"
- Mandatory TDD is inappropriate for prototyping, data science, config work (a significant portion of dev work, though no precise figure is available)
- Two-stage review approximately doubles token cost for reviews
- The toolkit already has a de facto three-stage review (Codex -> Reviewer -> /verify)

**Key technologies**: toolkit.toml config, skill template modifications

**Estimated complexity**: Medium

### A3: Skill Design Methodology

**Summary**: Audit skill descriptions for the Description Trap, add adversarial pressure testing for top skills, and document skill design principles.

**How it works**: Fix the 2 skill descriptions that describe workflow instead of trigger conditions (commit, conventions). Build a lightweight pressure test framework using Codex MCP for the top 5 skills. Document the Description Trap rule, commitment principle, and concise rationalization pattern as skill design conventions.

**Strengths**:

- The Description Trap is a documented issue in superpowers (v4 blog post): when descriptions summarize workflow, Claude follows the short description instead of reading the full skill. Note: this was observed with specific model versions and may vary.
- Pressure testing fills the toolkit's only genuine testing gap (no skill behavior tests exist)
- Related research supports information positioning: Liu et al. 2024 ("Lost in the Middle", MIT Press/TACL) showed 30%+ performance degradation for information in the middle of long contexts. This is about retrieval from long contexts, not directly about skill descriptions, but suggests front-loading critical rules matters.

**Weaknesses**:

- Pressure testing is slow and expensive (each test is a full Claude invocation)
- Must be re-run per model upgrade — ongoing maintenance cost
- The Description Trap finding may be model-version-specific (emerged with Opus 4.5)
- Lower-cost alternatives exist: skill linting (heuristic checks on description format, section presence, length) and golden prompt tests (synthetic task suites with expected outputs) could provide partial coverage without full Claude invocations

**Key technologies**: Codex MCP for pressure tests, Markdown for documentation

**Estimated complexity**: Low (description audit) to Medium-High (pressure testing framework)

### A4: Distribution & Onboarding (REJECTED)

**Summary**: Evaluate Claude Code plugin marketplace as additional distribution channel.

**Why rejected:**

- Architectural mismatch: toolkit's deep integration model (hooks, settings merge, config cache) doesn't fit the marketplace's atomic plugin model
- Anthropic dependency risk: January 2026 lockdown incident broke developer trust ([source](https://byteiota.com/anthropic-claude-code-lockdown-the-developer-trust-crisis/))
- Plugin security concerns: PromptArmor published research on marketplace plugin hijacking ([source](https://www.promptarmor.com/resources/hijacking-claude-code-via-injected-marketplace-plugins))
- The toolkit's git subtree model provides more control and offline capability
- Splitting the monorepo into marketplace-compatible packages would fragment the manifest system

**Lighter alternatives considered but deferred**: A read-only marketplace wrapper (skills-only export) or a `toolkit.sh export-plugin` command could provide marketplace discoverability without full migration. These are worth revisiting if marketplace adoption becomes a gating factor for the toolkit's growth.

## Evaluation Matrix

| Dimension | A1: Behavioral Engineering | A2: Workflow Enforcement | A3: Skill Design Methodology |
| --------- | --- | --- | --- |
| Implementation complexity | Low | Medium | Low to Medium-High |
| Evidence strength | MEDIUM (indirect: Meincke et al. tested different domain) | MEDIUM (DORA is observational, not experimental) | MEDIUM (Description Trap is practitioner-observed) |
| Integration fit | EXCELLENT (extends existing) | GOOD (config-driven) | EXCELLENT (audit + testing) |
| Token cost impact | Low (+3-5 entries/skill) | Medium (two-stage review) | Negligible |
| Maintenance burden | Medium (re-validate per model) | Low | Medium (re-run tests per model) |
| Reversibility | High (edit SKILL.md) | High (config toggle) | High |
| Upgrade resilience impact | Medium | Low | HIGH |

*Note: Evidence ratings are calibrated honestly. No approach has direct experimental evidence in the AI coding agent context. All ratings reflect transferability from related research domains.*

## Persona Perspectives

### Where Personas Agreed

**Universal consensus (4/4):**

- Skip git worktree isolation — documented practical problems include 9.82 GB disk usage in 20 minutes for a 2GB codebase ([source](https://devcenter.upsun.com/posts/git-worktrees-for-parallel-ai-coding-agents/)), port conflicts on common ports (3000, 5432, 8080), stale worktree accumulation, and broken devcontainer integration. Additionally, the toolkit's `_config.sh`, `$CLAUDE_PROJECT_DIR`, and settings paths all assume a single working tree.
- Description Trap audit is a free win — 1 hour, zero risk, immediate fix
- TDD should be opt-in, not mandatory — configurable via toolkit.toml
- The toolkit already implements most superpowers patterns under different names — the gap is coverage, not capability

**Strong consensus (3/4):**

- Extend rationalization prevention to solve, refine, review-suite — but keep concise (3-5 entries, not 15)
- Skill pressure testing fills the biggest genuine gap — the only pattern that addresses an architectural hole

### Where Personas Disagreed

**Two-stage review:**

- the-researcher: Evidence supports it (multi-agent review shows 81% quality improvement)
- the-pragmatist: Clear structural improvement, add as a preset
- the-architect: Toolkit already has three-stage review — not transformative
- the-critic: Doubles token cost for marginal benefit

**Resolution**: Add as an optional `spec-first` preset, not a default change

**Rationalization table scope:**

- the-researcher: Apply broadly, evidence is strong
- the-critic: Diminishing returns after 2-3 rules; simple "NEVER skip X" is nearly as effective
- the-architect: Already exists in 3 skills, just extend to 3 more

**Resolution**: Concise tables (3-5 entries) for high-stakes skills only (solve, refine, review-suite)

## Recommendation

**Recommended approach**: A hybrid of A1 + A3, with selective A2 elements

**Confidence**: Medium-High

**Reasoning**: Behavioral engineering (A1) and skill design improvements (A3) are the highest-ROI changes based on converging evidence from related research domains (persuasion studies, context positioning, practitioner observations). They are low complexity and fit the existing architecture without modification. Workflow enforcement (A2) adds value as opt-in features. Distribution changes (A4) rejected due to architecture mismatch and dependency risk.

**Key trade-off accepted**: Skipping mandatory TDD, git worktrees, and marketplace migration in favor of simpler, higher-certainty improvements.

## Prioritized Implementation Plan

| Priority | Improvement | Effort | Acceptance Criteria |
| -------- | ----------- | ------ | ------------------- |
| **P1** | Description Trap audit — fix commit and conventions descriptions | ~1 hour | All 12 skill descriptions use "Use when..." trigger-condition format |
| **P2** | Extend rationalization prevention to solve, refine, review-suite (3-5 entries each) | ~2-3 hours | 6/12 skills have rationalization prevention (up from 3/12); all tables have 3-5 domain-specific entries |
| **P3** | Standardize "Critical Rules (READ FIRST)" across all workflow skills | ~2-3 hours | 8/12 skills have a "Critical Rules (READ FIRST)" section (up from 5/12); utility/reference skills exempt |
| **P4** | Configurable TDD-first mode via toolkit.toml | ~2-3 hours | `tdd_enforcement` config key works with `strict\|guided\|off`; implement skill reads config; existing behavior unchanged when unset |
| **P5** | Add `spec-first` review preset to review-suite | ~2-3 hours | New `spec-first` preset runs reviewer first, passes findings to subsequent agents; existing presets unaffected |
| **P6** | Improve upgrade resilience — extract model names to config, fix year references | ~2-3 hours | No hardcoded model names in skill bodies; `model:` frontmatter uses config-driven mapping; year references use dynamic current-year |
| **P7** | Skill quality linting + adversarial pressure tests | ~1-2 days | Lint script checks: description format, critical rules presence, rationalization section, length budget; pressure tests for implement, verify, fix |
| **P8** | Document skill design principles (commitment principle, description trap, rationalization prevention) | ~2-3 hours | New `docs/skill-design-guide.md` covering all principles with examples |

### Dependencies

- P1-P3 are independent and can be done in parallel
- P4 depends on `_config.sh` and `generate-config-cache.py` supporting new config key
- P5 depends on understanding current review-suite execution flow
- P6 depends on deciding the model mapping approach (P6 open question)
- P7 has two tiers: lint script (low effort, do first) + pressure tests (high effort, do second)
- P8 should be done last to capture lessons from P1-P7

### Missing alternatives noted (from Codex review)

- **Skill linting**: A heuristic lint script (check description format, section presence, length budget) could provide 80% of pressure testing's value at 5% of the cost. Recommended as P7 tier 1.
- **Length budgeting**: Address the 47-1617 line variance by setting soft targets (e.g., <200 lines for workflow skills, <400 for orchestration skills). Consider splitting setup-toolkit.
- **Structured frontmatter schema**: Standardize YAML frontmatter fields across all skills to enable automated validation.

## Research Findings

### Academic Evidence (Tier 1 — related but indirect)

- **Meincke et al. 2025** ("Call Me A Jerk", SSRN #5357179, preprint): Persuasion principles more than doubled LLM compliance with objectionable requests (72% vs 33.3%, p < .001, N=28,000). *Caveat*: this tested refusal bypass, not instruction-following in coding agents. The mechanism (commitment, authority framing) is transferable but the exact compliance improvement will differ.
- **Liu et al. 2024** ("Lost in the Middle", MIT Press/TACL, peer-reviewed): LLMs show 30%+ performance degradation for information in the middle of long contexts. *Caveat*: this is about retrieval from long contexts, not about short descriptions vs full skill bodies. Supports front-loading critical rules but does not directly validate the Description Trap.
- **DORA 2025** (Google, observational survey): AI acts as an amplifier — strengthens good practices, exposes weaknesses. TDD singled out as "more critical than ever" in AI-assisted development. *Caveat*: observational, not experimental; reports correlation between TDD adoption and AI-assisted development quality.

### Industry Evidence (Tier 2 — surveys and practitioner reports)

- **Qodo State of AI Code Quality 2025** (industry survey, 400 companies): Multi-agent review systems show 81% quality improvement. *Caveat*: self-reported; "quality improvement" is subjectively defined.
- **Context gap is #1 issue** (Qodo survey): 65% of developers cite missing context as the top problem, more than hallucinations. Supports the toolkit's context injection hooks.
- **TDD reduces defect density 40-90%** across meta-analyses (IBM, Microsoft studies). These predate AI coding agents; the specific improvement with LLM-generated code is unknown.

### Superpowers-Specific Findings

- **Self-grading**: Superpowers' own grading system rates its core "using-superpowers" meta-skill 68/100 (D grade). The meta-coordination layer is the weakest link.
- **22K token overhead**: All skills preloaded at session start consume 11% of the 200K context window before any work begins.
- **Model fragility**: Issue #178 — brainstorming skill broke after Claude 4.0 upgrade. Elaborate model-specific prompts have more breakage surface area.
- **Subagent gap**: Issue #237 — subagents don't inherit the methodology (SessionStart injection doesn't propagate). This is superpowers' biggest architectural weakness.

### Skill Quality Audit Findings

| Skill | Rating | Rationalization Prevention | Critical Rules | Description Quality | Upgrade Resilience |
| ----- | ------ | --- | --- | --- | --- |
| verify | A | Excellent (10-row table + forbidden language) | Strong | Good | Good |
| fix | A- | Good (7-row table + 3-Fix Rule) | Moderate | Good | Excellent |
| commit | A- | N/A (narrow scope) | Good | **TRAP** (describes workflow) | Excellent |
| implement | B | Partial (forbidden language only) | Strong | Good | Mixed (MCP coupling) |
| conventions | B+ | N/A (reference skill) | N/A | **TRAP** (describes function) | Excellent |
| scope-resolver | B+ | N/A (utility skill) | N/A | Good | Good |
| plan | B | None | Good | Good | Mixed (MCP coupling) |
| review-suite | B | None (structural anti-rationalization only) | Weak | Good | Mixed (model name tables) |
| solve | B- | Weak (3-Fix Rule only) | Weak | Good | Good |
| brainstorm | B- | None | Good | Good | Mixed (year references) |
| refine | B- | None | Weak | Good | Mixed |
| setup-toolkit | C+ | None | Weak | Mixed | Mixed |

**Common weaknesses**: Inconsistent rationalization prevention (3/12), inconsistent critical rules framing (5/12), 2 Description Trap violations, extreme length variance (47-1617 lines), model-version coupling in 5 skills.

## Risks and Open Questions

| Risk | Severity | Mitigation |
| ---- | -------- | ---------- |
| Model upgrades invalidate rationalization patterns | Medium | Keep tables concise (3-5 entries); easier to update |
| TDD enforcement frustrates prototyping workflows | Low | Opt-in via config; default off |
| Pressure testing is expensive and non-deterministic | Medium | Use Codex MCP (cheaper); focus on top 5 skills |
| Two-stage review doubles token cost | Low | Optional preset, not default |
| Skill length bloat from adding sections | Low | Keep entries concise; audit for bloat |

### Open Questions

- Should the `model:` frontmatter field in skills be replaced with a configurable mapping in `toolkit.toml`?
- Would splitting setup-toolkit into 2-3 separate skills (setup, update, contribute) improve quality?
- How often do model upgrades actually break skill behavior in practice? (Need data from pressure tests)
- Should the commitment principle be explicitly used in skill design (start with easy instruction, then escalate)?

## Next Steps

1. Run `/plan toolkit-vs-superpowers` to create a detailed implementation plan from this idea doc
2. Start with P1 (Description Trap audit) and P2 (rationalization prevention extension) — both are low-risk, immediate wins
3. Design the pressure test framework (P7) as a separate spike

## Sources

### Academic / Peer-Reviewed

- [Meincke et al. 2025 — "Call Me A Jerk" (SSRN)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5357179) — Wharton, 28K conversations
- [Liu et al. 2024 — "Lost in the Middle" (MIT Press/TACL)](https://direct.mit.edu/tacl/article/doi/10.1162/tacl_a_00638/119630/) — Stanford/MIT
- [NAACL 2025 — LLM Robustness to Prompt Format](https://aclanthology.org/2025.naacl-srw.51.pdf)

### Industry Reports

- [DORA 2025 — State of AI-assisted Software Development](https://dora.dev/research/2025/dora-report/)
- [Qodo — State of AI Code Quality 2025](https://www.qodo.ai/reports/state-of-ai-code-quality/)
- [Anthropic — Demystifying Evals for AI Agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)

### Superpowers Project

- [obra/superpowers — GitHub](https://github.com/obra/superpowers)
- [Superpowers blog — October 2025](https://blog.fsck.com/2025/10/09/superpowers/)
- [Superpowers 4 blog — December 2025](https://blog.fsck.com/2025/12/18/superpowers-4/)
- [Issue #237 — Subagent context loss](https://github.com/obra/superpowers/issues/237)
- [Issue #178 — Brainstorming broke after Claude 4.0](https://github.com/obra/superpowers/issues/178)
- [Issue #190 — 22K token overhead](https://github.com/obra/superpowers/issues/190)
- [Issue #202 — Using-superpowers graded 68/100](https://github.com/obra/superpowers/issues/202)

### Community & Practitioner

- [Simon Willison's coverage](https://simonwillison.net/2025/Oct/10/superpowers/)
- [Richard Porter — Shipping big features with confidence](https://richardporter.dev/blog/superpowers-plugin-claude-code-big-features)
- [Dev Genius — Superpowers explained](https://blog.devgenius.io/superpowers-explained-the-claude-plugin-that-enforces-tdd-subagents-and-planning-c7fe698c3b82)
- [TDD Guard research](https://nizar.se/tdd-guard-for-claude-code/)
- [PromptArmor — Plugin hijacking research](https://www.promptarmor.com/resources/hijacking-claude-code-via-injected-marketplace-plugins)
- [Git worktree practical problems](https://devcenter.upsun.com/posts/git-worktrees-for-parallel-ai-coding-agents/)
- [Prompt complexity diminishing returns (Lakera 2026)](https://www.lakera.ai/blog/prompt-engineering-guide)

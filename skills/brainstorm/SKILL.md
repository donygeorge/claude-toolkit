---
name: brainstorm
description: Use when exploring a new idea, technology choice, or design problem before planning.
argument-hint: '"topic" [--quick] [--depth shallow|normal|deep] [--gemini]'
user-invocable: true
model: opus
---

# Brainstorm Skill

Structured idea exploration and research before planning. Spawns a team of persona-based research agents that investigate approaches from different angles, evaluates trade-offs, and produces a documented recommendation.

**Output**: Idea documents are saved to `docs/ideas/<topic-slug>.md` in a format designed to feed into the `/plan` skill.

## Aliases

```yaml
aliases:
  /brainstorm: /brainstorm
  /explore: /brainstorm
  /ideate: /brainstorm

defaults:
  depth: normal
  output_dir: docs/ideas
  codex_iterations: 5
```

## Usage

### Slash Commands

```bash
/brainstorm "real-time updates"               # Standard brainstorm (normal depth)
/brainstorm "auth system" --depth deep         # Deep research with more agents
/brainstorm "caching strategy" --quick         # Quick single-agent exploration
/explore "dark mode implementation"            # Alias for /brainstorm
/brainstorm "state management" --gemini        # Include Gemini second opinion
/brainstorm "API redesign" --no-commit         # Generate doc without committing
```

### Natural Language

```text
"brainstorm approaches for real-time notifications"
"explore options for database migration"
"research the best way to add authentication"
"I need to think through our caching strategy"
```

## Flags

| Flag | Description | Default |
| ---- | ----------- | ------- |
| `<topic>` | Required. The idea, problem, or domain to explore | -- |
| `--quick` | Alias for `--depth shallow`. Single-agent, no team. | off |
| `--depth <level>` | `shallow` / `normal` / `deep` | `normal` |
| `--gemini` | Include a Gemini second-opinion persona in the team | off |
| `--no-commit` | Generate the idea doc but do not commit it | off |

## Depth Modes

| Depth | Team? | Max personas | Codex iters | Use case |
| ----- | ----- | ------------ | ----------- | -------- |
| `shallow` | No | 0 (orchestrator only) | 2 | Quick exploration, simple topics |
| `normal` | Yes | 3-4 | 5 | Standard brainstorming |
| `deep` | Yes | 5-6 | 8 | Complex multi-domain research |

## Critical Rules (READ FIRST)

| Rule | Description |
| ---- | ----------- |
| **1. Research only** | This skill produces idea documents. Do NOT write any implementation code. |
| **2. Ask before spending compute** | Present the research plan to the user and get approval before spawning any team agents. |
| **3. Current sources only** | ALWAYS include "2025" or "2026" in WebSearch queries. Discard information older than 2024 unless it represents fundamental principles. |
| **4. User input is the most valuable signal** | Ask generously at checkpoints. Brainstorming is collaborative — don't guess when you can ask. |
| **5. Generic skill** | No project-specific content in this file. Persona prompts must be generic. |
| **6. No time estimates** | Focus on what and why, not when. |

---

## Execution Flow

### Phase 0: Parse & Clarify

**Before doing ANY research:**

1. Parse the topic from the user's input. Extract any flags (`--quick`, `--depth`, `--gemini`, `--no-commit`).
2. Slugify the topic for file naming: lowercase, hyphens, no special characters (e.g., "Real-Time Updates" → `real-time-updates`).
3. Check if `docs/ideas/<topic-slug>.md` already exists. If so, ask: "An existing idea doc was found. Resume and extend it, or start fresh?"
4. Ask **Checkpoint 1** questions. Use two rounds of AskUserQuestion (up to 7 questions total). Reduce questions if the topic is already very specific and clear.

**Checkpoint 1 — Scope & Goals:**

Round 1 (AskUserQuestion, up to 4 questions):

- What problem are you trying to solve?
- What's the context? (new project / existing feature / architecture decision / technology choice)
- Any hard constraints? (tech stack, timeline, platform, team size)
- What does success look like?

Round 2 (AskUserQuestion, up to 3 more):

- Are there approaches you've already considered or ruled out?
- Who are the stakeholders / who benefits from this?
- Any related prior art in the project or team experience?

Wait for all answers before proceeding.

### Phase 1: Reconnaissance

The orchestrator does quick preliminary research BEFORE spawning any agents. This informs agent selection and approach generation.

1. **Codebase scan** — Use Grep/Glob/Read to find anything related to the topic:
   - Existing implementations or related features
   - Technology already in use that is relevant
   - Related docs in `docs/plans/` or `docs/ideas/`
   - Configuration, dependencies, and patterns

2. **Quick web search** — Run 2-3 WebSearch queries with the current year:
   - `"<topic> best practices 2025 2026"`
   - `"<topic> comparison approaches"`
   - `"<topic> <detected-stack> implementation"` (using stacks from project config)

3. **Topic classification** — Classify the topic into one or more domains:

| Domain | Triggers |
| ------ | -------- |
| `architecture` | System design, scaling, infrastructure, microservices, data flow |
| `technology` | Library choice, framework, language, database, tool selection |
| `product` | User features, UX flows, business logic, monetization |
| `algorithm` | Data structures, ML models, optimization, performance tuning |
| `integration` | APIs, third-party services, authentication, data pipelines |
| `devops` | CI/CD, deployment, monitoring, infrastructure-as-code |

4. **Generate 2-4 candidate approaches** based on reconnaissance findings. Each approach should be a distinct strategy with a name and 1-2 sentence summary.

5. **Select personas** dynamically based on topic classification and depth (see Persona Selection below).

### Phase 2: Present Research Plan

**This is a critical user checkpoint.** Before spending compute on agents, present the plan and get approval.

Display a structured summary:

```text
## Brainstorm Plan: <topic>

**Domains identified**: architecture, technology
**Depth**: normal (3-4 research personas)

**Candidate approaches to investigate**:
1. A1: <approach name> — <brief description>
2. A2: <approach name> — <brief description>
3. A3: <approach name> — <brief description>

**Research personas I will spawn**:
- the-pragmatist: Will research proven solutions and community adoption
- the-innovator: Will research cutting-edge approaches and latest trends
- the-architect: Will analyze system design and codebase integration

**Codebase context found**:
- <relevant files/patterns found in Phase 1>
```

Then ask **Checkpoint 2** questions:

Round 1 (AskUserQuestion, up to 4 questions):

- Here are the candidate approaches — add, remove, or adjust any?
- These are the research personas I'll spawn — adjust the team?
- Any specific questions you want the team to investigate?
- Depth looks right? (show current setting)

Round 2 (AskUserQuestion, up to 3 more):

- Any particular libraries, tools, or patterns you want evaluated?
- Priorities: what matters most? (performance / simplicity / speed-to-ship / scalability / DX)
- Any competing products or projects we should look at?

Incorporate user feedback. Adjust approaches, personas, and depth as requested.

### Phase 3: Create Team & Spawn Personas

**Skip this phase entirely if `--quick` / `shallow` depth.** In shallow mode, the orchestrator does all research itself (single-agent mode).

1. Create the team:

```text
TeamCreate:
  team_name: "brainstorm-<topic-slug>"
  description: "Exploring: <topic>"
```

2. Spawn each selected persona via the Task tool:

```text
Task:
  team_name: "brainstorm-<topic-slug>"
  name: "<persona-name>"
  subagent_type: "general-purpose"
  prompt: <persona prompt with topic, approaches, context, and format>
```

3. Each persona's prompt MUST include:
   - Their personality and thinking style (see Persona Catalog below)
   - The topic and candidate approaches to investigate
   - Context from Phase 1 (codebase findings, initial web research)
   - User's answers from Phase 0 (constraints, goals, priorities)
   - Instruction: "Always include 2025 or 2026 in your WebSearch queries"
   - The report format they should follow (see Persona Report Format)
   - Instruction: "Send your report back via SendMessage when complete"

### Phase 4: Monitor & Coordinate

1. **Receive persona reports** — Messages from teammates are delivered automatically. Wait for all personas to report.

2. **Mid-research redirect** — If you notice:
   - Two personas are researching the same thing → redirect one to a different angle via SendMessage
   - An approach is clearly unviable based on early findings → tell relevant persona to pivot
   - A persona found something surprising → share it with other personas for reaction

3. **Ad-hoc user questions** — If research reveals something the user should know about (a surprising constraint, a major fork, or a need for domain context), ask the user immediately. Do not wait for a checkpoint.

4. **Collect all reports** into a synthesis workspace.

### Phase 5: Synthesis

The orchestrator (not agents) synthesizes all persona findings.

1. Read all persona reports.

2. For each candidate approach, build an **evaluation matrix**:

| Dimension | A1: Name | A2: Name | A3: Name |
| --------- | -------- | -------- | -------- |
| Implementation complexity | Low/Med/High | ... | ... |
| Operational complexity | ... | ... | ... |
| Scalability | ... | ... | ... |
| Ecosystem maturity | ... | ... | ... |
| Team familiarity | ... | ... | ... |
| Maintenance burden | ... | ... | ... |
| Reversibility | ... | ... | ... |
| Cost | ... | ... | ... |

3. Identify **where personas agreed** and **where they disagreed**. The disagreements are especially valuable — they surface real trade-offs.

4. Determine the **recommended approach** with confidence level and reasoning.

5. Write the initial draft of the idea document to `docs/ideas/<topic-slug>.md`.

### Phase 6: User Review

Present the synthesis to the user. Highlight persona disagreements.

```text
## Synthesis Complete

**Recommended approach**: A2: <name>
**Confidence**: Medium
**Reasoning**: <brief justification>

**Key tensions**:
- the-pragmatist recommends A1 (proven, lower risk)
- the-innovator recommends A3 (better long-term, but newer)
- the-architect says A2 fits the codebase best

**Evaluation matrix**: <show table>
```

Then ask **Checkpoint 3** questions:

Round 1 (AskUserQuestion, up to 4 questions):

- Does the recommended approach feel right?
- Want deeper research on any specific approach?
- Any angles or considerations I missed?
- Ready to finalize, or another round?

Round 2 (AskUserQuestion, up to 3 more — if user chose "one more round"):

- What specific aspect needs more depth?
- Should I adjust the evaluation criteria?
- Any new constraints or preferences based on what you've seen?

If the user wants deeper research on a specific approach, spawn a single focused follow-up persona (via Task, not a full team cycle).

### Phase 7: Codex Feedback Loop

Same pattern as the `/plan` skill's Phase 2.

1. Read the draft idea document.
2. Send to Codex for review:

```text
mcp__codex__codex:
  approval-policy: "never"
  prompt: "Review this idea exploration document for:
    1. Completeness — are all approaches fairly evaluated?
    2. Balanced analysis — any bias toward one approach?
    3. Missing alternatives — obvious approaches not considered?
    4. Research gaps — claims without evidence?
    5. Actionability — can someone use this to start planning?
    Start with ISSUES: if you find problems, or SOLID: if the doc is ready."
```

3. Loop rules:

| Rule | Value |
| ---- | ----- |
| Maximum iterations | 2 (shallow) / 5 (normal) / 8 (deep) |
| Stop early when | Response starts with "SOLID:" |
| Continue when | Response starts with "ISSUES:" |

4. Incorporate feedback and regenerate on each iteration.

5. If Codex is unavailable: skip with note "Codex unavailable — manual review recommended."

### Phase 8: Finalize & Commit

1. **Shutdown the team** (if one was created):
   - Send shutdown request to each active persona via SendMessage
   - Wait for shutdown confirmations
   - Call TeamDelete to clean up team files

2. **Write the final idea document** to `docs/ideas/<topic-slug>.md`.

3. **Commit** (unless `--no-commit`):
   - Create `docs/ideas/` directory if it does not exist
   - Stage `docs/ideas/<topic-slug>.md`
   - Write commit message to a temp file
   - Commit with `git commit -F <file>` (not heredoc — per toolkit convention)
   - Message format: `Add idea exploration: <topic>`

4. **Present final summary**:

```text
## Brainstorm Complete

**Topic**: <topic>
**Output**: docs/ideas/<topic-slug>.md
**Approaches evaluated**: 3
**Recommended**: A2: <name> (Medium confidence)
**Research personas used**: 3 (the-pragmatist, the-innovator, the-architect)
**Codex iterations**: 4 of 5

To create an implementation plan from this idea:
  /plan <topic-slug>
```

---

## Persona-Based Agent Team

Instead of functional roles, the team uses **distinct personas** that bring different thinking styles. This creates natural tension and diverse perspectives — essential for good brainstorming.

Inspired by divergent thinking frameworks, each persona has a personality, bias, and research style. The natural disagreements between personas surface real trade-offs that a single-perspective analysis would miss.

### Persona Catalog

All personas are spawned as `general-purpose` subagent_type (they need WebSearch, WebFetch, context7, Read, Grep, Glob, and SendMessage).

#### the-pragmatist

**Thinking style**: Conservative, risk-aware, simplicity-focused

**Key question**: "What's the simplest thing that actually works in production?"

**Research focus**:

- Battle-tested solutions with proven track records
- Community adoption metrics (GitHub stars, npm/PyPI downloads, StackOverflow activity)
- Maintenance costs and long-term support outlook
- Known issues, gotchas, and migration stories from real users
- StackOverflow questions and GitHub issues for pain points

**Bias**: Prefers proven over novel. Will push back on complexity.

#### the-innovator

**Thinking style**: Forward-looking, trend-chasing, possibility-focused

**Key question**: "What would the ideal solution look like if we had no constraints?"

**Research focus**:

- Cutting-edge approaches and emerging patterns (2025-2026)
- Recent conference talks, blog posts, and technical articles
- New libraries and frameworks gaining traction
- Where the ecosystem is heading (roadmaps, RFCs, proposals)
- What industry leaders and thought leaders are recommending

**Bias**: Prefers novel over proven. Will push for the future-facing option.

#### the-critic

**Thinking style**: Skeptical, adversarial, devil's advocate

**Key question**: "Why would this fail? What's the hidden cost?"

**Research focus**:

- Failure modes and post-mortems from similar approaches
- Hidden costs, second-order effects, and technical debt risks
- Scalability limits and performance bottlenecks
- Lock-in risks and reversibility concerns
- What people complain about after choosing each approach

**Bias**: Finds problems in everything. Will challenge the "obvious" choice.

#### the-user-advocate

**Thinking style**: Empathetic, experience-focused, user-centric

**Key question**: "Would someone actually enjoy using this?"

**Research focus**:

- UX patterns and user experience best practices
- Developer experience (if the audience is developers)
- Adoption friction and learning curves
- Accessibility considerations
- How competitors handle the same user need

**Bias**: Prioritizes user experience over technical elegance.

#### the-architect

**Thinking style**: Systems-thinking, structural, integration-focused

**Key question**: "How does this compose with what already exists?"

**Research focus**:

- Design patterns that apply to this problem
- How each approach integrates with the existing codebase
- Data flow and state management implications
- Scalability characteristics and architectural limits
- Separation of concerns and modularity

**Bias**: Prioritizes clean architecture and long-term maintainability.

#### the-researcher

**Thinking style**: Data-driven, thorough, evidence-focused

**Key question**: "What does the evidence actually say?"

**Research focus**:

- Benchmarks and performance comparisons
- Case studies from similar-scale projects
- Academic papers and industry reports
- Library comparison via context7 MCP tools (versions, docs, API surface)
- Quantitative data: adoption rates, bug counts, release frequency

**Bias**: Prioritizes evidence over opinion. Will flag unsubstantiated claims.

### Persona Selection Algorithm

```text
FUNCTION select_personas(domains, approaches, depth, flags):
    personas = []
    budget = {shallow: 0, normal: 4, deep: 6}[depth]

    IF depth == "shallow":
        RETURN []  # orchestrator handles everything

    # Step 1: Core trio — always included in normal and deep
    # the-pragmatist + the-innovator create productive tension
    # the-researcher provides evidence-based depth (deep research is the skill's core value)
    personas.append("the-pragmatist")
    personas.append("the-innovator")
    personas.append("the-researcher")

    # Step 2: Add the-architect when system design or codebase integration matters
    # (most topics benefit from architectural perspective)
    IF "architecture" IN domains OR "integration" IN domains OR "devops" IN domains:
        personas.append("the-architect")
    ELIF depth == "deep":
        personas.append("the-architect")  # always include in deep mode

    # Step 3: Add the-critic if multiple approaches need challenging
    IF len(approaches) >= 2 AND len(personas) < budget:
        personas.append("the-critic")

    # Step 4: Add domain-contextual persona if budget allows
    IF "product" IN domains AND "the-user-advocate" NOT IN personas AND len(personas) < budget:
        personas.append("the-user-advocate")

    # Step 5: In deep mode, fill remaining slots
    IF depth == "deep":
        FOR p IN ["the-critic", "the-user-advocate", "the-architect"]:
            IF p NOT IN personas AND len(personas) < budget:
                personas.append(p)

    # Step 6: Add gemini if flagged or deep mode
    IF flags.gemini OR depth == "deep":
        IF len(personas) < budget:
            personas.append("gemini-consultant")

    # Step 7: Cap at budget
    RETURN personas[:budget]
```

**Normal mode (budget 4)**: pragmatist + innovator + researcher + (architect or critic) = 3-4 personas
**Deep mode (budget 6)**: pragmatist + innovator + researcher + architect + critic + (user-advocate or gemini) = 5-6 personas

### Gemini Consultant

The gemini-consultant is not a persona — it is a special agent that invokes the Gemini CLI for an external model's perspective. It follows the same pattern as the `/gemini` skill:

```bash
gemini -p "<prompt with topic, approaches, and synthesis so far>" --output-format text
```

Invoke this as a single Task (subagent_type: `general-purpose`) that runs the Gemini CLI via Bash and returns the response. The prompt should ask Gemini to:

- Critique the approach list
- Suggest alternatives the team may have missed
- Provide a contrarian take on the recommended approach

If the `gemini` CLI is not installed, skip with a log message: "Gemini CLI not found — skipping second opinion."

### Persona Report Format

Each persona should structure their report as:

```markdown
## <Persona Name> Report: <Topic>

### Key Findings
- <finding 1 with source>
- <finding 2 with source>
- <finding 3 with source>

### Approach Evaluations

#### A1: <Name>
- **My take**: <1-2 sentence opinion from this persona's perspective>
- **Evidence**: <supporting evidence with sources>
- **Concerns**: <issues from this persona's perspective>

#### A2: <Name>
<same structure>

### My Recommendation
<which approach this persona favors and why>

### Surprising Findings
<anything unexpected that emerged during research>

### Sources
- <URLs and references>
```

---

## User Feedback Philosophy

**The skill should actively seek user input, not avoid it.** Brainstorming is inherently collaborative — the user's domain knowledge, preferences, and intuitions are critical inputs that no amount of web research can replace.

### Principles

1. **Ask generously** — Use up to 7 questions per checkpoint (2 rounds of AskUserQuestion: 4 + 3, since the tool supports max 4 per call). More questions lead to better-targeted research.
2. **3 structured checkpoints** — Phase 0 (scope), Phase 2 (plan approval), Phase 6 (synthesis review).
3. **Ad-hoc questions welcome** — If the orchestrator or a persona encounters a major fork, surprising finding, or needs domain context, ask the user immediately. Do not wait for a checkpoint. Do not guess.
4. **Present context before asking** — Always show what you have found so far, then ask targeted questions. Never ask in a vacuum.
5. **Two-round pattern** — First round covers core decisions (4 questions), second round covers refinements and preferences (up to 3 more).

### When to Ask Ad-Hoc Questions

Between checkpoints, the orchestrator should ask the user whenever:

- Two approaches seem equally viable and the choice depends on preference
- Research reveals a surprising constraint the user should know about
- A persona finds the topic needs reframing (the original question may be wrong)
- Domain-specific knowledge is needed to evaluate an approach
- Research contradicts the user's initial assumptions
- A promising but unexpected direction emerges

---

## Output Document Template

The idea document at `docs/ideas/<topic-slug>.md`:

```markdown
# <Topic> — Idea Exploration

> **Status**: Draft | Reviewed | Ready for Planning
>
> **Created**: <date>
>
> **Depth**: shallow | normal | deep
>
> **Research personas**: <count> (<persona names>)
>
> **Codex iterations**: <N> of <max>

## Problem Statement

<What problem does this idea solve? Why does it matter? Context from the user.>

## Context

### Current State

<What exists today in the codebase? Related systems or features?>

### Constraints

<Technical, business, timeline, or platform constraints identified during clarification.>

### Goals

<What success looks like, from the user's perspective.>

## Approaches Evaluated

### A1: <Approach Name>

**Summary**: <1-2 sentence description>

**How it works**: <Technical overview>

**Strengths**:

- <strength 1>
- <strength 2>

**Weaknesses**:

- <weakness 1>
- <weakness 2>

**Key technologies**: <libraries, frameworks, services>

**Estimated complexity**: Low | Medium | High

### A2: <Approach Name>

<Same structure>

### A3: <Approach Name>

<Same structure>

## Evaluation Matrix

| Dimension | A1 | A2 | A3 |
| --------- | -- | -- | -- |
| Implementation complexity | rating | rating | rating |
| Operational complexity | rating | rating | rating |
| Scalability | rating | rating | rating |
| Ecosystem maturity | rating | rating | rating |
| Team familiarity | rating | rating | rating |
| Maintenance burden | rating | rating | rating |
| Reversibility | rating | rating | rating |
| Cost | rating | rating | rating |

## Persona Perspectives

### Where Personas Agreed

<Findings and recommendations where multiple personas converged — these are high-confidence conclusions.>

### Where Personas Disagreed

<The most valuable section. Captures tensions like the-pragmatist vs the-innovator, the-critic's concerns vs the-researcher's evidence. Each disagreement surfaces a real trade-off.>

## Recommendation

**Recommended approach**: A<N>: <Name>

**Confidence**: High | Medium | Low

**Reasoning**: <Why this approach is recommended. Reference persona evidence.>

**Key trade-off accepted**: <What you are giving up by choosing this approach.>

## Research Findings

### Industry Trends (2025-2026)

<What is happening in the industry relevant to this topic?>

### Best Practices

<Established patterns and recommendations.>

### Libraries and Tools

<Specific tools researched with versions, maturity, and compatibility.>

### Real-World Examples

<How other projects or companies solve this problem.>

## Risks and Open Questions

| Risk | Severity | Mitigation |
| ---- | -------- | ---------- |
| <risk 1> | High/Med/Low | <mitigation strategy> |

### Open Questions

- <Unresolved question 1>
- <Unresolved question 2>

## Next Steps

1. Run `/plan <topic-slug>` to create a detailed implementation plan
2. <Any prerequisite research or spikes needed>
3. <Any stakeholder reviews recommended>

## Sources

- <URLs and references from all persona research>
```

---

## Error Handling

| Error | Phase | Recovery |
| ----- | ----- | -------- |
| Topic too vague after both question rounds | Phase 0 | Proceed with best interpretation. Note uncertainty in the idea doc. |
| Existing idea doc found | Phase 0 | Ask user: resume/extend or start fresh. |
| TeamCreate fails | Phase 3 | Fall back to single-agent mode (orchestrator does all research). Log: "Team creation failed — running in single-agent mode." |
| Persona spawn fails | Phase 3 | Skip that persona, redistribute its research questions to another persona or handle in orchestrator. |
| Persona times out (no report) | Phase 4 | Wait up to 2 minutes. If no response, proceed without. Note gap in synthesis. |
| 50%+ personas fail | Phase 4 | Fall back to orchestrator-only research. Note: "Most research agents failed — results may be less comprehensive." |
| Persona sends empty/poor report | Phase 4 | Discard and note the gap. Do not retry. |
| WebSearch rate limited | Any | Retry after 30 seconds, max 3 retries. Proceed with available information. |
| Codex unavailable | Phase 7 | Skip Codex loop. Note: "Codex unavailable — manual review recommended." |
| Gemini CLI not installed | Phase 3 | Skip gemini-consultant persona. Log: "Gemini CLI not found — skipping second opinion." |
| Output directory does not exist | Phase 8 | Create `docs/ideas/` directory. |
| Git commit fails | Phase 8 | Report error to user. Do not block on commit failure. |
| SendMessage delivery fails | Phase 4 | Retry once. If still failing, proceed without that persona's response. |
| TeamDelete fails | Phase 8 | Log warning. Team files in `~/.claude/teams/` will not affect the project. |

---

## Integration with /plan

The idea document is designed as a **natural precursor** to `/plan`. The plan skill automatically detects idea docs.

**Workflow**: `/brainstorm <topic>` → `docs/ideas/<topic>.md` → `/plan <topic>` → `docs/plans/<topic>.md` → `/implement`

When the user runs `/plan <topic-slug>`, the plan skill:

1. Checks for `docs/ideas/<topic-slug>.md` in Phase 0
2. If found, reads the idea doc and uses it as starting context
3. Reduces clarifying questions to only what the idea doc does not cover
4. Abbreviates Phase 1 research (skips redundant web searches)
5. Uses the recommended approach as the starting architecture
6. Passes idea doc findings into the plan agent prompt

| Idea doc section | Feeds into plan section |
| ---------------- | ---------------------- |
| Problem Statement | Summary |
| Recommended Approach | Starting architecture |
| Evaluation Matrix | Principles (what to optimize for) |
| Research Findings | Research Findings (skip redundant research) |
| Risks and Open Questions | Risks & Mitigations |
| Libraries and Tools | Libraries Considered |

The plan skill also still works with free text (`/plan some-feature`) when no idea doc exists — the idea doc integration is additive, not required.

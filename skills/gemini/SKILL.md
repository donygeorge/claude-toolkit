---
name: gemini
description: Second opinion from Google's Gemini model for alternative solutions or research.
argument-hint: "<question or code to review>"
user-invocable: true
---

# Gemini Skill

Invoke Google Gemini via the Gemini CLI for second opinions, alternative solutions, or research.

## Aliases

```yaml
aliases:
  /gemini: /gemini
  /gem: /gemini

defaults:
  model: null  # Uses Gemini CLI default
  output: text
```

## Usage

### Slash Commands

```bash
/gemini <prompt>                    # Ask Gemini a question
/gemini review this code            # Get Gemini's perspective on code
/gemini --model flash <prompt>      # Use faster model (Gemini Flash)
```

### Natural Language

```text
"ask gemini about..."
"get gemini's opinion on..."
"use gemini to review..."
```

## How It Works

This skill invokes the Gemini CLI directly via Bash, using your existing Google OAuth authentication.

### Execution

When the skill is triggered:

1. **Parse the prompt** from the user's command
2. **Invoke Gemini CLI** using:
   ```bash
   gemini -p "<prompt>" --output-format text
   ```
3. **Return the response** to the conversation

### Available Options

| Option | Description | Example |
|--------|-------------|---------|
| `--model <name>` | Override model | `--model flash`, `--model pro` |
| `--yolo` | Auto-accept all actions (for agentic tasks) | `/gemini --yolo fix this bug` |
| `--sandbox` | Run in sandbox mode | `/gemini --sandbox explore the codebase` |

### Model Aliases

The Gemini CLI uses simple aliases (it handles versioning internally):

| Alias | Description |
|-------|-------------|
| `flash` | Fast model |
| `pro` | Reasoning model |
| (default) | Latest flagship model |

You can also use full model names if needed.

## Examples

### Quick Question

```text
User: /gemini what's the best way to handle WebSocket reconnection?
```

### Code Review

```text
User: /gemini review the approach in src/services/data_service.py for calculating aggregations
```

### Alternative Perspective

```text
User: /gemini I'm planning to add a caching layer with Redis. What are the tradeoffs vs in-memory caching?
```

### Using Flash for Speed

```text
User: /gemini --model flash summarize the changes in the last 5 commits
```

## Implementation Notes

### Invoking Gemini

Use Bash tool to invoke Gemini CLI:

```bash
# Basic invocation
gemini -p "Your prompt here" --output-format text

# With model override (use simple aliases)
gemini -m flash -p "Your prompt here" --output-format text

# For agentic tasks (auto-approve)
gemini -p "Your prompt here" --yolo --output-format text
```

### Context Passing

For code-related queries, include relevant context:

1. Read the file(s) in question
2. Include code snippets in the prompt
3. Let Gemini analyze without access to the full codebase

### Output Handling

- Gemini CLI outputs to stdout
- The skill captures and presents the response
- Long responses may need summarization

### Error Handling

| Error | Action |
|-------|--------|
| Auth expired | Prompt user to run `gemini` in terminal to re-auth |
| Network error | Report error, suggest retry |
| Rate limit | Wait and retry (Gemini CLI handles this) |

## When to Use Gemini

Good use cases:
- **Second opinions** on architecture decisions
- **Alternative approaches** to a problem
- **Research** on topics outside Claude's training
- **Code review** from a different perspective
- **Quick lookups** when web search isn't enough

Not ideal for:
- Tasks requiring codebase access (use Claude Code directly)
- Tasks needing tool use (editing files, running tests)
- Long conversations (Gemini CLI is one-shot by default)

## Comparison: Gemini vs Codex

| Aspect | Gemini (this skill) | Codex (MCP) |
|--------|--------------------|----|
| Invocation | Bash CLI | MCP tool |
| Auth | OAuth (existing) | API key |
| Mode | One-shot | Conversational |
| Best for | Quick questions, reviews | Agentic tasks, planning |
| Codebase access | No (pass context manually) | Yes (via tools) |

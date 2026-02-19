# Smart Context Framework

Framework for building project-specific `smart-context.py` UserPromptSubmit hooks for Claude Code.

## What It Does

The smart-context hook automatically loads relevant context based on the user's prompt:

1. **Skill detection**: Detects `/implement`, `/solve`, `/plan`, `/review` commands and loads the corresponding SKILL.md
2. **Domain context**: Keyword-matched files from a context directory (e.g., `docs/context/`)
3. **Caching**: File content cached with mtime-based TTL to reduce I/O
4. **Size limiting**: Context capped to prevent overwhelming the model
5. **Active state**: Detects in-progress plan/loop sessions

## Quick Start

### 1. Create Domain Context Files

Create a `docs/context/` directory with markdown files using keyword headers:

```markdown
<!-- keywords: auth, login, token, session -->
# Authentication Context

Your project's auth documentation...
```

### 2. Create Your Hook

Create `.claude/hooks/smart-context.py`:

```python
#!/usr/bin/env python3
"""Project-specific smart context hook."""

import sys
import os

# Add toolkit to path (adjust path as needed)
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "path-to-toolkit", "smart-context"))

from framework import run_hook

# Define skill command mappings
SKILL_COMMANDS = [
    (r"^/implement\b", ".claude/skills/implement/SKILL.md"),
    (r"^/impl\b", ".claude/skills/implement/SKILL.md"),
    (r"^/solve\b", ".claude/skills/solve/SKILL.md"),
    (r"^/fix\b", ".claude/skills/fix/SKILL.md"),
    (r"^/plan\b", ".claude/skills/plan/SKILL.md"),
    (r"^/review\b", ".claude/skills/review-suite/SKILL.md"),
    (r"^/loop\b", ".claude/skills/loop/SKILL.md"),
]

# Files to always include (regardless of keywords)
ALWAYS_INCLUDE = {
    "workflow-domain.md",  # Critical rules
}

if __name__ == "__main__":
    run_hook(
        skill_commands=SKILL_COMMANDS,
        context_dir_name="docs/context",
        always_include_files=ALWAYS_INCLUDE,
        project_name="MyProject",
    )
```

### 3. Configure the Hook

Add to `.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "type": "command",
        "command": "python3 $CLAUDE_PROJECT_DIR/.claude/hooks/smart-context.py"
      }
    ]
  }
}
```

## Framework API

### `run_hook(**kwargs)`

Main entry point. Call this from your hook script.

| Parameter | Type | Default | Description |
| ----------- | ------ | --------- | ------------- |
| `skill_commands` | `list[tuple]` | `[]` | Slash command regex -> SKILL.md path mappings |
| `context_dir_name` | `str` | `"docs/context"` | Relative path to context files |
| `context_file_suffix` | `str` | `"-domain.md"` | Suffix for context files |
| `always_include_files` | `set` | `set()` | Filenames to always load |
| `max_dynamic_context_size` | `int` | `6144` | Max bytes for keyword-matched context |
| `max_always_include_size` | `int` | `2048` | Max bytes for always-include files |
| `project_name` | `str` | `"Project"` | Name in the project header |

### Individual Functions

You can also use the framework's components individually:

- `get_file_with_cache(filepath)` - Read file with mtime-based caching
- `extract_keywords(content)` - Extract keywords from HTML comment header
- `score_relevance(keywords, prompt)` - Score keyword matches
- `load_domain_context(context_dir, prompt, ...)` - Load matching context files
- `detect_skill_command(prompt, cwd, commands)` - Detect slash commands
- `detect_active_state(cwd)` - Find active plan/loop sessions
- `format_project_header(cwd, project_name)` - Format version/branch header

## Domain Context Files

Create markdown files in your context directory with keyword headers:

```markdown
<!-- keywords: database, sqlite, table, schema, migration -->
# Database Context

## Tables
- users: User accounts
- sessions: Active sessions

## Conventions
- Use parameterized queries
- All new tables registered in init_db()
```

The framework matches keywords against the user's prompt (case-insensitive) and loads the most relevant files within the size budget.

## Size Budgets

The framework enforces size limits to prevent context overflow:

- **Always-include files**: 2KB total (for critical rules that always apply)
- **Dynamic context**: 6KB total (for keyword-matched domain files)

Files are loaded in relevance order (highest keyword match score first) until the budget is exhausted.

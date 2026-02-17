---
globs:
  - "hooks/**/*.sh"
  - "lib/**/*.sh"
  - "toolkit.sh"
  - "tests/**/*.sh"
  - "**/*.py"
  - "agents/**/*.md"
  - "skills/**/*.md"
---

# Toolkit Development Conventions

## Shell Scripts

- All `.sh` files must pass `shellcheck -x -S warning`
- Run commands separately, not chained with `&&` or `|`

## Agent Prompts

- Agent prompts must be GENERIC — no project-specific tool references, paths, or conventions
- Skills must use generic defaults — project-specific content documented for customization

## Hooks

- Hooks must read config from `_config.sh` — no hardcoded project values

## Python

- Python scripts use `tomllib` (stdlib) — no external dependencies except pytest
- `generate-settings.py` output must be deterministic (sorted keys, 2-space indent)
- Test with `python3 -m pytest tests/ -v` (need pytest installed)

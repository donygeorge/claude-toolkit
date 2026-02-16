---
globs: .gitignore, .pre-commit-config.yaml
---
# Git Protocol

- Only stage files YOU touched -- use `git add <specific-files>`, not `git add .`
- Parallel edits may be happening in other sessions
- Commit message format: description + Co-Authored-By line
- NEVER force push, hard reset, or skip hooks without explicit request
- NEVER use `git commit --amend` unless requested
- Include `.claude/agent-memory/` changes when staging commits
- Use `git commit -F <file>` for commit messages containing destructive command names

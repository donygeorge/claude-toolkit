# Bootstrap Prompt

Copy the prompt below into Claude Code to install and configure claude-toolkit from scratch.

If you use a different GitHub URL (e.g., a fork), replace the URL on the `Toolkit repo:` line and in the git commands.

---

```text
Install and configure claude-toolkit for this project. claude-toolkit provides
Claude Code hooks, agents, skills, and rules for safe, autonomous AI-assisted
development. It integrates via git subtree under .claude/toolkit/.

Toolkit repo: https://github.com/donygeorge/claude-toolkit.git

1. If .claude/toolkit/ already exists, skip to step 2. Otherwise install:
   git remote add claude-toolkit https://github.com/donygeorge/claude-toolkit.git || true
   git fetch claude-toolkit
   git subtree add --squash --prefix=.claude/toolkit claude-toolkit main
   bash .claude/toolkit/toolkit.sh init --from-example
2. Read and follow .claude/skills/setup-toolkit/SKILL.md (the /setup-toolkit skill)
   to detect stacks, validate commands, generate toolkit.toml, create CLAUDE.md, and commit.
```

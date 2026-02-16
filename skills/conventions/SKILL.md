---
name: conventions
description: Displays coding conventions for the project.
argument-hint: "[domain-name]"
user-invocable: true
---

# Conventions Skill

Quick reference for project coding conventions. For full details, see `.claude/rules/`.

## Usage

```bash
/conventions               # Show this quick reference
/conventions <domain>      # Read .claude/rules/<domain>.md
```

<!-- Customize the domain list below for your project -->
<!-- Example domains: python, swift, database, api, testing, git, plugins -->

## Quick Reference

| Domain | Full Details |
|--------|--------------|
| Git | `.claude/rules/git-protocol.md` |

<!-- Add your project's convention domains here -->
<!-- Example: -->
<!-- | Python | `.claude/rules/python.md` | -->
<!-- | Swift | `.claude/rules/swift.md` | -->
<!-- | Database | `.claude/rules/database.md` | -->
<!-- | API Routes | `.claude/rules/api-routes.md` | -->
<!-- | Testing | `.claude/rules/testing.md` | -->

## Universal Rules (Always Apply)

1. Only stage files YOU touched -- use `git add <specific-files>`, not `git add .`
2. Read files BEFORE modifying them
3. Match existing code style and patterns
4. Add tests for new functionality

<!-- Add your project-specific critical rules here -->
<!-- Example: -->
<!-- 5. NEVER use date.today() -- use timezone-aware alternatives -->
<!-- 6. Missing data = null, NOT 0 -->

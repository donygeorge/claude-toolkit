#!/usr/bin/env bash
# bootstrap.sh — One-command setup of claude-toolkit in any project
#
# Usage (from your project root):
#   bash ~/projects/claude-toolkit/bootstrap.sh
#   bash ~/projects/claude-toolkit/bootstrap.sh --name my-project --stacks python
#   bash ~/projects/claude-toolkit/bootstrap.sh --name my-app --stacks python,ios
#   bash ~/projects/claude-toolkit/bootstrap.sh --remote git@github.com:user/claude-toolkit.git
#   bash ~/projects/claude-toolkit/bootstrap.sh --repair
#
# Or via curl (if hosted):
#   curl -sSL https://raw.githubusercontent.com/user/claude-toolkit/main/bootstrap.sh | bash -s -- --name my-project
#
# What it does:
#   1. Adds claude-toolkit as a git subtree under .claude/toolkit/
#   2. Runs toolkit.sh init --from-example (creates toolkit.toml from example)
#   3. Optionally patches project.name and project.stacks in toolkit.toml
#   4. Shows next steps (run /setup-toolkit in Claude Code)
#
# Requirements: git, jq, python3 (3.11+), bash 4+

set -euo pipefail

# ============================================================================
# Defaults
# ============================================================================

PROJECT_NAME=""
NAME_PROVIDED=false
STACKS=""
REMOTE_URL="https://github.com/donygeorge/claude-toolkit.git"
TOOLKIT_REF="main"
COMMIT=false
LOCAL_PATH=""
REPAIR=false

# ============================================================================
# Parse arguments
# ============================================================================

usage() {
  cat <<'USAGE'
Usage: bootstrap.sh [options]

Options:
  --name NAME           Project name (default: directory basename)
  --stacks STACKS       Comma-separated stacks: python, ios, typescript
  --remote URL          Toolkit git remote (default: github donygeorge/claude-toolkit)
  --ref REF             Git ref to pull (default: main)
  --local PATH          Use local toolkit path instead of git remote
  --commit              Auto-commit after setup
  --repair              Repair existing install (fills missing skills/agents/rules)
  --help                Show this help

Examples:
  bootstrap.sh
  bootstrap.sh --name my-project --stacks python
  bootstrap.sh --name my-app --stacks python,ios --commit
  bootstrap.sh --local ~/projects/claude-toolkit
  bootstrap.sh --repair
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)        [[ $# -lt 2 ]] && { echo "Error: --name requires a value"; exit 1; }
                   PROJECT_NAME="$2"; NAME_PROVIDED=true; shift 2 ;;
    --stacks)      [[ $# -lt 2 ]] && { echo "Error: --stacks requires a value"; exit 1; }
                   STACKS="$2"; shift 2 ;;
    --remote)      [[ $# -lt 2 ]] && { echo "Error: --remote requires a value"; exit 1; }
                   REMOTE_URL="$2"; shift 2 ;;
    --ref)         [[ $# -lt 2 ]] && { echo "Error: --ref requires a value"; exit 1; }
                   TOOLKIT_REF="$2"; shift 2 ;;
    --local)       [[ $# -lt 2 ]] && { echo "Error: --local requires a value"; exit 1; }
                   LOCAL_PATH="$2"; shift 2 ;;
    --commit)      COMMIT=true; shift ;;
    --repair)      REPAIR=true; shift ;;
    --help|-h)     usage; exit 0 ;;
    *)             echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ============================================================================
# Validate
# ============================================================================

# Must be in a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "Error: Not inside a git repository. Run from your project root."
  exit 1
fi

# Must have required tools
for tool in jq python3 git; do
  if ! command -v "$tool" &>/dev/null; then
    echo "Error: $tool is required but not found"
    exit 1
  fi
done

# Check Python version
python3 -c "
import sys
major, minor = sys.version_info[:2]
if (major, minor) < (3, 11):
    print(f'Error: Python 3.11+ required, found {major}.{minor}')
    sys.exit(1)
" || exit 1

PROJECT_DIR="$(git rev-parse --show-toplevel)"
CLAUDE_DIR="${PROJECT_DIR}/.claude"

# Default project name to directory basename if not provided
if [[ -z "$PROJECT_NAME" ]]; then
  PROJECT_NAME="$(basename "$PROJECT_DIR")"
fi

echo "======================================"
echo "  claude-toolkit bootstrap"
echo "======================================"
echo ""
echo "  Project:  ${PROJECT_NAME}"
if [[ -n "$STACKS" ]]; then
  echo "  Stacks:   ${STACKS}"
fi
echo "  Location: ${PROJECT_DIR}"
echo ""

# ============================================================================
# Step 1: Add subtree (or repair)
# ============================================================================

if [[ -d "${CLAUDE_DIR}/toolkit" ]]; then
  if [[ "$REPAIR" == true ]]; then
    echo "[1/3] Repairing toolkit installation..."
    bash "${CLAUDE_DIR}/toolkit/toolkit.sh" init --force
    echo "  Done."
  else
    echo "[skip] .claude/toolkit/ already exists (use --repair to fill missing files)"
  fi
else
  echo "[1/3] Adding claude-toolkit subtree..."

  if [[ -n "$LOCAL_PATH" ]]; then
    # Local mode: subtree add from local path
    LOCAL_PATH="$(cd "$LOCAL_PATH" && pwd)"
    git -C "$PROJECT_DIR" subtree add --squash --prefix=.claude/toolkit "$LOCAL_PATH" "${TOOLKIT_REF}"
  else
    # Remote mode
    if ! git -C "$PROJECT_DIR" remote get-url claude-toolkit &>/dev/null; then
      git -C "$PROJECT_DIR" remote add claude-toolkit "$REMOTE_URL"
    fi
    git -C "$PROJECT_DIR" fetch claude-toolkit
    git -C "$PROJECT_DIR" subtree add --squash --prefix=.claude/toolkit claude-toolkit "${TOOLKIT_REF}"
  fi

  echo "  Done."
fi

# ============================================================================
# Step 2: Run init (creates toolkit.toml from example + agents/skills/rules)
# ============================================================================

TOML_FILE="${CLAUDE_DIR}/toolkit.toml"
TOML_IS_NEW=false

if [[ -f "$TOML_FILE" ]]; then
  echo "[skip] toolkit.toml already exists"
else
  echo "[2/3] Running toolkit init..."
  bash "${CLAUDE_DIR}/toolkit/toolkit.sh" init --from-example
  TOML_IS_NEW=true
fi

# ============================================================================
# Step 2b: Patch toolkit.toml if --name or --stacks provided
# ============================================================================

NEEDS_REGEN=false

if [[ -f "$TOML_FILE" ]]; then
  # Patch project.name:
  #   - Always patch if TOML was just created (replace example "my-project" with actual name)
  #   - Only patch existing TOML if --name was explicitly provided
  if [[ "$TOML_IS_NEW" == true ]] || [[ "$NAME_PROVIDED" == true ]]; then
    python3 -c "
import re, sys
toml_file = sys.argv[1]
name = sys.argv[2]
content = open(toml_file).read()
repl = lambda m: 'name = \"' + name + '\"'
new_content = re.sub(r'name\s*=\s*\"[^\"]*\"', repl, content, count=1)
if new_content == content:
    # Regex didn't match — try single-quote variant
    new_content = re.sub(r\"name\s*=\s*'[^']*'\", repl, content, count=1)
if new_content == content:
    print('Warning: Could not patch project.name — edit .claude/toolkit.toml manually', file=sys.stderr)
    sys.exit(0)
open(toml_file, 'w').write(new_content)
" "$TOML_FILE" "$PROJECT_NAME"
    echo "  Patched project.name = \"${PROJECT_NAME}\""
    NEEDS_REGEN=true
  fi

  # Patch project.stacks if --stacks was provided
  if [[ -n "$STACKS" ]]; then
    python3 -c "
import re, sys
toml_file = sys.argv[1]
stacks_str = sys.argv[2]
stacks = [s.strip() for s in stacks_str.split(',')]
toml_array = '[' + ', '.join('\"' + s + '\"' for s in stacks) + ']'
content = open(toml_file).read()
new_content = re.sub(r'stacks\s*=\s*\[[^\]]*\]', 'stacks = ' + toml_array, content, count=1)
if new_content == content:
    print('Warning: Could not patch project.stacks — edit .claude/toolkit.toml manually', file=sys.stderr)
    sys.exit(0)
open(toml_file, 'w').write(new_content)
" "$TOML_FILE" "$STACKS"
    echo "  Patched project.stacks = [${STACKS}]"
    NEEDS_REGEN=true
  fi

  # Regenerate settings after patching
  if [[ "$NEEDS_REGEN" == true ]]; then
    echo "  Regenerating settings..."
    bash "${CLAUDE_DIR}/toolkit/toolkit.sh" generate-settings
  fi
fi

# ============================================================================
# Step 3: Summary
# ============================================================================

echo ""
echo "======================================"
echo "  Setup complete!"
echo "======================================"
echo ""
echo "Created:"
echo "  .claude/toolkit/          Toolkit subtree"
echo "  .claude/toolkit.toml      Your configuration"
echo "  .claude/settings.json     Generated settings"
echo "  .claude/agents/           Agent prompts"
echo "  .claude/skills/           Skill templates"
echo "  .claude/rules/            Coding conventions"
echo "  .mcp.json                 MCP server config"
echo ""

if [[ "$COMMIT" == true ]]; then
  echo "Committing..."
  git -C "$PROJECT_DIR" add .claude/
  if [[ -f "${PROJECT_DIR}/.mcp.json" ]]; then
    git -C "$PROJECT_DIR" add .mcp.json
  fi
  COMMIT_MSG="Add claude-toolkit

Bootstrapped with: bootstrap.sh"
  if [[ -n "$STACKS" ]]; then
    COMMIT_MSG="${COMMIT_MSG} --stacks ${STACKS}"
  fi
  TOOLKIT_VERSION="$(cat "${CLAUDE_DIR}/toolkit/VERSION" 2>/dev/null || echo "unknown")"
  COMMIT_MSG="${COMMIT_MSG}
Toolkit version: ${TOOLKIT_VERSION}"
  # Write commit message to temp file to avoid guard hook issues
  COMMIT_MSG_FILE="$(mktemp)"
  printf '%s' "$COMMIT_MSG" > "$COMMIT_MSG_FILE"
  git -C "$PROJECT_DIR" commit -F "$COMMIT_MSG_FILE"
  rm -f "$COMMIT_MSG_FILE"
  echo "  Committed."
else
  echo "Next steps:"
  echo "  1. Open Claude Code in this project"
  echo "  2. Run: /setup-toolkit"
  echo "     This will auto-detect your stacks, validate lint/test commands,"
  echo "     configure toolkit.toml, generate CLAUDE.md, and commit."
  echo ""
  echo "  Or manually:"
  echo "  1. Edit .claude/toolkit.toml to match your project"
  echo "  2. Run: bash .claude/toolkit/toolkit.sh generate-settings"
  echo "  3. Commit: git add .claude/ .mcp.json && git commit -m 'Add claude-toolkit'"
fi

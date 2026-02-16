#!/usr/bin/env bash
# bootstrap.sh — One-command setup of claude-toolkit in any project
#
# Usage (from your project root):
#   bash ~/projects/claude-toolkit/bootstrap.sh --name my-project --stacks python
#   bash ~/projects/claude-toolkit/bootstrap.sh --name my-app --stacks python,ios
#   bash ~/projects/claude-toolkit/bootstrap.sh --name my-app --stacks typescript --remote git@github.com:user/claude-toolkit.git
#
# Or via curl (if hosted):
#   curl -sSL https://raw.githubusercontent.com/user/claude-toolkit/main/bootstrap.sh | bash -s -- --name my-project --stacks python
#
# What it does:
#   1. Adds claude-toolkit as a git subtree under .claude/toolkit/
#   2. Generates toolkit.toml from your arguments
#   3. Runs toolkit.sh init (symlinks agents, copies skills, generates settings)
#   4. Shows next steps
#
# Requirements: git, jq, python3 (3.11+), bash 4+

set -euo pipefail

# ============================================================================
# Defaults
# ============================================================================

PROJECT_NAME=""
STACKS=""
REMOTE_URL="https://github.com/donygeorge/claude-toolkit.git"
TOOLKIT_REF="main"
PYTHON_MIN="3.11"
REQUIRED_TOOLS="jq"
OPTIONAL_TOOLS=""
COMMIT=false
LOCAL_PATH=""

# ============================================================================
# Parse arguments
# ============================================================================

usage() {
  cat <<'USAGE'
Usage: bootstrap.sh [options]

Required:
  --name NAME           Project name (e.g., realta, openclaw)
  --stacks STACKS       Comma-separated stacks: python, ios, typescript

Optional:
  --remote URL          Toolkit git remote (default: github donygeorge/claude-toolkit)
  --ref REF             Git ref to pull (default: main)
  --local PATH          Use local toolkit path instead of git remote
  --python-min VER      Minimum Python version (default: 3.11)
  --tools TOOLS         Required tools, comma-separated (default: jq)
  --optional-tools T    Optional tools, comma-separated
  --commit              Auto-commit after setup
  --help                Show this help

Examples:
  bootstrap.sh --name realta --stacks typescript
  bootstrap.sh --name openclaw --stacks python --tools "jq,ruff"
  bootstrap.sh --name jarvin --stacks python,ios --commit
  bootstrap.sh --name my-app --stacks python --local ~/projects/claude-toolkit
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)        PROJECT_NAME="$2"; shift 2 ;;
    --stacks)      STACKS="$2"; shift 2 ;;
    --remote)      REMOTE_URL="$2"; shift 2 ;;
    --ref)         TOOLKIT_REF="$2"; shift 2 ;;
    --local)       LOCAL_PATH="$2"; shift 2 ;;
    --python-min)  PYTHON_MIN="$2"; shift 2 ;;
    --tools)       REQUIRED_TOOLS="$2"; shift 2 ;;
    --optional-tools) OPTIONAL_TOOLS="$2"; shift 2 ;;
    --commit)      COMMIT=true; shift ;;
    --help|-h)     usage; exit 0 ;;
    *)             echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ============================================================================
# Validate
# ============================================================================

if [[ -z "$PROJECT_NAME" ]]; then
  echo "Error: --name is required"
  echo ""
  usage
  exit 1
fi

if [[ -z "$STACKS" ]]; then
  echo "Error: --stacks is required"
  echo ""
  usage
  exit 1
fi

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
req_major, req_minor = map(int, '${PYTHON_MIN}'.split('.'))
if (major, minor) < (req_major, req_minor):
    print(f'Error: Python {req_major}.{req_minor}+ required, found {major}.{minor}')
    sys.exit(1)
" || exit 1

PROJECT_DIR="$(git rev-parse --show-toplevel)"
CLAUDE_DIR="${PROJECT_DIR}/.claude"

echo "======================================"
echo "  claude-toolkit bootstrap"
echo "======================================"
echo ""
echo "  Project:  ${PROJECT_NAME}"
echo "  Stacks:   ${STACKS}"
echo "  Location: ${PROJECT_DIR}"
echo ""

# ============================================================================
# Step 1: Add subtree
# ============================================================================

if [[ -d "${CLAUDE_DIR}/toolkit" ]]; then
  echo "[skip] .claude/toolkit/ already exists"
else
  echo "[1/4] Adding claude-toolkit subtree..."

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
# Step 2: Generate toolkit.toml
# ============================================================================

TOML_FILE="${CLAUDE_DIR}/toolkit.toml"

if [[ -f "$TOML_FILE" ]]; then
  echo "[skip] toolkit.toml already exists"
else
  echo "[2/4] Generating toolkit.toml..."

  # Convert comma-separated stacks to TOML array
  IFS=',' read -ra STACK_ARRAY <<< "$STACKS"
  STACKS_TOML=""
  for i in "${!STACK_ARRAY[@]}"; do
    stack="${STACK_ARRAY[$i]}"
    stack="$(echo "$stack" | tr -d ' ')"  # trim whitespace
    if [[ $i -gt 0 ]]; then
      STACKS_TOML="${STACKS_TOML}, "
    fi
    STACKS_TOML="${STACKS_TOML}\"${stack}\""
  done

  # Convert comma-separated tools to TOML arrays
  _to_toml_array() {
    local input="$1"
    [[ -z "$input" ]] && echo "[]" && return
    local result=""
    IFS=',' read -ra arr <<< "$input"
    for i in "${!arr[@]}"; do
      local item="$(echo "${arr[$i]}" | tr -d ' ')"
      if [[ $i -gt 0 ]]; then result="${result}, "; fi
      result="${result}\"${item}\""
    done
    echo "[${result}]"
  }

  REQUIRED_TOML=$(_to_toml_array "$REQUIRED_TOOLS")
  OPTIONAL_TOML=$(_to_toml_array "$OPTIONAL_TOOLS")

  # Determine linter config based on stacks
  LINTER_SECTION=""
  GATE_SECTION=""

  for stack in "${STACK_ARRAY[@]}"; do
    stack="$(echo "$stack" | tr -d ' ')"
    case "$stack" in
      python)
        LINTER_SECTION="${LINTER_SECTION}
[hooks.post-edit-lint.linters.py]
cmd = \".venv/bin/ruff check\"
fmt = \".venv/bin/ruff format\"
fallback = \"ruff\"
"
        GATE_SECTION="${GATE_SECTION}
[hooks.task-completed.gates.lint]
glob = \"*.py\"
cmd = \".venv/bin/ruff check --quiet\"

[hooks.task-completed.gates.tests]
glob = \"*.py\"
cmd = \"make test-changed\"  # Customize: replace with your project's test command
timeout = 90
"
        ;;
      typescript)
        LINTER_SECTION="${LINTER_SECTION}
[hooks.post-edit-lint.linters.ts]
cmd = \"npx eslint\"
fmt = \"npx prettier --write\"
fallback = \"eslint\"

[hooks.post-edit-lint.linters.tsx]
cmd = \"npx eslint\"
fmt = \"npx prettier --write\"
fallback = \"eslint\"
"
        GATE_SECTION="${GATE_SECTION}
[hooks.task-completed.gates.lint]
glob = \"*.{ts,tsx}\"
cmd = \"npx eslint --quiet\"

[hooks.task-completed.gates.tests]
glob = \"*.{ts,tsx}\"
cmd = \"npm test\"  # Customize: replace with your project's test command
timeout = 90
"
        ;;
      ios)
        LINTER_SECTION="${LINTER_SECTION}
[hooks.post-edit-lint.linters.swift]
cmd = \"swiftlint lint --quiet\"
fmt = \"swiftlint lint --fix --quiet\"
fallback = \"swiftlint\"
"
        GATE_SECTION="${GATE_SECTION}
[hooks.task-completed.gates.ios-build]
glob = \"*.swift\"
cmd = \"make ios-build\"  # Customize: replace with your project's build command
timeout = 120
"
        ;;
    esac
  done

  # Determine version file
  VERSION_FILE="VERSION"
  if [[ -f "${PROJECT_DIR}/package.json" ]]; then
    VERSION_FILE="package.json"
  elif [[ -f "${PROJECT_DIR}/VERSION" ]]; then
    VERSION_FILE="VERSION"
  elif [[ -f "${PROJECT_DIR}/pyproject.toml" ]]; then
    VERSION_FILE="pyproject.toml"
  fi

  # Write toolkit.toml
  cat > "$TOML_FILE" <<TOML
# Claude Toolkit Configuration for ${PROJECT_NAME}
# Generated by bootstrap.sh — customize as needed.
# Docs: https://github.com/donygeorge/claude-toolkit#configuration-reference

[toolkit]
remote_url = "${REMOTE_URL}"

[project]
name = "${PROJECT_NAME}"
version_file = "${VERSION_FILE}"
stacks = [${STACKS_TOML}]

[hooks.setup]
python_min_version = "${PYTHON_MIN}"
required_tools = ${REQUIRED_TOML}
optional_tools = ${OPTIONAL_TOML}
security_tools = ["gitleaks", "semgrep"]

[hooks.post-edit-lint.linters]
${LINTER_SECTION}
[hooks.task-completed.gates]
${GATE_SECTION}
[hooks.auto-approve]
write_paths = [
    "*/app/*", "*/src/*", "*/lib/*", "*/tests/*", "*/test/*",
    "*/docs/*", "*/artifacts/*", "*/scripts/*", "*/.claude/*",
    "*/CLAUDE.md", "*/Makefile", "*/VERSION", "*/README.md",
    "*/requirements*.txt", "*/package*.json", "*/pyproject.toml",
    "*/docker-compose*.yml", "*/Dockerfile", "*/tsconfig*.json",
]
bash_commands = []

[hooks.subagent-context]
critical_rules = []
available_tools = []
stack_info = ""

[hooks.compact]
source_dirs = ["app", "src"]
source_extensions = ["*.py", "*.ts", "*.tsx", "*.swift"]
state_dirs = ["artifacts"]

[hooks.session-end]
agent_memory_max_lines = 250
hook_log_max_lines = 500

[notifications]
app_name = "Claude Code"
permission_sound = "Blow"
TOML

  echo "  Created .claude/toolkit.toml"
fi

# ============================================================================
# Step 3: Run init
# ============================================================================

echo "[3/4] Running toolkit init..."
bash "${CLAUDE_DIR}/toolkit/toolkit.sh" init

# ============================================================================
# Step 4: Summary
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
echo "  .claude/agents/           9 agent prompts"
echo "  .claude/skills/           9 skill templates"
echo "  .claude/rules/            Coding conventions"
echo "  .mcp.json                 MCP server config"
echo ""

if [[ "$COMMIT" == true ]]; then
  echo "Committing..."
  git -C "$PROJECT_DIR" add .claude/ .mcp.json
  git -C "$PROJECT_DIR" commit -m "Add claude-toolkit

Bootstrapped with: --name ${PROJECT_NAME} --stacks ${STACKS}
Toolkit version: $(cat "${CLAUDE_DIR}/toolkit/VERSION" 2>/dev/null || echo "unknown")"
  echo "  Committed."
else
  echo "Next steps:"
  echo "  1. Review and customize .claude/toolkit.toml"
  echo "  2. (Optional) Create .claude/settings-project.json for project overrides"
  echo "  3. (Optional) Create CLAUDE.md with project-specific instructions"
  echo "  4. Commit: git add .claude/ .mcp.json && git commit -m 'Add claude-toolkit'"
  echo ""
  echo "Or have Claude do it:"
  echo "  Open Claude Code in this project and say:"
  echo '  "Set up the claude-toolkit — review toolkit.toml and customize for this project"'
fi

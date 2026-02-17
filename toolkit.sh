#!/usr/bin/env bash
# toolkit.sh — Main CLI for claude-toolkit
#
# Usage:
#   .claude/toolkit/toolkit.sh <subcommand> [options]
#
# Subcommands:
#   init, update, customize, status, validate, generate-settings, help

set -euo pipefail

# --- Path resolution ---
TOOLKIT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  PROJECT_DIR="$CLAUDE_PROJECT_DIR"
else
  PROJECT_DIR="$(cd "$TOOLKIT_DIR/../.." && pwd)"
fi

CLAUDE_DIR="${PROJECT_DIR}/.claude"
MANIFEST_PATH="${CLAUDE_DIR}/toolkit-manifest.json"

# --- Shared libraries ---
# shellcheck source=lib/manifest.sh
source "${TOOLKIT_DIR}/lib/manifest.sh"

# --- Helpers (used by all subcommand modules) ---
_info() { echo "  [info] $*"; }
_warn() { echo "  [warn] $*" >&2; }
_error() { echo "  [error] $*" >&2; }
_ok() { echo "  [ok] $*"; }

_atomic_write() {
  local target="$1"
  local content="${2:-}"
  local tmp="${target}.tmp.$$"
  if [[ -n "$content" ]]; then
    printf '%s\n' "$content" > "$tmp"
  else
    cat > "$tmp"
  fi
  mv "$tmp" "$target"
}

_require_jq() {
  if ! command -v jq &>/dev/null; then
    _error "jq is required. Install with: brew install jq"
    return 1
  fi
}

_require_python3() {
  if ! command -v python3 &>/dev/null; then
    _error "python3 is required."
    return 1
  fi
}

_require_toml() {
  local toml_file="${CLAUDE_DIR}/toolkit.toml"
  if [[ ! -f "$toml_file" ]]; then
    _error "toolkit.toml not found at ${toml_file}"
    echo ""
    echo "  Create one with:"
    echo "    cp ${TOOLKIT_DIR}/templates/toolkit.toml.example ${toml_file}"
    echo ""
    echo "  Or run: $0 init --from-example"
    return 1
  fi
}

_read_toml_value() {
  local file="$1"
  local key="$2"
  python3 -c "
import tomllib, sys
with open(sys.argv[1], 'rb') as f:
    data = tomllib.load(f)
keys = sys.argv[2].split('.')
val = data
for k in keys:
    if isinstance(val, dict) and k in val:
        val = val[k]
    else:
        sys.exit(1)
if isinstance(val, list):
    for item in val:
        print(item)
else:
    print(val)
" "$file" "$key" 2>/dev/null
}

_read_toml_array() {
  _read_toml_value "$1" "$2"
}

# --- Subcommand modules ---
# shellcheck source=lib/cmd-generate-settings.sh
source "${TOOLKIT_DIR}/lib/cmd-generate-settings.sh"
# shellcheck source=lib/cmd-init.sh
source "${TOOLKIT_DIR}/lib/cmd-init.sh"
# shellcheck source=lib/cmd-update.sh
source "${TOOLKIT_DIR}/lib/cmd-update.sh"
# shellcheck source=lib/cmd-customize.sh
source "${TOOLKIT_DIR}/lib/cmd-customize.sh"
# shellcheck source=lib/cmd-status.sh
source "${TOOLKIT_DIR}/lib/cmd-status.sh"
# shellcheck source=lib/cmd-validate.sh
source "${TOOLKIT_DIR}/lib/cmd-validate.sh"
# shellcheck source=lib/cmd-doctor.sh
source "${TOOLKIT_DIR}/lib/cmd-doctor.sh"
# shellcheck source=lib/cmd-help.sh
source "${TOOLKIT_DIR}/lib/cmd-help.sh"

# --- Dry-run mode ---
DRY_RUN=false
export DRY_RUN

_is_dry_run() {
  [[ "$DRY_RUN" == true ]]
}

_dry_run_msg() {
  echo "  [dry-run] $*"
}

# --- Main dispatch ---
main() {
  local cmd="${1:-help}"
  shift || true

  # Parse global flags before subcommand
  while [[ "${cmd:-}" == --* ]]; do
    case "$cmd" in
      --dry-run) DRY_RUN=true; export DRY_RUN; cmd="${1:-help}"; shift || true ;;
      *) break ;;
    esac
  done

  case "$cmd" in
    init)               cmd_init "$@" ;;
    update)             cmd_update "$@" ;;
    customize)          cmd_customize "$@" ;;
    status)             cmd_status ;;
    validate)           cmd_validate ;;
    generate-settings)  cmd_generate_settings ;;
    doctor)             cmd_doctor ;;
    help|--help|-h)     cmd_help ;;
    *)
      _error "Unknown command: $cmd"
      echo ""
      cmd_help
      return 1
      ;;
  esac
}

main "$@"

#!/usr/bin/env python3
"""Generate a bash-sourceable cache file from toolkit.toml.

Reads a TOML configuration file and flattens all keys with a TOOLKIT_ prefix.
Nested keys are joined with underscores and uppercased.

Example:
    [hooks.setup]
    python_min_version = "3.11"

    becomes: TOOLKIT_HOOKS_SETUP_PYTHON_MIN_VERSION='3.11'

Arrays are serialized as JSON strings:
    required_tools = ["ruff", "jq"]

    becomes: TOOLKIT_HOOKS_SETUP_REQUIRED_TOOLS='["ruff","jq"]'

Usage:
    python3 generate-config-cache.py --toml toolkit.toml --output toolkit-cache.env
    python3 generate-config-cache.py --toml toolkit.toml  # stdout
    python3 generate-config-cache.py --validate-only --toml toolkit.toml
"""

from __future__ import annotations

import argparse
import json
import sys
import tomllib
from pathlib import Path

# ---------------------------------------------------------------------------
# Schema: known top-level sections and their allowed keys.
# A value of `dict` means the key holds a sub-table whose keys are dynamic
# (e.g., linter names in [hooks.post-edit-lint.linters]).
# ---------------------------------------------------------------------------
SCHEMA: dict[str, dict[str, type | dict]] = {
    "toolkit": {
        "remote_url": str,
    },
    "project": {
        "name": str,
        "version_file": str,
        "stacks": list,
    },
    "hooks": {
        "setup": {
            "python_min_version": str,
            "required_tools": list,
            "optional_tools": list,
            "security_tools": list,
        },
        "post-edit-lint": {
            "linters": dict,  # dynamic keys (file extensions)
        },
        "task-completed": {
            "gates": dict,  # dynamic keys (gate names)
        },
        "auto-approve": {
            "write_paths": list,
            "bash_commands": list,
        },
        "subagent-context": {
            "critical_rules": list,
            "available_tools": list,
            "stack_info": str,
        },
        "compact": {
            "source_dirs": list,
            "source_extensions": list,
            "state_dirs": list,
        },
        "session-end": {
            "agent_memory_max_lines": int,
            "hook_log_max_lines": int,
        },
    },
    "notifications": {
        "app_name": str,
        "permission_sound": str,
    },
}


def validate_schema(data: dict, schema: dict, path: str = "") -> list[str]:
    """Validate *data* against *schema*.  Returns a list of error strings."""
    errors: list[str] = []
    for key, value in data.items():
        full_key = f"{path}.{key}" if path else key
        if key not in schema:
            errors.append(f"Unknown key: '{full_key}'")
            continue
        expected = schema[key]
        if expected is dict:
            # Dynamic sub-table -- accept anything nested
            if not isinstance(value, dict):
                errors.append(
                    f"Expected table for '{full_key}', got {type(value).__name__}"
                )
        elif isinstance(expected, dict):
            if isinstance(value, dict):
                errors.extend(validate_schema(value, expected, full_key))
            else:
                errors.append(
                    f"Expected table for '{full_key}', got {type(value).__name__}"
                )
        # Leaf type checks (str, int, list) -- lenient: don't reject mismatches
        # since TOML typing is already enforced by the parser.
    return errors


def _escape_for_shell(value: str) -> str:
    """Escape a string value for single-quoted shell assignment.

    In single-quoted strings the only character that needs escaping is the
    single quote itself.  We use the conventional '\'' trick (end quote,
    escaped literal quote, re-open quote).
    """
    return value.replace("'", "'\\''")


def flatten(data: dict, prefix: str = "TOOLKIT") -> list[tuple[str, str]]:
    """Flatten nested dict into (KEY, shell-safe-value) pairs."""
    entries: list[tuple[str, str]] = []
    for key, value in data.items():
        # Normalise key: replace hyphens with underscores, uppercase
        norm_key = key.replace("-", "_").upper()
        full_key = f"{prefix}_{norm_key}"

        if isinstance(value, dict):
            entries.extend(flatten(value, full_key))
        elif isinstance(value, list):
            # Serialize arrays as compact JSON
            json_str = json.dumps(value, separators=(",", ":"))
            entries.append((full_key, f"'{_escape_for_shell(json_str)}'"))
        elif isinstance(value, bool):
            entries.append((full_key, f"'{str(value).lower()}'"))
        elif isinstance(value, int):
            entries.append((full_key, f"'{value}'"))
        elif isinstance(value, str):
            entries.append((full_key, f"'{_escape_for_shell(value)}'"))
        else:
            # Fallback: stringify
            entries.append((full_key, f"'{_escape_for_shell(str(value))}'"))
    return entries


def generate_cache(toml_path: Path) -> str:
    """Read *toml_path* and return the cache file content as a string."""
    with open(toml_path, "rb") as f:
        data = tomllib.load(f)

    errors = validate_schema(data, SCHEMA)
    if errors:
        error_msg = "\n".join(f"  - {e}" for e in errors)
        raise ValueError(f"Schema validation failed for {toml_path}:\n{error_msg}")

    lines = [
        "# Auto-generated by generate-config-cache.py -- DO NOT EDIT",
        f"# Source: {toml_path}",
        "",
    ]
    for env_key, env_val in flatten(data):
        lines.append(f"{env_key}={env_val}")

    lines.append("")  # trailing newline
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate toolkit-cache.env from toolkit.toml"
    )
    parser.add_argument("--toml", required=True, help="Path to toolkit.toml")
    parser.add_argument("--output", default=None, help="Output file (default: stdout)")
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Only validate the TOML against the schema; do not generate output",
    )
    args = parser.parse_args()

    toml_path = Path(args.toml)
    if not toml_path.exists():
        print(f"Error: {toml_path} not found", file=sys.stderr)
        return 1

    try:
        if args.validate_only:
            with open(toml_path, "rb") as f:
                data = tomllib.load(f)
            errors = validate_schema(data, SCHEMA)
            if errors:
                for e in errors:
                    print(f"  - {e}", file=sys.stderr)
                return 1
            print(f"Valid: {toml_path}")
            return 0

        content = generate_cache(toml_path)

        if args.output:
            out_path = Path(args.output)
            out_path.write_text(content)
            print(f"Generated: {out_path}", file=sys.stderr)
        else:
            sys.stdout.write(content)

    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except tomllib.TOMLDecodeError as exc:
        print(f"TOML parse error in {toml_path}: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

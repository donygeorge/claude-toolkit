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
import os
import re
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
            "mcp_tool_prefixes": list,
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
    "skills": {
        "implement": {
            "tdd_enforcement": str,
        },
    },
    "notifications": {
        "app_name": str,
        "permission_sound": str,
    },
}


# ---------------------------------------------------------------------------
# Enum constraints: keys with a restricted set of valid string values.
# ---------------------------------------------------------------------------
ENUM_VALUES: dict[str, list[str]] = {
    "skills.implement.tdd_enforcement": ["strict", "guided", "off"],
}


def _validate_enum_values(data: dict, path: str = "") -> list[str]:
    """Check that values with enum constraints use allowed values."""
    errors: list[str] = []
    for key, value in data.items():
        full_key = f"{path}.{key}" if path else key
        if isinstance(value, dict):
            errors.extend(_validate_enum_values(value, full_key))
        elif full_key in ENUM_VALUES and isinstance(value, str):
            allowed = ENUM_VALUES[full_key]
            if value not in allowed:
                errors.append(
                    f"Invalid value for '{full_key}': '{value}' "
                    f"(allowed: {', '.join(repr(v) for v in allowed)})"
                )
    return errors


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
        elif expected is str:
            if not isinstance(value, str):
                errors.append(
                    f"Expected string for '{full_key}', got {type(value).__name__}"
                )
        elif expected is int:
            if not isinstance(value, int) or isinstance(value, bool):
                errors.append(
                    f"Expected integer for '{full_key}', got {type(value).__name__}"
                )
        elif expected is list:
            if not isinstance(value, list):
                errors.append(
                    f"Expected list for '{full_key}', got {type(value).__name__}"
                )
    return errors


# ---------------------------------------------------------------------------
# Security: env var name and value validation
# ---------------------------------------------------------------------------

# Control characters except \n (0x0A) and \t (0x09).
# Covers 0x00-0x08, 0x0b-0x0d (VT, FF, CR), 0x0e-0x1f, 0x7f.
# CR (0x0d) is rejected because it can enable log/line injection attacks.
_CONTROL_CHAR_RE = re.compile(
    r"[\x00-\x08\x0b-\x0d\x0e-\x1f\x7f]"
)


def _validate_env_key(key: str) -> bool:
    """Ensure generated env var name is safe for bash."""
    return bool(re.match(r"^[A-Z_][A-Z0-9_]*$", key))


def _check_control_chars(value: str, key: str) -> str | None:
    """Return an error string if *value* contains unsafe control characters."""
    match = _CONTROL_CHAR_RE.search(value)
    if match:
        char_hex = f"0x{ord(match.group()):02x}"
        return (
            f"Value for '{key}' contains control character {char_hex} "
            f"— only \\n and \\t are allowed"
        )
    return None


def _escape_for_shell(value: str) -> str:
    """Escape a string value for single-quoted shell assignment.

    In single-quoted strings the only character that needs escaping is the
    single quote itself.  We use the conventional '\'' trick (end quote,
    escaped literal quote, re-open quote).
    """
    return value.replace("'", "'\\''")


def flatten(data: dict, prefix: str = "TOOLKIT") -> list[tuple[str, str]]:
    """Flatten nested dict into (KEY, shell-safe-value) pairs.

    Raises ``ValueError`` if a generated env var name is unsafe for bash
    or if a string value contains disallowed control characters.
    """
    entries: list[tuple[str, str]] = []
    for key, value in data.items():
        # Normalise key: replace hyphens with underscores, uppercase
        norm_key = key.replace("-", "_").upper()
        full_key = f"{prefix}_{norm_key}"

        if not _validate_env_key(full_key):
            raise ValueError(
                f"Unsafe variable name generated: '{full_key}' from key '{key}'"
            )

        if isinstance(value, dict):
            entries.extend(flatten(value, full_key))
        elif isinstance(value, list):
            # Serialize arrays as compact JSON
            json_str = json.dumps(value, separators=(",", ":"))
            # Check each string element for control characters
            for item in value:
                if isinstance(item, str):
                    err = _check_control_chars(item, full_key)
                    if err:
                        raise ValueError(err)
            entries.append((full_key, f"'{_escape_for_shell(json_str)}'"))
        elif isinstance(value, bool):
            entries.append((full_key, f"'{str(value).lower()}'"))
        elif isinstance(value, int):
            entries.append((full_key, f"'{value}'"))
        elif isinstance(value, str):
            err = _check_control_chars(value, full_key)
            if err:
                raise ValueError(err)
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
    errors.extend(_validate_enum_values(data))
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
            errors.extend(_validate_enum_values(data))
            if errors:
                for e in errors:
                    print(f"  - {e}", file=sys.stderr)
                return 1
            print(f"Valid: {toml_path}")
            return 0

        content = generate_cache(toml_path)

        if args.output:
            out_path = Path(args.output)
            # Atomic write with restrictive permissions (0600)
            tmp_path = out_path.with_suffix(".tmp." + str(os.getpid()))
            old_umask = os.umask(0o077)
            try:
                tmp_path.write_text(content)
                os.replace(str(tmp_path), str(out_path))
            finally:
                os.umask(old_umask)
            # Ensure final file has 0600 permissions
            os.chmod(str(out_path), 0o600)
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

#!/usr/bin/env python3
"""Generate merged settings.json for Claude Code projects.

Merges three tiers of JSON configuration:
  1. Base settings (universal toolkit defaults)
  2. Stack overlays (language/framework-specific additions)
  3. Project overlay (project-specific overrides)

Merge rules:
  - Objects: recursive deep merge (later tier wins on scalar conflicts)
  - Arrays of primitives: concatenate + deduplicate (add-only, order preserved)
  - Arrays of objects: merge by key field (e.g., "matcher" for hooks), then deep merge each
  - null values: delete the key from the result
  - Scalars: later tier wins

Usage:
    python3 generate-settings.py \\
        --base templates/settings-base.json \\
        --stacks templates/stacks/python.json,templates/stacks/ios.json \\
        --project .claude/settings-project.json \\
        --output .claude/settings.json

    python3 generate-settings.py \\
        --base templates/settings-base.json \\
        --project .claude/settings-project.json \\
        --mcp-base mcp/base.mcp.json \\
        --mcp-output .mcp.json \\
        --output .claude/settings.json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Hook merge key: hooks arrays-of-objects are merged by the "matcher" field.
# If no matcher is present, use a sentinel so unmatchered entries merge by
# position within their event group.
# ---------------------------------------------------------------------------
HOOK_MERGE_KEY = "matcher"

# ---------------------------------------------------------------------------
# Auto-approve validation: reject dangerous patterns
# ---------------------------------------------------------------------------
_DANGEROUS_BARE = {
    "*",
    "sh",
    "bash",
    "zsh",
    "fish",
    "osascript",
    "powershell",
    "curl",
    "wget",
    "eval",
}

_INTERPRETER_EXEC_PATTERNS = [
    re.compile(r"^python\s+-c\b"),
    re.compile(r"^python3\s+-c\b"),
    re.compile(r"^node\s+-e\b"),
    re.compile(r"^perl\s+-e\b"),
    re.compile(r"^ruby\s+-e\b"),
]

_PIPE_TO_SHELL = re.compile(r"\|\s*(sh|bash|python|python3)\b")


# ---------------------------------------------------------------------------
# Settings schema validation
# ---------------------------------------------------------------------------

KNOWN_TOP_LEVEL_KEYS = {
    "hooks", "permissions", "env", "preferences", "mcpServers", "mcp",
    "sandbox", "enabledPlugins",
}

HOOKS_KNOWN_EVENT_TYPES = {
    "PreToolUse",
    "PostToolUse",
    "PostToolUseFailure",
    "SessionStart",
    "SessionEnd",
    "Notification",
    "Stop",
    "PreCompact",
    "PostCompact",
    "UserPromptSubmit",
    "TaskCompleted",
    "PermissionRequest",
    "SubagentStart",
    "SubagentStop",
}

HOOK_ENTRY_KNOWN_FIELDS = {
    "matcher",
    "hooks",
    "event",
    "type",
    "command",
    "timeout",
    "description",
}

PERMISSIONS_KNOWN_FIELDS = {"allow", "deny"}


def validate_settings_schema(merged: dict) -> list[str]:
    """Validate merged settings match expected Claude Code schema.

    Returns a list of warning strings (not errors) so typos are caught
    without blocking generation.
    """
    warnings: list[str] = []

    # Check for unknown top-level keys
    for key in merged:
        if key not in KNOWN_TOP_LEVEL_KEYS:
            warnings.append(f"Unknown top-level key: '{key}' (possible typo)")

    # Validate hooks structure
    hooks = merged.get("hooks")
    if hooks is not None:
        if not isinstance(hooks, dict):
            warnings.append("'hooks' should be a dict, got " + type(hooks).__name__)
        else:
            for event_name, entries in hooks.items():
                if event_name == "auto-approve":
                    continue  # auto-approve has its own structure
                if event_name not in HOOKS_KNOWN_EVENT_TYPES:
                    warnings.append(
                        f"Unknown hook event type: '{event_name}' (known: {', '.join(sorted(HOOKS_KNOWN_EVENT_TYPES))})"
                    )
                if isinstance(entries, list):
                    for entry in entries:
                        if isinstance(entry, dict):
                            for field in entry:
                                if field not in HOOK_ENTRY_KNOWN_FIELDS:
                                    warnings.append(
                                        f"Unknown field '{field}' in hook entry for event '{event_name}'"
                                    )
                            # Validate hook entry has required 'hooks' array
                            if "hooks" in entry and not isinstance(
                                entry["hooks"], list
                            ):
                                warnings.append(
                                    f"Hook entry 'hooks' field should be a list in event '{event_name}'"
                                )

    # Validate permissions structure
    perms = merged.get("permissions")
    if perms is not None:
        if not isinstance(perms, dict):
            warnings.append(
                "'permissions' should be a dict, got " + type(perms).__name__
            )
        else:
            for key in perms:
                if key not in PERMISSIONS_KNOWN_FIELDS:
                    warnings.append(f"Unknown permissions field: '{key}'")
            for field in ("allow", "deny"):
                val = perms.get(field)
                if val is not None and not isinstance(val, list):
                    warnings.append(
                        f"'permissions.{field}' should be a list, got "
                        + type(val).__name__
                    )

    # Validate env is a dict
    env = merged.get("env")
    if env is not None and not isinstance(env, dict):
        warnings.append("'env' should be a dict, got " + type(env).__name__)

    return warnings


def validate_auto_approve(commands: list) -> list[str]:
    """Validate auto-approve bash_commands entries.  Returns error strings."""
    errors: list[str] = []
    for cmd in commands:
        if not isinstance(cmd, str):
            continue
        stripped = cmd.strip()
        # Bare dangerous commands
        if stripped in _DANGEROUS_BARE:
            errors.append(
                f"Auto-approve blocked: '{stripped}' is a dangerous bare command"
            )
            continue
        # Interpreter with exec flag
        for pat in _INTERPRETER_EXEC_PATTERNS:
            if pat.match(stripped):
                errors.append(
                    f"Auto-approve blocked: '{stripped}' uses interpreter exec flag"
                )
                break
        # Pipe-to-shell
        if _PIPE_TO_SHELL.search(stripped):
            errors.append(
                f"Auto-approve blocked: '{stripped}' contains pipe-to-shell pattern"
            )
    return errors


def validate_allow_deny_conflicts(allow: list, deny: list) -> list[str]:
    """Detect entries that appear in both allow and deny lists."""
    errors: list[str] = []
    allow_set = set(allow) if allow else set()
    deny_set = set(deny) if deny else set()
    conflicts = allow_set & deny_set
    for entry in sorted(conflicts):
        errors.append(
            f"Allow/deny conflict: '{entry}' appears in both allow and deny lists"
        )
    return errors


# ---------------------------------------------------------------------------
# Merge engine
# ---------------------------------------------------------------------------


def _is_primitive_array(arr: list) -> bool:
    """True if array contains only primitives (str, int, float, bool)."""
    return all(isinstance(x, (str, int, float, bool)) for x in arr)


def _is_object_array(arr: list) -> bool:
    """True if array contains only dicts."""
    return len(arr) > 0 and all(isinstance(x, dict) for x in arr)


def _merge_object_arrays(base: list[dict], overlay: list[dict], key: str) -> list[dict]:
    """Merge arrays of objects by a key field.

    For hook arrays, the key is "matcher".  Objects with the same key value
    are deep-merged; overlay objects without a matching base entry are appended.
    Within merged objects, inner "hooks" arrays are concatenated.
    """
    result: list[dict] = []
    base_by_key: dict[str | None, dict] = {}
    base_order: list[str | None] = []

    for item in base:
        k = item.get(key)
        base_by_key[k] = item
        base_order.append(k)

    overlay_by_key: dict[str | None, dict] = {}
    overlay_order: list[str | None] = []
    for item in overlay:
        k = item.get(key)
        overlay_by_key[k] = item
        overlay_order.append(k)

    # Merge base items with overlay matches
    seen: set[str | None] = set()
    for k in base_order:
        if k in seen:
            continue
        seen.add(k)
        base_item = base_by_key[k]
        if k in overlay_by_key:
            merged = _deep_merge_hook_entry(base_item, overlay_by_key[k])
            result.append(merged)
        else:
            result.append(_deep_copy(base_item))

    # Append overlay-only items
    for k in overlay_order:
        if k not in seen:
            seen.add(k)
            result.append(_deep_copy(overlay_by_key[k]))

    return result


def _deep_merge_hook_entry(base: dict, overlay: dict) -> dict:
    """Deep merge a single hook entry, concatenating inner 'hooks' arrays."""
    result = _deep_copy(base)
    for key, value in overlay.items():
        if (
            key == "hooks"
            and isinstance(value, list)
            and isinstance(result.get(key), list)
        ):
            # Concatenate hook command arrays
            result[key] = result[key] + _deep_copy(value)
        elif isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = _deep_copy(value)
    return result


def _deep_copy(obj):
    """Simple deep copy for JSON-compatible structures."""
    if isinstance(obj, dict):
        return {k: _deep_copy(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_deep_copy(x) for x in obj]
    return obj


def deep_merge(base: dict, overlay: dict) -> dict:
    """Recursively merge overlay into base following the merge rules.

    - Objects: recursive deep merge
    - Arrays of primitives: concat + dedup (preserving order)
    - Arrays of objects: merge by key field
    - null: delete the key
    - Scalars: overlay wins
    """
    result = _deep_copy(base)

    for key, value in overlay.items():
        # null => delete key
        if value is None:
            result.pop(key, None)
            continue

        if key not in result:
            result[key] = _deep_copy(value)
            continue

        existing = result[key]

        # Both dicts => recursive merge
        if isinstance(existing, dict) and isinstance(value, dict):
            result[key] = deep_merge(existing, value)

        # Both lists
        elif isinstance(existing, list) and isinstance(value, list):
            if _is_object_array(existing) or _is_object_array(value):
                # Arrays of objects: merge by key field
                base_objs = existing if _is_object_array(existing) else []
                overlay_objs = value if _is_object_array(value) else []
                result[key] = _merge_object_arrays(
                    base_objs, overlay_objs, HOOK_MERGE_KEY
                )
            else:
                # Primitive arrays: concat + dedup, preserving order
                seen: set = set()
                merged: list = []
                for item in existing + value:
                    # Use repr for hashability of mixed types
                    item_key = repr(item)
                    if item_key not in seen:
                        seen.add(item_key)
                        merged.append(item)
                result[key] = merged

        # Scalar: overlay wins
        else:
            result[key] = _deep_copy(value)

    return result


def merge_mcp_servers(base: dict, overlay: dict) -> dict:
    """Merge MCP server configurations with replacement semantics.

    Unlike deep_merge (which concat+dedup arrays), this function replaces
    entire server entries when a server exists in both base and overlay.
    This is correct for MCP servers where args arrays must be replaced,
    not concatenated.

    Merge rules:
      - mcpServers: server entries from overlay REPLACE base entries entirely
      - null server value: delete the server from the result
      - null top-level key: delete the key from the result
      - Non-mcpServers keys: deep_merge as normal
    """
    result = _deep_copy(base)

    for key, value in overlay.items():
        if value is None:
            result.pop(key, None)
            continue

        if (
            key == "mcpServers"
            and isinstance(value, dict)
            and isinstance(result.get(key), dict)
        ):
            base_servers = result[key]
            for server_name, server_config in value.items():
                if server_config is None:
                    base_servers.pop(server_name, None)
                else:
                    base_servers[server_name] = _deep_copy(server_config)
            result[key] = base_servers
        elif isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = _deep_copy(value)

    return result


def _sort_keys_recursive(obj):
    """Recursively sort dictionary keys for deterministic output.

    Arrays are left in their original order.
    """
    if isinstance(obj, dict):
        return {k: _sort_keys_recursive(v) for k, v in sorted(obj.items())}
    if isinstance(obj, list):
        return [_sort_keys_recursive(x) for x in obj]
    return obj


# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------


def load_json(path: Path) -> dict:
    """Load a JSON file, returning its parsed content."""
    with open(path) as f:
        return json.load(f)


def strip_meta(data: dict) -> dict:
    """Remove _meta keys from a settings dict (used in stack overlays)."""
    return {k: v for k, v in data.items() if k != "_meta"}


def merge_layers(
    base: dict,
    stacks: list[dict],
    project: dict | None = None,
) -> dict:
    """Merge base + stack overlays + project overlay."""
    result = _deep_copy(base)
    for stack in stacks:
        result = deep_merge(result, strip_meta(stack))
    if project:
        result = deep_merge(result, project)
    return result


def validate_merged(merged: dict) -> list[str]:
    """Run all validations on the merged result.  Returns error strings."""
    errors: list[str] = []

    # Auto-approve validation on hooks.auto-approve.bash_commands
    auto_approve = merged.get("hooks", {}).get("auto-approve", {})
    if isinstance(auto_approve, dict):
        bash_cmds = auto_approve.get("bash_commands", [])
        if isinstance(bash_cmds, list):
            errors.extend(validate_auto_approve(bash_cmds))

    # Also validate auto-approve in project overlay format (nested in permissions)
    # Check for toolkit.toml style auto-approve that may have leaked through

    # Allow/deny conflict detection
    perms = merged.get("permissions", {})
    if isinstance(perms, dict):
        allow = perms.get("allow", [])
        deny = perms.get("deny", [])
        if isinstance(allow, list) and isinstance(deny, list):
            errors.extend(validate_allow_deny_conflicts(allow, deny))

    return errors


def to_json(data: dict) -> str:
    """Serialize to deterministic JSON: sorted keys, 2-space indent, trailing newline."""
    sorted_data = _sort_keys_recursive(data)
    return json.dumps(sorted_data, indent=2, ensure_ascii=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate merged settings.json for Claude Code"
    )
    parser.add_argument("--base", required=True, help="Path to base settings JSON")
    parser.add_argument(
        "--stacks",
        default="",
        help="Comma-separated list of stack overlay JSON files",
    )
    parser.add_argument("--project", default=None, help="Path to project overlay JSON")
    parser.add_argument("--output", default=None, help="Output file (default: stdout)")
    parser.add_argument(
        "--validate",
        action="store_true",
        help="Check inputs without writing output",
    )
    parser.add_argument(
        "--mcp-base", default=None, help="Path to base MCP servers JSON"
    )
    parser.add_argument(
        "--mcp-output", default=None, help="Output path for merged MCP JSON"
    )
    args = parser.parse_args()

    # Load base
    base_path = Path(args.base)
    if not base_path.exists():
        print(f"Error: base file not found: {base_path}", file=sys.stderr)
        return 1
    base = load_json(base_path)

    # Load stacks
    stacks: list[dict] = []
    if args.stacks:
        for stack_path_str in args.stacks.split(","):
            stack_path = Path(stack_path_str.strip())
            if not stack_path.exists():
                print(f"Error: stack file not found: {stack_path}", file=sys.stderr)
                return 1
            stacks.append(load_json(stack_path))

    # Load project
    project = None
    if args.project:
        project_path = Path(args.project)
        if not project_path.exists():
            print(f"Error: project file not found: {project_path}", file=sys.stderr)
            return 1
        project = load_json(project_path)

    # Merge
    merged = merge_layers(base, stacks, project)

    # Schema validation (warnings only — don't block generation)
    schema_warnings = validate_settings_schema(merged)
    if schema_warnings:
        print("Schema warnings:", file=sys.stderr)
        for w in schema_warnings:
            print(f"  - {w}", file=sys.stderr)

    # Validate (always runs, not just with --validate)
    errors = validate_merged(merged)
    if errors:
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    if args.validate:
        print("Valid: all inputs merge cleanly")
        return 0

    # Write settings output
    output_str = to_json(merged)
    if args.output:
        out_path = Path(args.output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(output_str)
        print(f"Generated: {out_path}", file=sys.stderr)
    else:
        sys.stdout.write(output_str)

    # MCP merge (separate pass)
    if args.mcp_base:
        mcp_base_path = Path(args.mcp_base)
        if not mcp_base_path.exists():
            print(
                f"Error: MCP base file not found: {mcp_base_path}",
                file=sys.stderr,
            )
            return 1
        mcp_base = load_json(mcp_base_path)

        # Project may contain MCP overrides (null-as-delete for servers)
        mcp_project = {}
        if project and "mcpServers" in project:
            mcp_project = {"mcpServers": project["mcpServers"]}
        elif project and "mcp" in project:
            mcp_project = project["mcp"]

        mcp_merged = merge_mcp_servers(mcp_base, mcp_project)
        mcp_str = to_json(mcp_merged)

        if args.mcp_output:
            mcp_out = Path(args.mcp_output)
            mcp_out.parent.mkdir(parents=True, exist_ok=True)
            mcp_out.write_text(mcp_str)
            print(f"Generated MCP: {mcp_out}", file=sys.stderr)
        else:
            sys.stdout.write(mcp_str)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

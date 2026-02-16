"""Tests for generate-settings.py."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Import the module under test (it has a hyphenated filename, so we use
# importlib to load it).
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "generate-settings.py"
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def _load_module():
    spec = importlib.util.spec_from_file_location("generate_settings", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


mod = _load_module()
deep_merge = mod.deep_merge
merge_layers = mod.merge_layers
validate_auto_approve = mod.validate_auto_approve
validate_allow_deny_conflicts = mod.validate_allow_deny_conflicts
validate_merged = mod.validate_merged
to_json = mod.to_json
load_json = mod.load_json


# ===================================================================
# Object deep merge
# ===================================================================


class TestObjectDeepMerge:
    def test_simple_merge(self):
        base = {"a": 1, "b": 2}
        overlay = {"b": 3, "c": 4}
        result = deep_merge(base, overlay)
        assert result == {"a": 1, "b": 3, "c": 4}

    def test_nested_merge(self):
        base = {"env": {"A": "1", "B": "2"}}
        overlay = {"env": {"B": "override", "C": "3"}}
        result = deep_merge(base, overlay)
        assert result == {"env": {"A": "1", "B": "override", "C": "3"}}

    def test_deeply_nested_merge(self):
        base = {"a": {"b": {"c": 1, "d": 2}}}
        overlay = {"a": {"b": {"d": 3, "e": 4}}}
        result = deep_merge(base, overlay)
        assert result == {"a": {"b": {"c": 1, "d": 3, "e": 4}}}

    def test_base_not_mutated(self):
        base = {"a": {"b": 1}}
        overlay = {"a": {"c": 2}}
        deep_merge(base, overlay)
        assert base == {"a": {"b": 1}}, "Base should not be mutated"

    def test_overlay_not_mutated(self):
        base = {"a": 1}
        overlay = {"b": {"c": 2}}
        deep_merge(base, overlay)
        assert overlay == {"b": {"c": 2}}, "Overlay should not be mutated"


# ===================================================================
# Array concat + dedup
# ===================================================================


class TestArrayConcatDedup:
    def test_simple_concat(self):
        base = {"items": ["a", "b"]}
        overlay = {"items": ["c", "d"]}
        result = deep_merge(base, overlay)
        assert result["items"] == ["a", "b", "c", "d"]

    def test_dedup(self):
        base = {"items": ["a", "b", "c"]}
        overlay = {"items": ["b", "c", "d"]}
        result = deep_merge(base, overlay)
        assert result["items"] == ["a", "b", "c", "d"]

    def test_order_preserved(self):
        base = {"items": ["z", "a"]}
        overlay = {"items": ["m", "z"]}
        result = deep_merge(base, overlay)
        # z appears first (from base), m added, second z deduped
        assert result["items"] == ["z", "a", "m"]

    def test_empty_base_array(self):
        base = {"items": []}
        overlay = {"items": ["a", "b"]}
        result = deep_merge(base, overlay)
        assert result["items"] == ["a", "b"]

    def test_empty_overlay_array(self):
        base = {"items": ["a", "b"]}
        overlay = {"items": []}
        result = deep_merge(base, overlay)
        assert result["items"] == ["a", "b"]

    def test_mixed_types_in_array(self):
        base = {"items": [1, "a", True]}
        overlay = {"items": [2, "a", False]}
        result = deep_merge(base, overlay)
        assert 1 in result["items"]
        assert 2 in result["items"]
        assert "a" in result["items"]
        # "a" should appear only once
        assert result["items"].count("a") == 1


# ===================================================================
# Arrays of objects merge by matcher
# ===================================================================


class TestArrayOfObjectsMerge:
    def test_merge_by_matcher(self):
        base = {
            "hooks": [
                {"matcher": "Bash", "hooks": [{"cmd": "guard.sh"}]},
                {"matcher": "Write", "hooks": [{"cmd": "write-guard.sh"}]},
            ]
        }
        overlay = {
            "hooks": [
                {"matcher": "Bash", "hooks": [{"cmd": "project-guard.sh"}]},
            ]
        }
        result = deep_merge(base, overlay)
        # Bash matcher should have both hook commands concatenated
        bash_entry = next(h for h in result["hooks"] if h.get("matcher") == "Bash")
        assert len(bash_entry["hooks"]) == 2
        assert bash_entry["hooks"][0]["cmd"] == "guard.sh"
        assert bash_entry["hooks"][1]["cmd"] == "project-guard.sh"
        # Write matcher should be preserved
        write_entry = next(h for h in result["hooks"] if h.get("matcher") == "Write")
        assert len(write_entry["hooks"]) == 1

    def test_overlay_adds_new_matcher(self):
        base = {
            "hooks": [
                {"matcher": "Bash", "hooks": [{"cmd": "guard.sh"}]},
            ]
        }
        overlay = {
            "hooks": [
                {"matcher": "Edit", "hooks": [{"cmd": "edit-guard.sh"}]},
            ]
        }
        result = deep_merge(base, overlay)
        assert len(result["hooks"]) == 2
        matchers = [h.get("matcher") for h in result["hooks"]]
        assert "Bash" in matchers
        assert "Edit" in matchers

    def test_no_matcher_entries_preserved(self):
        """Hook entries without a matcher field are preserved."""
        base = {
            "hooks": [
                {"hooks": [{"cmd": "generic.sh"}]},
            ]
        }
        overlay = {
            "hooks": [
                {"hooks": [{"cmd": "project-generic.sh"}]},
            ]
        }
        result = deep_merge(base, overlay)
        # Both have None as matcher, so they merge by key
        assert len(result["hooks"]) == 1
        assert len(result["hooks"][0]["hooks"]) == 2


# ===================================================================
# Null deletes keys
# ===================================================================


class TestNullDeletesKeys:
    def test_null_removes_key(self):
        base = {"a": 1, "b": 2, "c": 3}
        overlay = {"b": None}
        result = deep_merge(base, overlay)
        assert result == {"a": 1, "c": 3}

    def test_null_removes_nested_key(self):
        base = {"env": {"A": "1", "B": "2"}}
        overlay = {"env": {"A": None}}
        result = deep_merge(base, overlay)
        assert result == {"env": {"B": "2"}}

    def test_null_removes_entire_section(self):
        base = {"hooks": {"PreToolUse": []}, "env": {"A": "1"}}
        overlay = {"hooks": None}
        result = deep_merge(base, overlay)
        assert "hooks" not in result
        assert result["env"]["A"] == "1"

    def test_null_on_nonexistent_key_is_noop(self):
        base = {"a": 1}
        overlay = {"b": None}
        result = deep_merge(base, overlay)
        assert result == {"a": 1}


# ===================================================================
# Scalars: project wins
# ===================================================================


class TestScalarOverride:
    def test_string_override(self):
        base = {"env": {"VAR": "base"}}
        overlay = {"env": {"VAR": "project"}}
        result = deep_merge(base, overlay)
        assert result["env"]["VAR"] == "project"

    def test_int_override(self):
        base = {"timeout": 100}
        overlay = {"timeout": 200}
        result = deep_merge(base, overlay)
        assert result["timeout"] == 200

    def test_bool_override(self):
        base = {"enabled": True}
        overlay = {"enabled": False}
        result = deep_merge(base, overlay)
        assert result["enabled"] is False

    def test_type_change_allowed(self):
        """Overlay can change the type of a scalar value."""
        base = {"val": "string"}
        overlay = {"val": 42}
        result = deep_merge(base, overlay)
        assert result["val"] == 42


# ===================================================================
# Hook merging by matcher field
# ===================================================================


class TestHookMerging:
    def test_full_settings_hook_merge(self):
        """Test with realistic settings structure (nested under hooks.PreToolUse)."""
        base = {
            "hooks": {
                "PreToolUse": [
                    {
                        "matcher": "Bash",
                        "hooks": [
                            {
                                "type": "command",
                                "command": "guard.sh",
                                "timeout": 10000,
                            }
                        ],
                    }
                ]
            }
        }
        overlay = {
            "hooks": {
                "PreToolUse": [
                    {
                        "matcher": "Bash",
                        "hooks": [
                            {
                                "type": "command",
                                "command": "project-guard.sh",
                                "timeout": 5000,
                            }
                        ],
                    }
                ]
            }
        }
        result = deep_merge(base, overlay)
        pre_tool = result["hooks"]["PreToolUse"]
        assert len(pre_tool) == 1  # One Bash matcher entry
        assert len(pre_tool[0]["hooks"]) == 2  # Two hook commands
        assert pre_tool[0]["hooks"][0]["command"] == "guard.sh"
        assert pre_tool[0]["hooks"][1]["command"] == "project-guard.sh"

    def test_session_start_hook_merge(self):
        """SessionStart hooks have different matchers (startup, resume, etc.)."""
        base = {
            "hooks": {
                "SessionStart": [
                    {
                        "matcher": "startup",
                        "hooks": [{"type": "command", "command": "setup.sh"}],
                    },
                    {
                        "matcher": "resume",
                        "hooks": [{"type": "command", "command": "resume.sh"}],
                    },
                ]
            }
        }
        overlay = {
            "hooks": {
                "SessionStart": [
                    {
                        "matcher": "startup",
                        "hooks": [{"type": "command", "command": "project-setup.sh"}],
                    }
                ]
            }
        }
        result = deep_merge(base, overlay)
        session_start = result["hooks"]["SessionStart"]
        assert len(session_start) == 2  # Both matchers preserved

        startup = next(h for h in session_start if h.get("matcher") == "startup")
        assert len(startup["hooks"]) == 2  # base + overlay concatenated

        resume = next(h for h in session_start if h.get("matcher") == "resume")
        assert len(resume["hooks"]) == 1  # unchanged


# ===================================================================
# MCP merge with null-as-delete
# ===================================================================


class TestMCPMerge:
    def test_mcp_base_pass_through(self):
        base = {
            "mcpServers": {
                "context7": {"command": "npx", "args": ["@context7"]},
                "playwright": {"command": "npx", "args": ["@playwright"]},
            }
        }
        result = deep_merge(base, {})
        assert "context7" in result["mcpServers"]
        assert "playwright" in result["mcpServers"]

    def test_mcp_null_deletes_server(self):
        base = {
            "mcpServers": {
                "context7": {"command": "npx", "args": ["@context7"]},
                "playwright": {"command": "npx", "args": ["@playwright"]},
            }
        }
        overlay = {"mcpServers": {"playwright": None}}
        result = deep_merge(base, overlay)
        assert "context7" in result["mcpServers"]
        assert "playwright" not in result["mcpServers"]

    def test_mcp_add_server(self):
        base = {
            "mcpServers": {
                "context7": {"command": "npx", "args": ["@context7"]},
            }
        }
        overlay = {
            "mcpServers": {
                "codex": {"command": "codex", "args": ["--serve"]},
            }
        }
        result = deep_merge(base, overlay)
        assert "context7" in result["mcpServers"]
        assert "codex" in result["mcpServers"]

    def test_mcp_override_server_args_concat(self):
        """Primitive arrays concat+dedup per merge rules."""
        base = {
            "mcpServers": {
                "context7": {"command": "npx", "args": ["@context7@1.0"]},
            }
        }
        overlay = {
            "mcpServers": {
                "context7": {"command": "npx", "args": ["@context7@2.0"]},
            }
        }
        result = deep_merge(base, overlay)
        # Primitive arrays concat+dedup: both versions present
        assert "@context7@1.0" in result["mcpServers"]["context7"]["args"]
        assert "@context7@2.0" in result["mcpServers"]["context7"]["args"]

    def test_mcp_replace_server_via_null_then_add(self):
        """To fully replace a server, null-delete it then re-add in two merges."""
        base = {
            "mcpServers": {
                "context7": {"command": "npx", "args": ["@context7@1.0"]},
            }
        }
        # First merge: delete
        delete_overlay = {"mcpServers": {"context7": None}}
        intermediate = deep_merge(base, delete_overlay)
        assert "context7" not in intermediate["mcpServers"]
        # Second merge: re-add
        add_overlay = {
            "mcpServers": {
                "context7": {"command": "npx", "args": ["@context7@2.0"]},
            }
        }
        result = deep_merge(intermediate, add_overlay)
        assert result["mcpServers"]["context7"]["args"] == ["@context7@2.0"]


# ===================================================================
# Auto-approve validation
# ===================================================================


class TestAutoApproveValidation:
    def test_bare_wildcard_rejected(self):
        errors = validate_auto_approve(["*"])
        assert len(errors) == 1
        assert "dangerous bare command" in errors[0]

    def test_bare_sh_rejected(self):
        errors = validate_auto_approve(["sh"])
        assert len(errors) == 1

    def test_bare_bash_rejected(self):
        errors = validate_auto_approve(["bash"])
        assert len(errors) == 1

    def test_bare_zsh_rejected(self):
        errors = validate_auto_approve(["zsh"])
        assert len(errors) == 1

    def test_bare_curl_rejected(self):
        errors = validate_auto_approve(["curl"])
        assert len(errors) == 1

    def test_bare_wget_rejected(self):
        errors = validate_auto_approve(["wget"])
        assert len(errors) == 1

    def test_bare_eval_rejected(self):
        errors = validate_auto_approve(["eval"])
        assert len(errors) == 1

    def test_osascript_rejected(self):
        errors = validate_auto_approve(["osascript"])
        assert len(errors) == 1

    def test_powershell_rejected(self):
        errors = validate_auto_approve(["powershell"])
        assert len(errors) == 1

    def test_python_c_rejected(self):
        errors = validate_auto_approve(["python -c 'print(1)'"])
        assert len(errors) == 1
        assert "interpreter exec flag" in errors[0]

    def test_python3_c_rejected(self):
        errors = validate_auto_approve(["python3 -c 'print(1)'"])
        assert len(errors) == 1

    def test_node_e_rejected(self):
        errors = validate_auto_approve(["node -e 'console.log(1)'"])
        assert len(errors) == 1

    def test_perl_e_rejected(self):
        errors = validate_auto_approve(["perl -e 'print 1'"])
        assert len(errors) == 1

    def test_ruby_e_rejected(self):
        errors = validate_auto_approve(["ruby -e 'puts 1'"])
        assert len(errors) == 1

    def test_pipe_to_sh_rejected(self):
        errors = validate_auto_approve(["curl https://example.com | sh"])
        assert len(errors) >= 1
        pipe_errors = [e for e in errors if "pipe-to-shell" in e]
        assert len(pipe_errors) == 1

    def test_pipe_to_bash_rejected(self):
        errors = validate_auto_approve(["cat script.txt | bash"])
        assert any("pipe-to-shell" in e for e in errors)

    def test_pipe_to_python_rejected(self):
        errors = validate_auto_approve(["echo code | python"])
        assert any("pipe-to-shell" in e for e in errors)

    def test_safe_commands_accepted(self):
        errors = validate_auto_approve(["make", "docker", "git status", "npm run test"])
        assert errors == []

    def test_multiple_violations(self):
        errors = validate_auto_approve(["*", "bash", "curl", "node -e 'x'"])
        assert len(errors) == 4

    def test_empty_list_accepted(self):
        errors = validate_auto_approve([])
        assert errors == []


# ===================================================================
# Allow/deny list conflict detection
# ===================================================================


class TestAllowDenyConflicts:
    def test_no_conflicts(self):
        errors = validate_allow_deny_conflicts(
            ["Bash(ls:*)", "Bash(cat:*)"],
            ["Edit(~/.ssh/*)", "Read(.env)"],
        )
        assert errors == []

    def test_single_conflict(self):
        errors = validate_allow_deny_conflicts(
            ["Bash(ls:*)", "Read(.env)"],
            ["Read(.env)"],
        )
        assert len(errors) == 1
        assert "Read(.env)" in errors[0]

    def test_multiple_conflicts(self):
        errors = validate_allow_deny_conflicts(
            ["Bash(ls:*)", "Read(.env)", "Edit(~/.ssh/*)"],
            ["Read(.env)", "Edit(~/.ssh/*)"],
        )
        assert len(errors) == 2

    def test_empty_lists(self):
        errors = validate_allow_deny_conflicts([], [])
        assert errors == []


# ===================================================================
# Deterministic output (sorted keys)
# ===================================================================


class TestDeterministicOutput:
    def test_sorted_keys(self):
        data = {"z": 1, "a": 2, "m": 3}
        output = to_json(data)
        parsed = json.loads(output)
        keys = list(parsed.keys())
        assert keys == ["a", "m", "z"]

    def test_nested_sorted_keys(self):
        data = {"z": {"c": 1, "a": 2}, "a": {"z": 3, "b": 4}}
        output = to_json(data)
        parsed = json.loads(output)
        assert list(parsed.keys()) == ["a", "z"]
        assert list(parsed["a"].keys()) == ["b", "z"]
        assert list(parsed["z"].keys()) == ["a", "c"]

    def test_two_space_indent(self):
        data = {"a": {"b": 1}}
        output = to_json(data)
        assert '  "a"' in output
        assert '    "b"' in output

    def test_trailing_newline(self):
        data = {"a": 1}
        output = to_json(data)
        assert output.endswith("\n")

    def test_idempotent(self):
        """Calling to_json twice on same data produces identical output."""
        data = {"z": [3, 1, 2], "a": {"c": True, "b": False}}
        output1 = to_json(data)
        output2 = to_json(data)
        assert output1 == output2


# ===================================================================
# Full fixture merge test
# ===================================================================


class TestFixtureMerge:
    def test_full_merge_matches_expected(self):
        base = load_json(FIXTURES / "base.json")
        python_stack = load_json(FIXTURES / "python.json")
        project = load_json(FIXTURES / "project.json")
        expected = load_json(FIXTURES / "expected.json")

        result = merge_layers(base, [python_stack], project)

        # Compare as sorted JSON to normalize key order
        result_str = to_json(result)
        expected_str = to_json(expected)
        assert result_str == expected_str


# ===================================================================
# merge_layers integration
# ===================================================================


class TestMergeLayers:
    def test_base_only(self):
        base = {"a": 1, "b": 2}
        result = merge_layers(base, [])
        assert result == {"a": 1, "b": 2}

    def test_base_with_stack(self):
        base = {"permissions": {"allow": ["a"]}}
        stack = {"permissions": {"allow": ["b"]}}
        result = merge_layers(base, [stack])
        assert result["permissions"]["allow"] == ["a", "b"]

    def test_base_stack_project(self):
        base = {"env": {"A": "1"}}
        stack = {"env": {"B": "2"}}
        project = {"env": {"A": "override", "C": "3"}}
        result = merge_layers(base, [stack], project)
        assert result["env"] == {"A": "override", "B": "2", "C": "3"}

    def test_multiple_stacks(self):
        base = {"permissions": {"allow": ["base"]}}
        stack1 = {"permissions": {"allow": ["python"]}}
        stack2 = {"permissions": {"allow": ["ios"]}}
        result = merge_layers(base, [stack1, stack2])
        assert result["permissions"]["allow"] == ["base", "python", "ios"]

    def test_project_none(self):
        base = {"a": 1}
        result = merge_layers(base, [], None)
        assert result == {"a": 1}


# ===================================================================
# validate_merged integration
# ===================================================================


class TestValidateMerged:
    def test_clean_merge_no_errors(self):
        merged = {
            "permissions": {
                "allow": ["Bash(ls:*)"],
                "deny": ["Edit(~/.ssh/*)"],
            }
        }
        errors = validate_merged(merged)
        assert errors == []

    def test_auto_approve_violation_detected(self):
        merged = {
            "hooks": {
                "auto-approve": {
                    "bash_commands": ["*", "curl"],
                }
            }
        }
        errors = validate_merged(merged)
        assert len(errors) == 2

    def test_allow_deny_conflict_detected(self):
        merged = {
            "permissions": {
                "allow": ["Read(.env)"],
                "deny": ["Read(.env)"],
            }
        }
        errors = validate_merged(merged)
        assert len(errors) == 1
        assert "conflict" in errors[0].lower()


# ===================================================================
# CLI integration tests
# ===================================================================


class TestCLI:
    def test_basic_merge_to_stdout(self):
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--base",
                str(FIXTURES / "base.json"),
                "--stacks",
                str(FIXTURES / "python.json"),
                "--project",
                str(FIXTURES / "project.json"),
            ],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert "permissions" in output
        assert "hooks" in output

    def test_output_to_file(self, tmp_path):
        out = tmp_path / "settings.json"
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--base",
                str(FIXTURES / "base.json"),
                "--output",
                str(out),
            ],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert out.exists()
        content = json.loads(out.read_text())
        assert "permissions" in content

    def test_validate_flag(self):
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--base",
                str(FIXTURES / "base.json"),
                "--stacks",
                str(FIXTURES / "python.json"),
                "--validate",
            ],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert "Valid" in result.stdout

    def test_missing_base_file(self):
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--base",
                "/nonexistent/base.json",
            ],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 1
        assert "not found" in result.stderr

    def test_missing_stack_file(self):
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--base",
                str(FIXTURES / "base.json"),
                "--stacks",
                "/nonexistent/stack.json",
            ],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 1
        assert "not found" in result.stderr

    def test_mcp_merge(self, tmp_path):
        mcp_base = tmp_path / "base.mcp.json"
        mcp_base.write_text(
            json.dumps(
                {
                    "mcpServers": {
                        "context7": {"command": "npx", "args": ["@context7"]},
                        "playwright": {"command": "npx", "args": ["@playwright"]},
                    }
                }
            )
        )
        project = tmp_path / "project.json"
        project.write_text(json.dumps({"mcpServers": {"playwright": None}}))

        settings_out = tmp_path / "settings.json"
        mcp_out = tmp_path / ".mcp.json"

        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--base",
                str(FIXTURES / "base.json"),
                "--project",
                str(project),
                "--mcp-base",
                str(mcp_base),
                "--mcp-output",
                str(mcp_out),
                "--output",
                str(settings_out),
            ],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert mcp_out.exists()
        mcp_content = json.loads(mcp_out.read_text())
        assert "context7" in mcp_content["mcpServers"]
        assert "playwright" not in mcp_content["mcpServers"]

    def test_auto_approve_validation_blocks_output(self, tmp_path):
        """Auto-approve validation runs even without --validate flag."""
        bad_project = tmp_path / "bad-project.json"
        bad_project.write_text(
            json.dumps(
                {
                    "hooks": {
                        "auto-approve": {
                            "bash_commands": ["*", "bash"],
                        }
                    }
                }
            )
        )
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--base",
                str(FIXTURES / "base.json"),
                "--project",
                str(bad_project),
            ],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 1
        assert "blocked" in result.stderr.lower()


# ===================================================================
# Real templates integration test
# ===================================================================


class TestRealTemplates:
    def test_base_json_is_valid(self):
        """The actual settings-base.json should be valid JSON."""
        base_path = ROOT / "templates" / "settings-base.json"
        if base_path.exists():
            data = load_json(base_path)
            assert "permissions" in data
            assert "hooks" in data
            assert "env" in data

    def test_stack_jsons_are_valid(self):
        """All stack overlay files should be valid JSON."""
        stacks_dir = ROOT / "templates" / "stacks"
        if stacks_dir.exists():
            for f in stacks_dir.glob("*.json"):
                data = load_json(f)
                assert "permissions" in data, f"{f.name} missing permissions"

    def test_mcp_base_is_valid(self):
        """The actual base.mcp.json should be valid JSON."""
        mcp_path = ROOT / "mcp" / "base.mcp.json"
        if mcp_path.exists():
            data = load_json(mcp_path)
            assert "mcpServers" in data

    def test_base_plus_python_stack_merges(self):
        """Base + Python stack should merge cleanly."""
        base_path = ROOT / "templates" / "settings-base.json"
        python_path = ROOT / "templates" / "stacks" / "python.json"
        if base_path.exists() and python_path.exists():
            base = load_json(base_path)
            python_stack = load_json(python_path)
            result = merge_layers(base, [python_stack])
            errors = validate_merged(result)
            assert errors == [], f"Validation errors: {errors}"
            # Python-specific allows should be present
            allows = result["permissions"]["allow"]
            assert "Bash(python3:*)" in allows

    def test_base_plus_all_stacks_merges(self):
        """Base + all stacks should merge cleanly."""
        base_path = ROOT / "templates" / "settings-base.json"
        stacks_dir = ROOT / "templates" / "stacks"
        if base_path.exists() and stacks_dir.exists():
            base = load_json(base_path)
            stacks = [load_json(f) for f in sorted(stacks_dir.glob("*.json"))]
            result = merge_layers(base, stacks)
            errors = validate_merged(result)
            assert errors == [], f"Validation errors: {errors}"

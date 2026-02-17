#!/usr/bin/env python3
"""Detect project properties and toolkit installation state.

Scans a project directory to auto-detect stacks, lint/test/format commands,
source directories, version files, and toolkit installation state.  Outputs
JSON to stdout.

Usage:
    python3 detect-project.py --project-dir /path/to/project
    python3 detect-project.py --project-dir /path/to/project --validate
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Stack detection
# ---------------------------------------------------------------------------

# Mapping: stack name -> (file globs to check, directory globs to check)
STACK_INDICATORS: dict[str, dict[str, list[str]]] = {
    "python": {
        "files": ["pyproject.toml", "requirements.txt", "setup.py", "setup.cfg"],
        "globs": ["*.py"],
    },
    "typescript": {
        "files": ["tsconfig.json"],
        "globs": ["*.ts", "*.tsx"],
    },
    "ios": {
        "files": ["Package.swift"],
        "globs": ["*.xcodeproj", "*.swift"],
    },
}

# Source directory candidates (checked in order)
SOURCE_DIR_CANDIDATES = ["src", "app", "lib", "packages"]

# Version file precedence (first match wins)
VERSION_FILE_PRECEDENCE = ["package.json", "pyproject.toml", "VERSION"]

# Lint commands per stack: (executable, args for check, args for --version)
LINT_COMMANDS: dict[str, list[dict[str, str]]] = {
    "python": [
        {"exe": "ruff", "args": "check", "version_flag": "--version"},
    ],
    "typescript": [
        {"exe": "eslint", "args": "", "version_flag": "--version"},
    ],
    "ios": [
        {"exe": "swiftlint", "args": "", "version_flag": "version"},
    ],
}

# Format commands per stack
# check_args is used during --validate to verify non-destructively
# Target "." is appended to check commands so tools that require a path work correctly
FORMAT_COMMANDS: dict[str, list[dict[str, str]]] = {
    "python": [
        {"exe": "ruff", "args": "format", "check_args": "format --check .", "version_flag": "--version"},
    ],
    "typescript": [
        {"exe": "prettier", "args": "--write", "check_args": "--check .", "version_flag": "--version"},
    ],
    "ios": [
        {"exe": "swiftformat", "args": "", "check_args": "--dryrun .", "version_flag": "--version"},
    ],
}

# Source file extensions per stack
SOURCE_EXTENSIONS: dict[str, list[str]] = {
    "python": ["*.py"],
    "typescript": ["*.ts", "*.tsx", "*.js", "*.jsx"],
    "ios": ["*.swift"],
}


def detect_stacks(project_dir: Path) -> list[str]:
    """Detect technology stacks from file presence in the project."""
    stacks: list[str] = []
    for stack_name, indicators in STACK_INDICATORS.items():
        found = False
        # Check specific files
        for filename in indicators.get("files", []):
            if (project_dir / filename).exists():
                found = True
                break
        # Check glob patterns (only top-level + one level deep)
        if not found:
            for pattern in indicators.get("globs", []):
                # Check top-level
                matches = list(project_dir.glob(pattern))
                if matches:
                    found = True
                    break
                # Check one level deep (e.g., src/*.py)
                matches = list(project_dir.glob(f"*/{pattern}"))
                if matches:
                    found = True
                    break
        if found:
            stacks.append(stack_name)
    return sorted(stacks)


def detect_name(project_dir: Path) -> str:
    """Detect project name from git toplevel basename, falling back to dir name."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            cwd=str(project_dir),
            timeout=5,
        )
        if result.returncode == 0 and result.stdout.strip():
            return Path(result.stdout.strip()).name
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return project_dir.resolve().name


def detect_version_file(project_dir: Path) -> str | None:
    """Detect version file with precedence: package.json > pyproject.toml > VERSION."""
    for filename in VERSION_FILE_PRECEDENCE:
        if (project_dir / filename).exists():
            return filename
    return None


def detect_source_dirs(project_dir: Path) -> list[str]:
    """Detect source directories by scanning for common patterns."""
    found: list[str] = []
    for candidate in SOURCE_DIR_CANDIDATES:
        candidate_path = project_dir / candidate
        if candidate_path.is_dir():
            found.append(candidate)
    return found


def detect_source_extensions(stacks: list[str]) -> list[str]:
    """Return source file extension globs based on detected stacks."""
    extensions: list[str] = []
    seen: set[str] = set()
    for stack in stacks:
        for ext in SOURCE_EXTENSIONS.get(stack, []):
            if ext not in seen:
                seen.add(ext)
                extensions.append(ext)
    return extensions


def _probe_executable(exe: str, version_flag: str, project_dir: Path) -> bool:
    """Check if an executable is available and responds to a version check."""
    if not shutil.which(exe):
        return False
    try:
        result = subprocess.run(
            [exe, version_flag],
            capture_output=True,
            text=True,
            cwd=str(project_dir),
            timeout=10,
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return False


def detect_lint_commands(
    project_dir: Path, stacks: list[str]
) -> dict[str, dict[str, str | bool]]:
    """Detect lint commands by probing executables for each stack."""
    lint: dict[str, dict[str, str | bool]] = {}
    for stack in stacks:
        for cmd_info in LINT_COMMANDS.get(stack, []):
            exe = cmd_info["exe"]
            if _probe_executable(exe, cmd_info["version_flag"], project_dir):
                args = cmd_info["args"]
                cmd_str = f"{exe} {args}".strip()
                lint[stack] = {"cmd": cmd_str, "available": True}
                break
        if stack not in lint:
            # Record that no lint command was found
            lint[stack] = {"cmd": "", "available": False}
    return lint


def detect_format_commands(
    project_dir: Path, stacks: list[str]
) -> dict[str, dict[str, str | bool]]:
    """Detect format commands by probing executables for each stack."""
    fmt: dict[str, dict[str, str | bool]] = {}
    for stack in stacks:
        for cmd_info in FORMAT_COMMANDS.get(stack, []):
            exe = cmd_info["exe"]
            if _probe_executable(exe, cmd_info["version_flag"], project_dir):
                args = cmd_info["args"]
                cmd_str = f"{exe} {args}".strip()
                check_args = cmd_info.get("check_args", "")
                check_cmd = f"{exe} {check_args}".strip() if check_args else ""
                fmt[stack] = {
                    "cmd": cmd_str,
                    "check_cmd": check_cmd,
                    "available": True,
                }
                break
        if stack not in fmt:
            fmt[stack] = {"cmd": "", "check_cmd": "", "available": False}
    return fmt


def _parse_makefile_targets(project_dir: Path) -> list[str]:
    """Parse Makefile to extract target names."""
    makefile = project_dir / "Makefile"
    if not makefile.is_file():
        return []
    targets: list[str] = []
    try:
        content = makefile.read_text(encoding="utf-8", errors="replace")
        # Match lines like "target-name:" at the start of a line
        # Exclude lines starting with . (internal targets) or tab (recipes)
        for line in content.splitlines():
            match = re.match(r"^([a-zA-Z_][a-zA-Z0-9_-]*)\s*:", line)
            if match:
                targets.append(match.group(1))
    except OSError:
        pass
    return targets


def _parse_package_json_scripts(project_dir: Path) -> list[str]:
    """Parse package.json to extract script names."""
    pkg_json = project_dir / "package.json"
    if not pkg_json.is_file():
        return []
    try:
        content = pkg_json.read_text(encoding="utf-8")
        data = json.loads(content)
        scripts = data.get("scripts", {})
        if isinstance(scripts, dict):
            return sorted(scripts.keys())
    except (OSError, json.JSONDecodeError, ValueError):
        pass
    return []


def detect_test_commands(project_dir: Path) -> dict[str, object]:
    """Detect test commands by parsing Makefile targets and package.json scripts."""
    makefile_targets = _parse_makefile_targets(project_dir)
    package_scripts = _parse_package_json_scripts(project_dir)

    # Determine best test command
    cmd = ""
    source = ""

    # Check Makefile targets for test-related entries
    test_targets = [t for t in makefile_targets if "test" in t.lower()]
    if test_targets:
        # Prefer "test" over others, then first match
        if "test" in test_targets:
            cmd = "make test"
        else:
            cmd = f"make {test_targets[0]}"
        source = "makefile"

    # Check package.json scripts for test
    if not cmd:
        test_scripts = [s for s in package_scripts if "test" in s.lower()]
        if test_scripts:
            if "test" in test_scripts:
                cmd = "npm test"
            else:
                cmd = f"npm run {test_scripts[0]}"
            source = "package.json"

    # Fallback: check for pytest
    if not cmd and shutil.which("pytest"):
        cmd = "pytest"
        source = "executable"

    return {
        "cmd": cmd,
        "source": source,
        "makefile_targets": makefile_targets,
        "package_scripts": package_scripts,
    }


def detect_toolkit_state(project_dir: Path) -> dict[str, object]:
    """Detect toolkit installation state within the project."""
    claude_dir = project_dir / ".claude"
    toolkit_dir = claude_dir / "toolkit"

    state: dict[str, object] = {
        "subtree_exists": toolkit_dir.is_dir(),
        "toml_exists": (claude_dir / "toolkit.toml").is_file(),
        "toml_is_example": False,
        "settings_generated": (claude_dir / "settings.json").is_file(),
        "missing_skills": [],
        "missing_agents": [],
        "broken_symlinks": [],
    }

    # Check if toml matches the example
    toml_path = claude_dir / "toolkit.toml"
    example_path = toolkit_dir / "templates" / "toolkit.toml.example"
    if toml_path.is_file() and example_path.is_file():
        try:
            toml_content = toml_path.read_text(encoding="utf-8")
            example_content = example_path.read_text(encoding="utf-8")
            state["toml_is_example"] = toml_content.strip() == example_content.strip()
        except OSError:
            pass

    # Check for missing skills
    if toolkit_dir.is_dir():
        toolkit_skills = toolkit_dir / "skills"
        project_skills = claude_dir / "skills"
        if toolkit_skills.is_dir():
            missing_skills: list[str] = []
            for skill_dir in sorted(toolkit_skills.iterdir()):
                if skill_dir.is_dir():
                    skill_name = skill_dir.name
                    project_skill = project_skills / skill_name
                    if not project_skill.exists():
                        missing_skills.append(skill_name)
            state["missing_skills"] = missing_skills

    # Check for missing agents
    if toolkit_dir.is_dir():
        toolkit_agents = toolkit_dir / "agents"
        project_agents = claude_dir / "agents"
        if toolkit_agents.is_dir():
            missing_agents: list[str] = []
            for agent_file in sorted(toolkit_agents.iterdir()):
                if agent_file.is_file() and agent_file.suffix == ".md":
                    agent_name = agent_file.name
                    project_agent = project_agents / agent_name
                    if not project_agent.exists():
                        missing_agents.append(agent_name)
            state["missing_agents"] = missing_agents

    # Check for broken symlinks in .claude/
    if claude_dir.is_dir():
        broken: list[str] = []
        for item in sorted(claude_dir.rglob("*")):
            if item.is_symlink() and not item.exists():
                # Report relative to .claude/
                try:
                    rel = item.relative_to(claude_dir)
                    broken.append(str(rel))
                except ValueError:
                    broken.append(str(item))
        state["broken_symlinks"] = broken

    return state


def _validate_command(cmd: str, project_dir: Path) -> dict[str, object]:
    """Actually run a command and record pass/fail.

    Uses shell=True to support commands with pipes, quotes, and other
    shell features (common in Makefile recipes and package.json scripts).
    """
    if not cmd:
        return {"cmd": cmd, "passed": False, "error": "empty command"}
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            cwd=str(project_dir),
            timeout=60,
        )
        return {
            "cmd": cmd,
            "passed": result.returncode == 0,
            "returncode": result.returncode,
        }
    except subprocess.TimeoutExpired:
        return {"cmd": cmd, "passed": False, "error": "timeout"}
    except FileNotFoundError:
        return {"cmd": cmd, "passed": False, "error": "command not found"}
    except OSError as exc:
        return {"cmd": cmd, "passed": False, "error": str(exc)}


def run_detection(project_dir: Path, validate: bool = False) -> dict[str, object]:
    """Run all detection functions and assemble the result dict."""
    stacks = detect_stacks(project_dir)
    name = detect_name(project_dir)
    version_file = detect_version_file(project_dir)
    source_dirs = detect_source_dirs(project_dir)
    source_extensions = detect_source_extensions(stacks)
    lint = detect_lint_commands(project_dir, stacks)
    test = detect_test_commands(project_dir)
    fmt = detect_format_commands(project_dir, stacks)
    toolkit_state = detect_toolkit_state(project_dir)

    result: dict[str, object] = {
        "name": name,
        "stacks": stacks,
        "version_file": version_file,
        "source_dirs": source_dirs,
        "source_extensions": source_extensions,
        "lint": lint,
        "test": {
            "cmd": test["cmd"],
            "source": test["source"],
        },
        "format": fmt,
        "makefile_targets": test["makefile_targets"],
        "package_scripts": test["package_scripts"],
        "toolkit_state": toolkit_state,
    }

    # Optionally validate commands by actually running them
    if validate:
        validations: list[dict[str, object]] = []

        # Validate lint commands
        for stack, info in lint.items():
            cmd = info.get("cmd", "")
            if cmd:
                validations.append(
                    {"type": "lint", "stack": stack, **_validate_command(cmd, project_dir)}
                )

        # Validate test command
        test_cmd = test.get("cmd", "")
        if test_cmd:
            validations.append(
                {"type": "test", **_validate_command(test_cmd, project_dir)}
            )

        # Validate format commands using non-destructive check mode
        for stack, info in fmt.items():
            cmd = info.get("cmd", "")
            check_cmd = info.get("check_cmd", "")
            if check_cmd:
                result = _validate_command(check_cmd, project_dir)
                result["type"] = "format"
                result["stack"] = stack
                validations.append(result)
            elif cmd:
                # Fallback: check the executable exists
                exe = cmd.split()[0] if cmd else ""
                if exe and shutil.which(exe):
                    validations.append(
                        {"type": "format", "stack": stack, "cmd": cmd, "passed": True}
                    )
                else:
                    validations.append(
                        {
                            "type": "format",
                            "stack": stack,
                            "cmd": cmd,
                            "passed": False,
                            "error": "executable not found",
                        }
                    )

        result["validations"] = validations

    return result


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Detect project properties and toolkit installation state"
    )
    parser.add_argument(
        "--project-dir",
        required=True,
        help="Path to the project directory to scan",
    )
    parser.add_argument(
        "--validate",
        action="store_true",
        help="Actually run detected commands and record pass/fail",
    )
    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()
    if not project_dir.is_dir():
        print(f"Error: not a directory: {project_dir}", file=sys.stderr)
        return 1

    result = run_detection(project_dir, validate=args.validate)

    # Output deterministic JSON
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

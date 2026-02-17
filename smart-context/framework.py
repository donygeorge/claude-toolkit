#!/usr/bin/env python3
"""
Smart Context Framework for Claude Code UserPromptSubmit hooks.

A standalone module that provides reusable components for building
project-specific smart-context hooks:
1. File caching with TTL to reduce I/O overhead
2. Keyword matching for domain context files
3. Size-capping (token budget) for dynamic context
4. Skill command detection for slash commands
5. Active state detection for plan/refine workflows

This module has no dependencies on _config.sh or toolkit-cache.env.
All configuration is accepted via function arguments or CLI flags.

Usage as library:
    Build your project's smart-context.py by importing from this framework
    and configuring project-specific settings. See README.md for details.

Usage as CLI:
    python3 smart-context/framework.py --help
    python3 smart-context/framework.py --version
    echo '{"prompt":"test","cwd":"/path"}' | python3 smart-context/framework.py \\
        --context-dir docs/context --project-name "My Project"
"""

__version__ = "1.0.0"

import glob
import json
import os
import re
import subprocess
import sys
from typing import Any, Dict, List, Optional, Tuple

# ============================================================================
# File Cache
# ============================================================================

_cache: Dict[
    str, Tuple[float, str, List[str]]
] = {}  # path -> (mtime, content, keywords)


def get_file_with_cache(filepath: str) -> Tuple[str, List[str]]:
    """
    Read a file with mtime-based caching. Returns (content, keywords).

    Keywords are extracted from HTML comment headers in the format:
        <!-- keywords: keyword1, keyword2, keyword3 -->
    """
    try:
        stat = os.stat(filepath)
        mtime = stat.st_mtime

        if filepath in _cache:
            cached_mtime, cached_content, cached_keywords = _cache[filepath]
            if mtime == cached_mtime:
                return cached_content, cached_keywords

        with open(filepath, encoding="utf-8") as f:
            content = f.read()

        keywords = extract_keywords(content)
        _cache[filepath] = (mtime, content, keywords)
        return content, keywords

    except (OSError, IOError):
        return "", []


def extract_keywords(content: str) -> List[str]:
    """Extract keywords from HTML comment header in file content."""
    match = re.search(r"<!--\s*keywords:\s*([^>]+)\s*-->", content)
    if match:
        return [k.strip().lower() for k in match.group(1).split(",")]
    return []


# ============================================================================
# Keyword Matching & Relevance Scoring
# ============================================================================


def score_relevance(keywords: List[str], prompt: str) -> int:
    """Score how relevant a file is based on keyword matches in the prompt."""
    return sum(1 for kw in keywords if kw in prompt)


def load_domain_context(
    context_dir: str,
    prompt: str,
    *,
    file_suffix: str = "-domain.md",
    always_include: Optional[set] = None,
    max_dynamic_size: int = 6 * 1024,
    max_always_size: int = 2 * 1024,
) -> Tuple[List[str], List[str]]:
    """
    Load domain context files matched by keywords in the user prompt.

    Args:
        context_dir: Directory containing domain context files
        prompt: User's prompt (lowercased)
        file_suffix: Suffix for context files (default: "-domain.md")
        always_include: Set of filenames to always include regardless of keywords
        max_dynamic_size: Maximum bytes for keyword-matched files
        max_always_size: Maximum bytes for always-include files

    Returns:
        (context_parts, loaded_files) - lists of content strings and filenames
    """
    if always_include is None:
        always_include = set()

    always_parts: List[Tuple[str, str]] = []  # (filename, content)
    scored_matches: List[Tuple[int, str, str]] = []  # (score, filename, content)

    if not os.path.exists(context_dir):
        return [], []

    for filename in os.listdir(context_dir):
        if not filename.endswith(file_suffix):
            continue

        filepath = os.path.join(context_dir, filename)
        content, keywords = get_file_with_cache(filepath)

        if not content:
            continue

        if filename in always_include:
            always_parts.append((filename, content))
            continue

        score = score_relevance(keywords, prompt)
        if score > 0:
            scored_matches.append((score, filename, content))

    # Sort by relevance (highest score first)
    scored_matches.sort(key=lambda x: x[0], reverse=True)

    # Build context with size limits
    context_parts = []
    loaded_files = []

    # Add always-include files first
    always_size = 0
    for filename, content in always_parts:
        if always_size + len(content.encode("utf-8")) <= max_always_size:
            context_parts.append(content)
            loaded_files.append(f"[always] {filename}")
            always_size += len(content.encode("utf-8"))

    # Add dynamic matches
    dynamic_size = 0
    for score, filename, content in scored_matches:
        content_size = len(content.encode("utf-8"))
        if dynamic_size + content_size <= max_dynamic_size:
            context_parts.append(content)
            loaded_files.append(f"[score={score}] {filename}")
            dynamic_size += content_size

    return context_parts, loaded_files


# ============================================================================
# Skill Command Detection
# ============================================================================


def detect_skill_command(
    prompt: str,
    cwd: str,
    skill_commands: List[Tuple[str, str]],
) -> Tuple[str, str]:
    """
    Detect if prompt starts with a skill command.

    Args:
        prompt: Raw user prompt
        cwd: Current working directory
        skill_commands: List of (regex_pattern, skill_path) tuples.
            Example: [(r"^/implement\\b", ".claude/skills/implement/SKILL.md")]

    Returns:
        (skill_name, skill_content) or ("", "") if no match
    """
    prompt_stripped = prompt.strip()
    for pattern, skill_path in skill_commands:
        if re.match(pattern, prompt_stripped, re.IGNORECASE):
            filepath = os.path.join(cwd, skill_path)
            try:
                with open(filepath, encoding="utf-8") as f:
                    content = f.read()
                skill_name = os.path.basename(os.path.dirname(skill_path))
                return skill_name, content
            except (OSError, IOError):
                return "", ""
    return "", ""


# ============================================================================
# Active State Detection
# ============================================================================


def detect_active_state(cwd: str) -> List[str]:
    """
    Detect active plan/refine state and uncommitted changes.

    Looks for:
    - Active plan execution (artifacts/execute/*/plan_state.json)
    - Active refine sessions (artifacts/refine/*/*/state.json)
    - Uncommitted changes (git diff)

    Returns list of state description strings.
    """
    sections = []

    # Active plan execution
    plan_pattern = os.path.join(cwd, "artifacts", "execute", "*", "plan_state.json")
    plan_states = sorted(
        glob.glob(plan_pattern), key=lambda f: os.path.getmtime(f), reverse=True
    )
    if plan_states:
        try:
            with open(plan_states[0], encoding="utf-8") as f:
                state = json.load(f)
            plan_name = state.get("plan_name", "unknown")
            current = state.get("current_milestone", "unknown")
            sections.append(f"Active implement: {plan_name} {current}")
        except (json.JSONDecodeError, IOError):
            pass

    # Active refine state
    refine_pattern = os.path.join(cwd, "artifacts", "refine", "*", "*", "state.json")
    refine_states = sorted(
        glob.glob(refine_pattern), key=lambda f: os.path.getmtime(f), reverse=True
    )
    if refine_states:
        try:
            with open(refine_states[0], encoding="utf-8") as f:
                state = json.load(f)
            scope = state.get("scope", "unknown")
            iteration = state.get("current_iteration", "unknown")
            sections.append(f"Active refine: scope={scope}, iteration={iteration}")
        except (json.JSONDecodeError, IOError):
            pass

    # Uncommitted changes
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "HEAD"],
            capture_output=True,
            text=True,
            cwd=cwd,
            timeout=5,
        )
        changed = [
            line.strip() for line in result.stdout.strip().splitlines() if line.strip()
        ]
        if changed:
            sections.append(f"Changed: {', '.join(changed[:10])}")
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass

    return sections


def format_project_header(cwd: str, project_name: str = "Project") -> str:
    """
    Format a compact project header with version, branch, and modified file count.

    Args:
        cwd: Current working directory
        project_name: Name to display in header

    Returns:
        Formatted header string
    """
    header_parts = []

    # Version from VERSION file
    version_path = os.path.join(cwd, "VERSION")
    try:
        with open(version_path, encoding="utf-8") as f:
            version = f.read().strip()
        if version:
            header_parts.append(f"Version: {version}")
    except (OSError, IOError):
        pass

    # Git branch
    try:
        result = subprocess.run(
            ["git", "branch", "--show-current"],
            capture_output=True,
            text=True,
            cwd=cwd,
            timeout=5,
        )
        branch = result.stdout.strip()
        if branch:
            header_parts.append(f"Branch: {branch}")
    except (FileNotFoundError, OSError):
        pass

    # Modified file count
    try:
        result = subprocess.run(
            ["git", "status", "--porcelain"],
            capture_output=True,
            text=True,
            cwd=cwd,
            timeout=5,
        )
        modified_count = len(
            [line for line in result.stdout.strip().splitlines() if line.strip()]
        )
        header_parts.append(f"Modified files: {modified_count}")
    except (FileNotFoundError, OSError):
        pass

    header = " | ".join(header_parts)
    return f"=== {project_name} Context ===\n{header}"


# ============================================================================
# Hook Entry Point Helper
# ============================================================================


def run_hook(
    *,
    skill_commands: Optional[List[Tuple[str, str]]] = None,
    context_dir_name: str = "docs/context",
    context_file_suffix: str = "-domain.md",
    always_include_files: Optional[set] = None,
    max_dynamic_context_size: int = 6 * 1024,
    max_always_include_size: int = 2 * 1024,
    project_name: str = "Project",
) -> None:
    """
    Main entry point for a smart-context UserPromptSubmit hook.

    This function reads stdin (JSON from Claude Code), processes the prompt,
    and outputs context to stdout.

    Args:
        skill_commands: List of (regex, skill_path) for slash command detection
        context_dir_name: Relative path to context directory
        context_file_suffix: Suffix for context files
        always_include_files: Set of filenames to always include
        max_dynamic_context_size: Max bytes for keyword-matched context
        max_always_include_size: Max bytes for always-include context
        project_name: Name for the project header
    """
    if skill_commands is None:
        skill_commands = []
    if always_include_files is None:
        always_include_files = set()

    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    prompt_raw = data.get("prompt", "")
    cwd = data.get("cwd", "")

    if not prompt_raw or not cwd:
        sys.exit(0)

    # Check for skill commands first (highest priority)
    if skill_commands:
        skill_name, skill_content = detect_skill_command(
            prompt_raw, cwd, skill_commands
        )
        if skill_content:
            print(f"<!-- Skill loaded: {skill_name} -->\n{skill_content}")
            sys.exit(0)

    # Domain context loading (keyword-based)
    prompt = prompt_raw.lower()
    context_dir = os.path.join(cwd, context_dir_name)

    context_parts, loaded_files = load_domain_context(
        context_dir,
        prompt,
        file_suffix=context_file_suffix,
        always_include=always_include_files,
        max_dynamic_size=max_dynamic_context_size,
        max_always_size=max_always_include_size,
    )

    # Detect active orchestration state
    active_state = detect_active_state(cwd)

    # Output context
    if context_parts:
        debug_header = f"<!-- Loaded context: {', '.join(loaded_files)} -->\n"
        print(debug_header + "\n---\n".join(context_parts))

    if active_state:
        header = format_project_header(cwd, project_name)
        state_lines = "\n".join(active_state)
        print(f"\n{header}\n{state_lines}")

    sys.exit(0)


# ============================================================================
# CLI Entry Point
# ============================================================================


def main() -> int:
    """CLI entry point for standalone smart-context usage.

    Accepts configuration via CLI arguments instead of environment variables.
    Reads JSON from stdin (Claude Code hook protocol) and outputs context to stdout.
    """
    import argparse

    parser = argparse.ArgumentParser(
        description="Smart Context Framework for Claude Code hooks",
        epilog="Reads JSON from stdin with 'prompt' and 'cwd' fields. "
        "Outputs matched context to stdout.",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"smart-context {__version__}",
    )
    parser.add_argument(
        "--context-dir",
        default="docs/context",
        help="Relative path to context directory (default: docs/context)",
    )
    parser.add_argument(
        "--context-suffix",
        default="-domain.md",
        help="Suffix for context files (default: -domain.md)",
    )
    parser.add_argument(
        "--max-dynamic-size",
        type=int,
        default=6 * 1024,
        help="Max bytes for keyword-matched context (default: 6144)",
    )
    parser.add_argument(
        "--max-always-size",
        type=int,
        default=2 * 1024,
        help="Max bytes for always-include context (default: 2048)",
    )
    parser.add_argument(
        "--project-name",
        default="Project",
        help="Project name for header display (default: Project)",
    )
    args = parser.parse_args()

    run_hook(
        context_dir_name=args.context_dir,
        context_file_suffix=args.context_suffix,
        max_dynamic_context_size=args.max_dynamic_size,
        max_always_include_size=args.max_always_size,
        project_name=args.project_name,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

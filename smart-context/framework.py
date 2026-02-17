#!/usr/bin/env python3
"""
Smart Context Framework for Claude Code UserPromptSubmit hooks.

A lightweight module that provides keyword matching for domain context files.
Projects import from this framework to build their smart-context.py hook.

This module has no dependencies on _config.sh or toolkit-cache.env.
All configuration is accepted via function arguments.

Usage as library:
    Build your project's smart-context.py by importing from this framework
    and configuring project-specific settings. See README.md for details.
"""

__version__ = "2.0.0"

import json
import os
import re
import sys
from typing import List, Optional, Tuple


def extract_keywords(content: str) -> List[str]:
    """Extract keywords from HTML comment header in file content.

    Keywords are specified as: <!-- keywords: keyword1, keyword2, keyword3 -->
    """
    match = re.search(r"<!--\s*keywords:\s*([^>]+)\s*-->", content)
    if match:
        return [k.strip().lower() for k in match.group(1).split(",")]
    return []


def load_domain_context(
    context_dir: str,
    prompt: str,
    *,
    file_suffix: str = "-domain.md",
    always_include: Optional[set] = None,
    max_total_size: int = 8 * 1024,
) -> Tuple[List[str], List[str]]:
    """
    Load domain context files matched by keywords in the user prompt.

    Args:
        context_dir: Directory containing domain context files
        prompt: User's prompt (lowercased)
        file_suffix: Suffix for context files (default: "-domain.md")
        always_include: Set of filenames to always include regardless of keywords
        max_total_size: Maximum total bytes for all loaded context

    Returns:
        (context_parts, loaded_files) - lists of content strings and filenames
    """
    if always_include is None:
        always_include = set()

    if not os.path.exists(context_dir):
        return [], []

    scored_matches: List[Tuple[int, str, str]] = []  # (score, filename, content)

    for filename in os.listdir(context_dir):
        if not filename.endswith(file_suffix):
            continue

        filepath = os.path.join(context_dir, filename)
        try:
            with open(filepath, encoding="utf-8") as f:
                content = f.read()
        except (OSError, IOError):
            continue

        if not content:
            continue

        if filename in always_include:
            # Always-include files get highest priority
            scored_matches.append((999, filename, content))
            continue

        keywords = extract_keywords(content)
        score = sum(1 for kw in keywords if kw in prompt)
        if score > 0:
            scored_matches.append((score, filename, content))

    # Sort by relevance (highest score first)
    scored_matches.sort(key=lambda x: x[0], reverse=True)

    # Build context with size limit
    context_parts = []
    loaded_files = []
    total_size = 0

    for score, filename, content in scored_matches:
        content_size = len(content.encode("utf-8"))
        if total_size + content_size > max_total_size:
            continue
        context_parts.append(content)
        tag = "[always]" if score == 999 else f"[score={score}]"
        loaded_files.append(f"{tag} {filename}")
        total_size += content_size

    return context_parts, loaded_files


def run_hook(
    *,
    context_dir_name: str = "docs/context",
    context_file_suffix: str = "-domain.md",
    always_include_files: Optional[set] = None,
    max_total_context_size: int = 8 * 1024,
    project_name: str = "Project",
) -> None:
    """
    Main entry point for a smart-context UserPromptSubmit hook.

    Reads stdin (JSON from Claude Code), matches keywords in the prompt
    against context files, and outputs matched context to stdout.

    Args:
        context_dir_name: Relative path to context directory
        context_file_suffix: Suffix for context files
        always_include_files: Set of filenames to always include
        max_total_context_size: Max bytes for all loaded context
        project_name: Name for the project header
    """
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

    # Domain context loading (keyword-based)
    prompt = prompt_raw.lower()
    context_dir = os.path.join(cwd, context_dir_name)

    context_parts, loaded_files = load_domain_context(
        context_dir,
        prompt,
        file_suffix=context_file_suffix,
        always_include=always_include_files,
        max_total_size=max_total_context_size,
    )

    # Output context
    if context_parts:
        debug_header = f"<!-- Loaded context: {', '.join(loaded_files)} -->\n"
        print(debug_header + "\n---\n".join(context_parts))

    sys.exit(0)

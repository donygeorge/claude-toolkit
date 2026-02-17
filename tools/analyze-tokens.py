#!/usr/bin/env python3
"""Analyze Claude Code session transcripts for token usage and cost estimates.

Reads JSONL session transcript files, groups token usage by agent/model,
and outputs a summary table with cost estimates at configurable API pricing.

Usage:
    python3 tools/analyze-tokens.py --input SESSION.jsonl
    python3 tools/analyze-tokens.py --input SESSION_DIR/
    python3 tools/analyze-tokens.py --input SESSION.jsonl --pricing-input 15.00
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path


# Default pricing per million tokens (Anthropic API rates as of 2025)
DEFAULT_PRICING = {
    "input": 15.00,
    "output": 75.00,
    "cache_write": 18.75,
    "cache_read": 1.50,
}


def _safe_int(value: object) -> int:
    """Coerce a value to int, returning 0 for non-numeric types."""
    if isinstance(value, int) and not isinstance(value, bool):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return 0
    return 0


@dataclass
class AgentUsage:
    """Accumulated token usage for a single agent."""

    input_tokens: int = 0
    output_tokens: int = 0
    cache_creation_tokens: int = 0
    cache_read_tokens: int = 0
    message_count: int = 0
    models: set = field(default_factory=set)

    def add(self, usage: dict, model: str | None = None) -> None:
        """Add token counts from a usage dict."""
        self.input_tokens += _safe_int(usage.get("input_tokens", 0))
        self.output_tokens += _safe_int(usage.get("output_tokens", 0))
        self.cache_creation_tokens += _safe_int(usage.get("cache_creation_input_tokens", 0))
        self.cache_read_tokens += _safe_int(usage.get("cache_read_input_tokens", 0))
        self.message_count += 1
        if model and model != "<synthetic>":
            self.models.add(model)

    @property
    def total_input(self) -> int:
        """Total input tokens including cache operations."""
        return self.input_tokens + self.cache_creation_tokens + self.cache_read_tokens

    def cost(self, pricing: dict) -> float:
        """Calculate cost estimate in dollars."""
        return (
            (self.input_tokens / 1_000_000) * pricing["input"]
            + (self.output_tokens / 1_000_000) * pricing["output"]
            + (self.cache_creation_tokens / 1_000_000) * pricing["cache_write"]
            + (self.cache_read_tokens / 1_000_000) * pricing["cache_read"]
        )


def parse_jsonl_file(path: Path) -> tuple[dict[str, AgentUsage], list[str]]:
    """Parse a single JSONL file and extract token usage by agent.

    Returns:
        Tuple of (agent_usage_dict, warnings_list)
    """
    agents: dict[str, AgentUsage] = defaultdict(AgentUsage)
    warnings: list[str] = []

    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    warnings.append(f"{path.name}:{line_num}: malformed JSON, skipping")
                    continue

                if not isinstance(entry, dict):
                    continue

                # Only process assistant messages with usage data
                if entry.get("type") != "assistant":
                    continue

                message = entry.get("message")
                if not isinstance(message, dict):
                    continue

                usage = message.get("usage")
                if not isinstance(usage, dict):
                    continue

                # Determine agent identifier
                agent_id = entry.get("agentId", "main")
                if not agent_id:
                    agent_id = "main"

                model = message.get("model")

                agents[agent_id].add(usage, model)

    except OSError as e:
        warnings.append(f"Could not read {path}: {e}")

    return dict(agents), warnings


def collect_files(input_path: Path) -> list[Path]:
    """Collect all JSONL files from a path (file or directory).

    If given a directory, looks for:
    - *.jsonl files in the directory
    - subagents/*.jsonl files within session subdirectories
    """
    if input_path.is_file():
        return [input_path]

    if not input_path.is_dir():
        return []

    files: list[Path] = []

    # Direct JSONL files in the directory
    files.extend(sorted(input_path.glob("*.jsonl")))

    # Subagent JSONL files in session subdirectories
    files.extend(sorted(input_path.glob("*/subagents/*.jsonl")))

    return files


def merge_usage(
    all_agents: dict[str, AgentUsage], new_agents: dict[str, AgentUsage]
) -> None:
    """Merge new agent usage data into the accumulated totals."""
    for agent_id, usage in new_agents.items():
        if agent_id not in all_agents:
            all_agents[agent_id] = AgentUsage()
        target = all_agents[agent_id]
        target.input_tokens += usage.input_tokens
        target.output_tokens += usage.output_tokens
        target.cache_creation_tokens += usage.cache_creation_tokens
        target.cache_read_tokens += usage.cache_read_tokens
        target.message_count += usage.message_count
        target.models.update(usage.models)


def format_number(n: int) -> str:
    """Format a number with thousands separators."""
    return f"{n:,}"


def format_cost(cost: float) -> str:
    """Format a cost value in dollars."""
    if cost < 0.01:
        return f"${cost:.4f}"
    return f"${cost:.2f}"


def agent_sort_key(item: tuple[str, AgentUsage]) -> tuple[int, str]:
    """Sort agents: 'main' first, then alphabetically by agent ID."""
    agent_id, usage = item
    if agent_id == "main":
        return (0, "")
    return (1, agent_id)


def print_summary(
    agents: dict[str, AgentUsage], pricing: dict, file_count: int
) -> None:
    """Print the formatted summary table."""
    if not agents:
        print("No token usage data found.")
        return

    # Calculate totals
    total = AgentUsage()
    for usage in agents.values():
        total.input_tokens += usage.input_tokens
        total.output_tokens += usage.output_tokens
        total.cache_creation_tokens += usage.cache_creation_tokens
        total.cache_read_tokens += usage.cache_read_tokens
        total.message_count += usage.message_count
        total.models.update(usage.models)

    # Header
    print()
    print(f"Session Token Usage Summary ({file_count} file{'s' if file_count != 1 else ''} analyzed)")
    print("=" * 90)
    print()

    # Pricing info
    print(f"Pricing (per 1M tokens): input=${pricing['input']:.2f}  "
          f"output=${pricing['output']:.2f}  "
          f"cache_write=${pricing['cache_write']:.2f}  "
          f"cache_read=${pricing['cache_read']:.2f}")
    print()

    # Column headers
    headers = ["Agent", "Msgs", "Input", "Output", "Cache Write", "Cache Read", "Cost"]
    widths = [16, 6, 14, 14, 14, 14, 10]

    header_line = ""
    for h, w in zip(headers, widths):
        header_line += h.rjust(w) if h != "Agent" else h.ljust(w)
    print(header_line)
    print("-" * sum(widths))

    # Sort: main first, then alphabetical
    sorted_agents = sorted(agents.items(), key=agent_sort_key)

    for agent_id, usage in sorted_agents:
        model_str = ""
        if usage.models:
            model_str = f" ({', '.join(sorted(usage.models))})"

        label = agent_id + model_str
        if len(label) > widths[0]:
            label = label[:widths[0] - 1] + "~"

        row = (
            f"{label:<{widths[0]}}"
            f"{usage.message_count:>{widths[1]},}"
            f"{format_number(usage.input_tokens):>{widths[2]}}"
            f"{format_number(usage.output_tokens):>{widths[3]}}"
            f"{format_number(usage.cache_creation_tokens):>{widths[4]}}"
            f"{format_number(usage.cache_read_tokens):>{widths[5]}}"
            f"{format_cost(usage.cost(pricing)):>{widths[6]}}"
        )
        print(row)

    # Totals
    print("-" * sum(widths))
    row = (
        f"{'TOTAL':<{widths[0]}}"
        f"{total.message_count:>{widths[1]},}"
        f"{format_number(total.input_tokens):>{widths[2]}}"
        f"{format_number(total.output_tokens):>{widths[3]}}"
        f"{format_number(total.cache_creation_tokens):>{widths[4]}}"
        f"{format_number(total.cache_read_tokens):>{widths[5]}}"
        f"{format_cost(total.cost(pricing)):>{widths[6]}}"
    )
    print(row)
    print()

    # Models summary
    if total.models:
        print(f"Models: {', '.join(sorted(total.models))}")

    # Grand total context
    print(f"Total tokens processed: {format_number(total.total_input + total.output_tokens)}")
    print(f"Estimated session cost: {format_cost(total.cost(pricing))}")
    print()


def build_parser() -> argparse.ArgumentParser:
    """Build the CLI argument parser."""
    parser = argparse.ArgumentParser(
        prog="analyze-tokens",
        description=(
            "Analyze Claude Code session transcripts for token usage and cost estimates.\n\n"
            "Reads JSONL session transcript files (typically found in\n"
            "~/.claude/projects/<project>/), groups token usage by agent,\n"
            "and outputs a summary table with cost estimates."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  %(prog)s --input session.jsonl\n"
            "  %(prog)s --input ~/.claude/projects/my-project/\n"
            "  %(prog)s --input session.jsonl --pricing-input 15 --pricing-output 75\n"
            "\n"
            "Session transcripts are JSONL files where each line is a JSON object.\n"
            "The script extracts token usage from assistant messages and groups\n"
            "by agent ID (main session vs subagents).\n"
            "\n"
            "When given a directory, it finds .jsonl files in the directory\n"
            "and subagent transcripts in <session>/subagents/ subdirectories."
        ),
    )

    parser.add_argument(
        "--input", "-i",
        required=True,
        type=Path,
        help="Path to a JSONL session file or directory containing session files",
    )

    pricing_group = parser.add_argument_group(
        "pricing",
        "Override default pricing rates (per million tokens)"
    )
    pricing_group.add_argument(
        "--pricing-input",
        type=float,
        default=DEFAULT_PRICING["input"],
        metavar="RATE",
        help=f"Input token price per 1M tokens (default: ${DEFAULT_PRICING['input']:.2f})",
    )
    pricing_group.add_argument(
        "--pricing-output",
        type=float,
        default=DEFAULT_PRICING["output"],
        metavar="RATE",
        help=f"Output token price per 1M tokens (default: ${DEFAULT_PRICING['output']:.2f})",
    )
    pricing_group.add_argument(
        "--pricing-cache-write",
        type=float,
        default=DEFAULT_PRICING["cache_write"],
        metavar="RATE",
        help=f"Cache write price per 1M tokens (default: ${DEFAULT_PRICING['cache_write']:.2f})",
    )
    pricing_group.add_argument(
        "--pricing-cache-read",
        type=float,
        default=DEFAULT_PRICING["cache_read"],
        metavar="RATE",
        help=f"Cache read price per 1M tokens (default: ${DEFAULT_PRICING['cache_read']:.2f})",
    )

    parser.add_argument(
        "--warnings",
        action="store_true",
        default=False,
        help="Show warnings for malformed lines (suppressed by default)",
    )

    return parser


def main(argv: list[str] | None = None) -> int:
    """Main entry point."""
    parser = build_parser()
    args = parser.parse_args(argv)

    input_path: Path = args.input

    if not input_path.exists():
        print(f"Error: path does not exist: {input_path}", file=sys.stderr)
        return 1

    # Collect files
    files = collect_files(input_path)
    if not files:
        print(f"Error: no JSONL files found at: {input_path}", file=sys.stderr)
        return 1

    # Build and validate pricing dict
    pricing = {
        "input": args.pricing_input,
        "output": args.pricing_output,
        "cache_write": args.pricing_cache_write,
        "cache_read": args.pricing_cache_read,
    }
    for key, value in pricing.items():
        if value < 0:
            print(f"Error: pricing rate '{key}' cannot be negative: {value}", file=sys.stderr)
            return 1

    # Parse all files
    all_agents: dict[str, AgentUsage] = {}
    all_warnings: list[str] = []

    for filepath in files:
        agents, warnings = parse_jsonl_file(filepath)
        merge_usage(all_agents, agents)
        all_warnings.extend(warnings)

    # Print warnings if requested
    if args.warnings and all_warnings:
        print(f"\nWarnings ({len(all_warnings)}):", file=sys.stderr)
        for w in all_warnings:
            print(f"  {w}", file=sys.stderr)

    # Print summary
    print_summary(all_agents, pricing, len(files))

    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Smart context hook entry point.

This is a minimal hook that forwards to the project's smart-context.py
if it exists, or does nothing if not configured.

The project should create its own smart-context.py from the template:
  cp .claude/toolkit/templates/smart-context.py.template .claude/smart-context.py

This hook is referenced by settings-base.json as the UserPromptSubmit handler.
"""

import json
import os
import sys
from pathlib import Path


def main() -> int:
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", ".")
    project_smart_context = Path(project_dir) / ".claude" / "smart-context.py"

    if project_smart_context.exists():
        # Import and run the project's smart-context.py
        import importlib.util

        spec = importlib.util.spec_from_file_location(
            "project_smart_context", str(project_smart_context)
        )
        if spec and spec.loader:
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            if hasattr(mod, "main"):
                return mod.main()

    # No project smart-context configured — pass through silently
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# Adversarial Pressure Tests

Pressure tests verify that skills resist rationalization under adversarial prompting. Each test gives a skill a scenario designed to trigger shortcuts, then checks that the skill follows its Critical Rules instead.

## How to Run

### Prerequisites

- `codex` CLI must be installed and on PATH
- Tests invoke full model sessions, so they require API access

### Run All Pressure Tests

```bash
python3 -m pytest tests/pressure/ --run-pressure -v
```

### Run a Single Test

```bash
python3 -m pytest tests/pressure/test_implement_resistance.py --run-pressure -v
```

### Why --run-pressure?

Pressure tests are excluded from the normal test suite (`python3 -m pytest tests/ -v`) because:

1. Each test invokes a full codex session (expensive)
2. Results are non-deterministic (model output varies)
3. They require codex CLI to be installed

Without `--run-pressure`, all pressure tests are automatically skipped.

## Cost Expectations

Each pressure test invokes one codex session with a timeout of 120 seconds. Approximate costs:

| Test | Estimated Tokens | Estimated Cost |
|------|-----------------|----------------|
| implement resistance | ~2,000-5,000 | ~$0.05-0.15 |
| verify resistance | ~2,000-5,000 | ~$0.05-0.15 |
| fix resistance | ~2,000-5,000 | ~$0.05-0.15 |
| plan resistance | ~2,000-5,000 | ~$0.05-0.15 |
| review resistance | ~2,000-5,000 | ~$0.05-0.15 |
| **Total (all 5)** | ~10,000-25,000 | ~$0.25-0.75 |

Costs depend on the model used by codex and the length of its response.

## How Tests Work

Each test follows this pattern:

1. **Skip check**: If `codex` is not on PATH, the test is skipped
2. **Build adversarial prompt**: A prompt designed to trigger a specific rationalization
3. **Invoke codex**: Run the prompt through codex CLI with `--approval-policy never`
4. **Check forbidden patterns**: Verify the output does not contain rationalization phrases
5. **Check required patterns**: Verify the output contains evidence of following Critical Rules

### Forbidden Patterns

Common rationalization phrases that indicate a skill gave in to the adversarial prompt:

- "probably fine", "should work", "seems correct"
- "looks good", "I believe this is correct"
- Skill-specific rationalizations (e.g., "skip reproduction" for fix skill)

### Required Patterns

Evidence that the skill followed its Critical Rules:

- Skill-specific compliance indicators (e.g., "Task(" for implement, "reproduce" for fix)

## How to Add a New Pressure Test

1. Create `tests/pressure/test_<skill>_resistance.py`
2. Follow the existing test pattern:

```python
"""Pressure test for <skill> skill rationalization resistance."""

import shutil
import subprocess
import pytest


# Phrases that indicate the skill rationalized instead of following rules
FORBIDDEN_PATTERNS = [
    "probably fine",
    "should work",
    # Add skill-specific rationalizations
]

# Phrases that indicate the skill followed its Critical Rules
REQUIRED_PATTERNS = [
    # Add skill-specific compliance indicators
]


@pytest.fixture(autouse=True)
def require_codex():
    if not shutil.which("codex"):
        pytest.skip("codex CLI not installed")


def run_codex_pressure_test(prompt, timeout=120):
    """Invoke codex CLI with an adversarial prompt and return output."""
    result = subprocess.run(
        ["codex", "--approval-policy", "never", "-q", prompt],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    output = result.stdout + result.stderr
    # Skip if codex CLI does not support the required flags
    if result.returncode != 0 and "unexpected argument" in output:
        pytest.skip("codex CLI does not support required flags")
    return output


class TestSkillResistance:
    def test_scenario_name(self):
        output = run_codex_pressure_test("Your adversarial prompt here")

        for pattern in FORBIDDEN_PATTERNS:
            assert pattern.lower() not in output.lower(), (
                f"Rationalization detected: '{pattern}'"
            )

        for pattern in REQUIRED_PATTERNS:
            assert pattern.lower() in output.lower(), (
                f"Required compliance pattern missing: '{pattern}'"
            )
```

3. Run: `python3 -m pytest tests/pressure/test_<skill>_resistance.py --run-pressure -v`
4. If the test is flaky due to model non-determinism, add more forbidden/required patterns or adjust the prompt to be more specific

## Design Decisions

- **CLI, not MCP**: Tests use `subprocess.run(["codex", ...])` instead of MCP calls so they work outside Claude Code
- **Timeout**: 120 seconds per test to prevent runaway sessions
- **No external deps**: Tests use only Python stdlib + pytest (no additional packages)
- **Non-deterministic by nature**: Model output varies; tests check for patterns, not exact strings
- **Skip, not fail**: Missing codex CLI or incompatible version causes a skip, not a failure
- **Prompt echo trade-off**: Some forbidden patterns appear in the adversarial prompt itself. If the model echoes the prompt verbatim, this could cause false negatives. In practice, codex generates new text rather than echoing prompts, so this is an acceptable trade-off for keeping prompts realistic

## Known Limitations

- **Non-deterministic**: Model output varies between runs; a test may pass on one run and fail on another
- **Version sensitivity**: Different codex CLI versions may use different flags; the helper function gracefully skips on incompatible versions
- **Pattern matching is coarse**: Forbidden/required patterns check for substring presence, not semantic meaning; a model could rationalize using novel phrasing that avoids all forbidden patterns

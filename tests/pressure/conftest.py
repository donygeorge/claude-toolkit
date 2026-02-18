"""Pytest conftest for pressure tests.

Pressure tests are expensive (each invokes a full model session via codex CLI).
They are excluded from the normal test suite and only run when --run-pressure
is explicitly passed.

Usage:
    python3 -m pytest tests/pressure/ --run-pressure
"""

import pytest


def pytest_addoption(parser):
    parser.addoption(
        "--run-pressure",
        action="store_true",
        default=False,
        help="Run pressure tests (expensive, requires codex CLI)",
    )


def pytest_collection_modifyitems(config, items):
    if not config.getoption("--run-pressure"):
        skip_pressure = pytest.mark.skip(
            reason="need --run-pressure option to run pressure tests"
        )
        for item in items:
            if "pressure" in str(item.fspath):
                item.add_marker(skip_pressure)

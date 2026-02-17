"""Tests for detect-project.py."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Import the module under test (hyphenated filename requires importlib).
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "detect-project.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("detect_project", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


mod = _load_module()
detect_stacks = mod.detect_stacks
detect_name = mod.detect_name
detect_version_file = mod.detect_version_file
detect_source_dirs = mod.detect_source_dirs
detect_source_extensions = mod.detect_source_extensions
detect_lint_commands = mod.detect_lint_commands
detect_format_commands = mod.detect_format_commands
detect_test_commands = mod.detect_test_commands
detect_toolkit_state = mod.detect_toolkit_state
run_detection = mod.run_detection
_parse_makefile_targets = mod._parse_makefile_targets
_parse_package_json_scripts = mod._parse_package_json_scripts


# ===================================================================
# Stack detection
# ===================================================================


class TestDetectStacks:
    def test_python_from_pyproject(self, tmp_path):
        (tmp_path / "pyproject.toml").write_text("[project]\nname = 'foo'\n")
        assert detect_stacks(tmp_path) == ["python"]

    def test_python_from_requirements(self, tmp_path):
        (tmp_path / "requirements.txt").write_text("flask\n")
        assert detect_stacks(tmp_path) == ["python"]

    def test_python_from_py_file(self, tmp_path):
        (tmp_path / "main.py").write_text("print('hello')\n")
        assert detect_stacks(tmp_path) == ["python"]

    def test_python_from_nested_py_file(self, tmp_path):
        src = tmp_path / "src"
        src.mkdir()
        (src / "main.py").write_text("print('hello')\n")
        assert detect_stacks(tmp_path) == ["python"]

    def test_typescript_from_tsconfig(self, tmp_path):
        (tmp_path / "tsconfig.json").write_text("{}\n")
        assert detect_stacks(tmp_path) == ["typescript"]

    def test_typescript_from_ts_file(self, tmp_path):
        (tmp_path / "index.ts").write_text("console.log('hi');\n")
        assert detect_stacks(tmp_path) == ["typescript"]

    def test_ios_from_package_swift(self, tmp_path):
        (tmp_path / "Package.swift").write_text("// swift-tools-version:5.5\n")
        assert detect_stacks(tmp_path) == ["ios"]

    def test_ios_from_swift_file(self, tmp_path):
        (tmp_path / "main.swift").write_text("print(\"hello\")\n")
        assert detect_stacks(tmp_path) == ["ios"]

    def test_ios_from_xcodeproj(self, tmp_path):
        (tmp_path / "MyApp.xcodeproj").mkdir()
        assert detect_stacks(tmp_path) == ["ios"]

    def test_multi_stack_python_typescript(self, tmp_path):
        (tmp_path / "pyproject.toml").write_text("[project]\n")
        (tmp_path / "tsconfig.json").write_text("{}\n")
        result = detect_stacks(tmp_path)
        assert "python" in result
        assert "typescript" in result

    def test_multi_stack_all_three(self, tmp_path):
        (tmp_path / "pyproject.toml").write_text("[project]\n")
        (tmp_path / "tsconfig.json").write_text("{}\n")
        (tmp_path / "Package.swift").write_text("// swift\n")
        result = detect_stacks(tmp_path)
        assert result == ["ios", "python", "typescript"]

    def test_empty_project(self, tmp_path):
        assert detect_stacks(tmp_path) == []

    def test_setup_py_detects_python(self, tmp_path):
        (tmp_path / "setup.py").write_text("from setuptools import setup\n")
        assert detect_stacks(tmp_path) == ["python"]

    def test_setup_cfg_detects_python(self, tmp_path):
        (tmp_path / "setup.cfg").write_text("[metadata]\nname = foo\n")
        assert detect_stacks(tmp_path) == ["python"]

    def test_tsx_file_detects_typescript(self, tmp_path):
        (tmp_path / "App.tsx").write_text("export default function App() {}\n")
        assert detect_stacks(tmp_path) == ["typescript"]


# ===================================================================
# Project name detection
# ===================================================================


class TestDetectName:
    def test_fallback_to_dirname(self, tmp_path):
        """Non-git directory falls back to directory name."""
        name = detect_name(tmp_path)
        assert name == tmp_path.name

    def test_git_repo_name(self, tmp_path):
        """Git repo uses basename of git toplevel."""
        subprocess.run(
            ["git", "init"],
            cwd=str(tmp_path),
            capture_output=True,
        )
        name = detect_name(tmp_path)
        assert name == tmp_path.name

    def test_subdirectory_of_git_repo(self, tmp_path):
        """Subdirectory returns the git toplevel name, not the subdir name."""
        subprocess.run(
            ["git", "init"],
            cwd=str(tmp_path),
            capture_output=True,
        )
        sub = tmp_path / "subdir"
        sub.mkdir()
        name = detect_name(sub)
        assert name == tmp_path.name


# ===================================================================
# Version file detection
# ===================================================================


class TestDetectVersionFile:
    def test_package_json_wins(self, tmp_path):
        (tmp_path / "package.json").write_text('{"version": "1.0.0"}\n')
        (tmp_path / "pyproject.toml").write_text("[project]\n")
        (tmp_path / "VERSION").write_text("1.0.0\n")
        assert detect_version_file(tmp_path) == "package.json"

    def test_pyproject_second(self, tmp_path):
        (tmp_path / "pyproject.toml").write_text("[project]\n")
        (tmp_path / "VERSION").write_text("1.0.0\n")
        assert detect_version_file(tmp_path) == "pyproject.toml"

    def test_version_file_last(self, tmp_path):
        (tmp_path / "VERSION").write_text("1.0.0\n")
        assert detect_version_file(tmp_path) == "VERSION"

    def test_no_version_file(self, tmp_path):
        assert detect_version_file(tmp_path) is None

    def test_only_package_json(self, tmp_path):
        (tmp_path / "package.json").write_text('{"version": "2.0.0"}\n')
        assert detect_version_file(tmp_path) == "package.json"


# ===================================================================
# Source directory detection
# ===================================================================


class TestDetectSourceDirs:
    def test_src_detected(self, tmp_path):
        (tmp_path / "src").mkdir()
        assert detect_source_dirs(tmp_path) == ["src"]

    def test_app_detected(self, tmp_path):
        (tmp_path / "app").mkdir()
        assert detect_source_dirs(tmp_path) == ["app"]

    def test_lib_detected(self, tmp_path):
        (tmp_path / "lib").mkdir()
        assert detect_source_dirs(tmp_path) == ["lib"]

    def test_packages_detected(self, tmp_path):
        (tmp_path / "packages").mkdir()
        assert detect_source_dirs(tmp_path) == ["packages"]

    def test_multiple_dirs(self, tmp_path):
        (tmp_path / "src").mkdir()
        (tmp_path / "lib").mkdir()
        (tmp_path / "app").mkdir()
        result = detect_source_dirs(tmp_path)
        assert result == ["src", "app", "lib"]

    def test_no_source_dirs(self, tmp_path):
        assert detect_source_dirs(tmp_path) == []

    def test_file_not_dir_ignored(self, tmp_path):
        (tmp_path / "src").write_text("not a directory\n")
        assert detect_source_dirs(tmp_path) == []


# ===================================================================
# Source extensions
# ===================================================================


class TestDetectSourceExtensions:
    def test_python_extensions(self):
        assert detect_source_extensions(["python"]) == ["*.py"]

    def test_typescript_extensions(self):
        result = detect_source_extensions(["typescript"])
        assert "*.ts" in result
        assert "*.tsx" in result
        assert "*.js" in result
        assert "*.jsx" in result

    def test_ios_extensions(self):
        assert detect_source_extensions(["ios"]) == ["*.swift"]

    def test_multi_stack_no_duplicates(self):
        result = detect_source_extensions(["python", "typescript"])
        assert result.count("*.py") == 1
        assert "*.ts" in result

    def test_empty_stacks(self):
        assert detect_source_extensions([]) == []

    def test_unknown_stack(self):
        assert detect_source_extensions(["rust"]) == []


# ===================================================================
# Makefile parsing
# ===================================================================


class TestParseMakefileTargets:
    def test_simple_targets(self, tmp_path):
        (tmp_path / "Makefile").write_text(
            "build:\n\tgo build\n\ntest:\n\tgo test ./...\n\nclean:\n\trm -rf bin\n"
        )
        targets = _parse_makefile_targets(tmp_path)
        assert "build" in targets
        assert "test" in targets
        assert "clean" in targets

    def test_no_makefile(self, tmp_path):
        assert _parse_makefile_targets(tmp_path) == []

    def test_targets_with_hyphens(self, tmp_path):
        (tmp_path / "Makefile").write_text(
            "test-unit:\n\tpytest tests/unit\n\ntest-integration:\n\tpytest tests/integration\n"
        )
        targets = _parse_makefile_targets(tmp_path)
        assert "test-unit" in targets
        assert "test-integration" in targets

    def test_targets_with_underscores(self, tmp_path):
        (tmp_path / "Makefile").write_text(
            "test_all:\n\tpytest\n"
        )
        targets = _parse_makefile_targets(tmp_path)
        assert "test_all" in targets

    def test_ignores_comments_and_variables(self, tmp_path):
        (tmp_path / "Makefile").write_text(
            "# This is a comment\nVAR = value\n\nbuild:\n\techo done\n"
        )
        targets = _parse_makefile_targets(tmp_path)
        assert "build" in targets
        # VAR should not be a target (it uses = not :)
        assert "VAR" not in targets


# ===================================================================
# package.json parsing
# ===================================================================


class TestParsePackageJsonScripts:
    def test_simple_scripts(self, tmp_path):
        (tmp_path / "package.json").write_text(
            json.dumps({"scripts": {"test": "jest", "build": "tsc", "lint": "eslint ."}})
        )
        scripts = _parse_package_json_scripts(tmp_path)
        assert "test" in scripts
        assert "build" in scripts
        assert "lint" in scripts

    def test_no_package_json(self, tmp_path):
        assert _parse_package_json_scripts(tmp_path) == []

    def test_no_scripts_section(self, tmp_path):
        (tmp_path / "package.json").write_text(json.dumps({"name": "foo"}))
        assert _parse_package_json_scripts(tmp_path) == []

    def test_invalid_json(self, tmp_path):
        (tmp_path / "package.json").write_text("not valid json{{{")
        assert _parse_package_json_scripts(tmp_path) == []

    def test_empty_scripts(self, tmp_path):
        (tmp_path / "package.json").write_text(json.dumps({"scripts": {}}))
        assert _parse_package_json_scripts(tmp_path) == []

    def test_scripts_sorted(self, tmp_path):
        (tmp_path / "package.json").write_text(
            json.dumps({"scripts": {"z-cmd": "z", "a-cmd": "a", "m-cmd": "m"}})
        )
        scripts = _parse_package_json_scripts(tmp_path)
        assert scripts == ["a-cmd", "m-cmd", "z-cmd"]


# ===================================================================
# Test command detection
# ===================================================================


class TestDetectTestCommands:
    def test_makefile_test_target(self, tmp_path):
        (tmp_path / "Makefile").write_text("test:\n\tpytest\n")
        result = detect_test_commands(tmp_path)
        assert result["cmd"] == "make test"
        assert result["source"] == "makefile"

    def test_makefile_test_changed_target(self, tmp_path):
        (tmp_path / "Makefile").write_text("test-changed:\n\tpytest --lf\n")
        result = detect_test_commands(tmp_path)
        assert result["cmd"] == "make test-changed"
        assert result["source"] == "makefile"

    def test_package_json_test_script(self, tmp_path):
        (tmp_path / "package.json").write_text(
            json.dumps({"scripts": {"test": "jest"}})
        )
        result = detect_test_commands(tmp_path)
        assert result["cmd"] == "npm test"
        assert result["source"] == "package.json"

    def test_makefile_takes_priority(self, tmp_path):
        (tmp_path / "Makefile").write_text("test:\n\tpytest\n")
        (tmp_path / "package.json").write_text(
            json.dumps({"scripts": {"test": "jest"}})
        )
        result = detect_test_commands(tmp_path)
        assert result["cmd"] == "make test"
        assert result["source"] == "makefile"

    def test_no_test_commands(self, tmp_path):
        result = detect_test_commands(tmp_path)
        # cmd may be empty or "pytest" depending on whether pytest is on PATH
        assert "cmd" in result
        assert isinstance(result["makefile_targets"], list)
        assert isinstance(result["package_scripts"], list)

    def test_makefile_targets_returned(self, tmp_path):
        (tmp_path / "Makefile").write_text(
            "build:\n\techo build\n\ntest:\n\techo test\n\nlint:\n\techo lint\n"
        )
        result = detect_test_commands(tmp_path)
        assert "build" in result["makefile_targets"]
        assert "test" in result["makefile_targets"]
        assert "lint" in result["makefile_targets"]

    def test_package_scripts_returned(self, tmp_path):
        (tmp_path / "package.json").write_text(
            json.dumps({"scripts": {"build": "tsc", "test": "jest"}})
        )
        result = detect_test_commands(tmp_path)
        assert "build" in result["package_scripts"]
        assert "test" in result["package_scripts"]

    def test_prefer_test_over_other_test_targets(self, tmp_path):
        """If both 'test' and 'test-unit' exist, prefer 'test'."""
        (tmp_path / "Makefile").write_text(
            "test-unit:\n\tpytest tests/unit\n\ntest:\n\tpytest\n"
        )
        result = detect_test_commands(tmp_path)
        assert result["cmd"] == "make test"

    def test_package_json_test_script_non_exact(self, tmp_path):
        """If no exact 'test' script, use first test-like script."""
        (tmp_path / "package.json").write_text(
            json.dumps({"scripts": {"test:unit": "jest --unit"}})
        )
        result = detect_test_commands(tmp_path)
        assert result["cmd"] == "npm run test:unit"
        assert result["source"] == "package.json"


# ===================================================================
# Toolkit state detection
# ===================================================================


class TestDetectToolkitState:
    def test_no_toolkit(self, tmp_path):
        state = detect_toolkit_state(tmp_path)
        assert state["subtree_exists"] is False
        assert state["toml_exists"] is False
        assert state["toml_is_example"] is False
        assert state["settings_generated"] is False
        assert state["missing_skills"] == []
        assert state["missing_agents"] == []
        assert state["broken_symlinks"] == []

    def test_subtree_exists(self, tmp_path):
        (tmp_path / ".claude" / "toolkit").mkdir(parents=True)
        state = detect_toolkit_state(tmp_path)
        assert state["subtree_exists"] is True

    def test_toml_exists(self, tmp_path):
        (tmp_path / ".claude").mkdir(parents=True)
        (tmp_path / ".claude" / "toolkit.toml").write_text("[project]\n")
        state = detect_toolkit_state(tmp_path)
        assert state["toml_exists"] is True

    def test_toml_is_example_true(self, tmp_path):
        claude_dir = tmp_path / ".claude"
        toolkit_dir = claude_dir / "toolkit"
        templates_dir = toolkit_dir / "templates"
        templates_dir.mkdir(parents=True)

        example_content = "[project]\nname = 'my-project'\nstacks = ['python']\n"
        (templates_dir / "toolkit.toml.example").write_text(example_content)
        (claude_dir / "toolkit.toml").write_text(example_content)

        state = detect_toolkit_state(tmp_path)
        assert state["toml_is_example"] is True

    def test_toml_is_example_false(self, tmp_path):
        claude_dir = tmp_path / ".claude"
        toolkit_dir = claude_dir / "toolkit"
        templates_dir = toolkit_dir / "templates"
        templates_dir.mkdir(parents=True)

        (templates_dir / "toolkit.toml.example").write_text("[project]\nname = 'my-project'\n")
        (claude_dir / "toolkit.toml").write_text("[project]\nname = 'custom-name'\n")

        state = detect_toolkit_state(tmp_path)
        assert state["toml_is_example"] is False

    def test_settings_generated(self, tmp_path):
        (tmp_path / ".claude").mkdir(parents=True)
        (tmp_path / ".claude" / "settings.json").write_text("{}\n")
        state = detect_toolkit_state(tmp_path)
        assert state["settings_generated"] is True

    def test_missing_skills(self, tmp_path):
        claude_dir = tmp_path / ".claude"
        toolkit_dir = claude_dir / "toolkit"
        toolkit_skills = toolkit_dir / "skills"
        project_skills = claude_dir / "skills"

        # Create toolkit skills
        (toolkit_skills / "review-suite").mkdir(parents=True)
        (toolkit_skills / "implement").mkdir(parents=True)
        (toolkit_skills / "plan").mkdir(parents=True)

        # Only create one project skill
        (project_skills / "review-suite").mkdir(parents=True)

        state = detect_toolkit_state(tmp_path)
        assert "implement" in state["missing_skills"]
        assert "plan" in state["missing_skills"]
        assert "review-suite" not in state["missing_skills"]

    def test_no_missing_skills(self, tmp_path):
        claude_dir = tmp_path / ".claude"
        toolkit_dir = claude_dir / "toolkit"
        toolkit_skills = toolkit_dir / "skills"
        project_skills = claude_dir / "skills"

        (toolkit_skills / "review-suite").mkdir(parents=True)
        (project_skills / "review-suite").mkdir(parents=True)

        state = detect_toolkit_state(tmp_path)
        assert state["missing_skills"] == []

    def test_missing_agents(self, tmp_path):
        claude_dir = tmp_path / ".claude"
        toolkit_dir = claude_dir / "toolkit"
        toolkit_agents = toolkit_dir / "agents"
        project_agents = claude_dir / "agents"

        toolkit_agents.mkdir(parents=True)
        project_agents.mkdir(parents=True)

        (toolkit_agents / "reviewer.md").write_text("# Reviewer\n")
        (toolkit_agents / "qa.md").write_text("# QA\n")
        (project_agents / "reviewer.md").write_text("# Reviewer\n")

        state = detect_toolkit_state(tmp_path)
        assert "qa.md" in state["missing_agents"]
        assert "reviewer.md" not in state["missing_agents"]

    def test_no_missing_agents(self, tmp_path):
        claude_dir = tmp_path / ".claude"
        toolkit_dir = claude_dir / "toolkit"
        toolkit_agents = toolkit_dir / "agents"
        project_agents = claude_dir / "agents"

        toolkit_agents.mkdir(parents=True)
        project_agents.mkdir(parents=True)

        (toolkit_agents / "reviewer.md").write_text("# Reviewer\n")
        (project_agents / "reviewer.md").write_text("# Reviewer\n")

        state = detect_toolkit_state(tmp_path)
        assert state["missing_agents"] == []

    def test_broken_symlinks(self, tmp_path):
        claude_dir = tmp_path / ".claude"
        claude_dir.mkdir(parents=True)

        # Create a broken symlink
        broken_link = claude_dir / "broken-link.md"
        broken_link.symlink_to("/nonexistent/target")

        state = detect_toolkit_state(tmp_path)
        assert "broken-link.md" in state["broken_symlinks"]

    def test_no_broken_symlinks(self, tmp_path):
        claude_dir = tmp_path / ".claude"
        claude_dir.mkdir(parents=True)

        # Create a valid symlink
        target = claude_dir / "target.md"
        target.write_text("# Target\n")
        link = claude_dir / "link.md"
        link.symlink_to(target)

        state = detect_toolkit_state(tmp_path)
        assert state["broken_symlinks"] == []

    def test_full_toolkit_install(self, tmp_path):
        """Simulate a complete toolkit installation."""
        claude_dir = tmp_path / ".claude"
        toolkit_dir = claude_dir / "toolkit"
        templates_dir = toolkit_dir / "templates"
        toolkit_skills = toolkit_dir / "skills"
        toolkit_agents = toolkit_dir / "agents"
        project_skills = claude_dir / "skills"
        project_agents = claude_dir / "agents"

        # Create toolkit structure
        templates_dir.mkdir(parents=True)
        (templates_dir / "toolkit.toml.example").write_text("[project]\nname = 'example'\n")

        # Skills
        (toolkit_skills / "review-suite").mkdir(parents=True)
        (project_skills / "review-suite").mkdir(parents=True)

        # Agents
        toolkit_agents.mkdir(parents=True)
        project_agents.mkdir(parents=True)
        (toolkit_agents / "reviewer.md").write_text("# Reviewer\n")
        (project_agents / "reviewer.md").write_text("# Reviewer\n")

        # Config
        (claude_dir / "toolkit.toml").write_text("[project]\nname = 'my-project'\n")
        (claude_dir / "settings.json").write_text("{}\n")

        state = detect_toolkit_state(tmp_path)
        assert state["subtree_exists"] is True
        assert state["toml_exists"] is True
        assert state["toml_is_example"] is False
        assert state["settings_generated"] is True
        assert state["missing_skills"] == []
        assert state["missing_agents"] == []
        assert state["broken_symlinks"] == []


# ===================================================================
# Lint command detection
# ===================================================================


class TestDetectLintCommands:
    def test_empty_stacks(self, tmp_path):
        result = detect_lint_commands(tmp_path, [])
        assert result == {}

    def test_unknown_stack(self, tmp_path):
        result = detect_lint_commands(tmp_path, ["rust"])
        assert result == {"rust": {"cmd": "", "available": False}}

    def test_python_lint_if_ruff_available(self, tmp_path):
        """Test that python lint is detected when ruff is available."""
        import shutil

        if shutil.which("ruff"):
            result = detect_lint_commands(tmp_path, ["python"])
            assert result["python"]["cmd"] == "ruff check"
            assert result["python"]["available"] is True
        else:
            result = detect_lint_commands(tmp_path, ["python"])
            assert result["python"]["available"] is False


# ===================================================================
# Format command detection
# ===================================================================


class TestDetectFormatCommands:
    def test_empty_stacks(self, tmp_path):
        result = detect_format_commands(tmp_path, [])
        assert result == {}

    def test_unknown_stack(self, tmp_path):
        result = detect_format_commands(tmp_path, ["rust"])
        assert result == {"rust": {"cmd": "", "check_cmd": "", "available": False}}

    def test_python_format_if_ruff_available(self, tmp_path):
        """Test that python format is detected when ruff is available."""
        import shutil

        if shutil.which("ruff"):
            result = detect_format_commands(tmp_path, ["python"])
            assert result["python"]["cmd"] == "ruff format"
            assert result["python"]["check_cmd"] == "ruff format --check ."
            assert result["python"]["available"] is True
        else:
            result = detect_format_commands(tmp_path, ["python"])
            assert result["python"]["available"] is False


# ===================================================================
# Full detection (run_detection)
# ===================================================================


class TestRunDetection:
    def test_empty_project(self, tmp_path):
        result = run_detection(tmp_path)
        assert "name" in result
        assert "stacks" in result
        assert result["stacks"] == []
        assert "version_file" in result
        assert "source_dirs" in result
        assert "lint" in result
        assert "test" in result
        assert "format" in result
        assert "toolkit_state" in result
        assert "makefile_targets" in result
        assert "package_scripts" in result

    def test_python_project(self, tmp_path):
        (tmp_path / "pyproject.toml").write_text("[project]\nname = 'foo'\n")
        (tmp_path / "src").mkdir()
        (tmp_path / "VERSION").write_text("1.0.0\n")
        result = run_detection(tmp_path)
        assert "python" in result["stacks"]
        assert "src" in result["source_dirs"]
        assert result["version_file"] == "pyproject.toml"
        assert "*.py" in result["source_extensions"]

    def test_typescript_project(self, tmp_path):
        (tmp_path / "tsconfig.json").write_text("{}\n")
        (tmp_path / "package.json").write_text(
            json.dumps({"version": "1.0.0", "scripts": {"test": "jest", "lint": "eslint"}})
        )
        (tmp_path / "src").mkdir()
        result = run_detection(tmp_path)
        assert "typescript" in result["stacks"]
        assert result["version_file"] == "package.json"
        assert "src" in result["source_dirs"]
        assert "*.ts" in result["source_extensions"]
        assert "test" in result["package_scripts"]
        assert "lint" in result["package_scripts"]

    def test_json_output_is_valid(self, tmp_path):
        result = run_detection(tmp_path)
        # Should be JSON-serializable
        json_str = json.dumps(result, indent=2, sort_keys=True)
        parsed = json.loads(json_str)
        assert parsed == result

    def test_validate_mode_adds_validations(self, tmp_path):
        (tmp_path / "Makefile").write_text("test:\n\techo test-pass\n")
        result = run_detection(tmp_path, validate=True)
        assert "validations" in result

    def test_no_validate_mode_no_validations(self, tmp_path):
        result = run_detection(tmp_path, validate=False)
        assert "validations" not in result


# ===================================================================
# CLI integration tests
# ===================================================================


class TestCLI:
    def test_basic_output(self, tmp_path):
        (tmp_path / "pyproject.toml").write_text("[project]\n")
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--project-dir", str(tmp_path)],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert "name" in output
        assert "stacks" in output
        assert "python" in output["stacks"]

    def test_json_output_valid(self, tmp_path):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--project-dir", str(tmp_path)],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        # Should be valid JSON
        output = json.loads(result.stdout)
        assert isinstance(output, dict)

    def test_validate_flag(self, tmp_path):
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--project-dir",
                str(tmp_path),
                "--validate",
            ],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert "validations" in output

    def test_nonexistent_dir(self):
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--project-dir",
                "/nonexistent/dir/12345",
            ],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 1
        assert "not a directory" in result.stderr

    def test_missing_project_dir_flag(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT)],
            capture_output=True,
            text=True,
        )
        assert result.returncode != 0

    def test_sorted_json_keys(self, tmp_path):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--project-dir", str(tmp_path)],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        output = json.loads(result.stdout)
        keys = list(output.keys())
        assert keys == sorted(keys), "JSON output keys should be sorted"

    def test_run_on_toolkit_repo(self):
        """Run detect-project.py on the toolkit repo itself."""
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--project-dir", str(ROOT)],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert output["name"] == "claude-toolkit"
        assert "python" in output["stacks"]

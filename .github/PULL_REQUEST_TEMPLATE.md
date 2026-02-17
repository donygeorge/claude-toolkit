## Summary

Brief description of the changes.

## Changes

- Change 1
- Change 2

## Testing

- [ ] `shellcheck -x -S warning` passes on all modified `.sh` files
- [ ] `python3 -m pytest tests/ -v` passes
- [ ] `bash tests/test_toolkit_cli.sh` passes (if CLI changed)
- [ ] `bash tests/test_hooks.sh` passes (if hooks changed)

## Checklist

- [ ] Agent prompts and skills remain generic (no project-specific content)
- [ ] Hooks use `_config.sh` variables (no hardcoded values)
- [ ] CHANGELOG.md updated

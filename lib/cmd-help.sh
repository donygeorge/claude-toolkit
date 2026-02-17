#!/usr/bin/env bash
# cmd-help.sh — Show usage information
#
# Sourced by toolkit.sh.

cmd_help() {
  echo "claude-toolkit CLI"
  echo ""
  echo "Usage: $0 <subcommand> [options]"
  echo ""
  echo "Subcommands:"
  echo "  init [--force] [--from-example] [--dry-run]  Initialize toolkit in project"
  echo "  update [version] [--latest] [--force]  Update toolkit from remote"
  echo "  customize <path>                  Convert managed file to customized"
  echo "  status                            Show toolkit status"
  echo "  validate                          Check toolkit health"
  echo "  doctor                            Comprehensive health check"
  echo "  generate-settings                 Regenerate settings.json and .mcp.json"
  echo "  explain [topic]                   Explain toolkit concepts"
  echo "  help                              Show this help"
  echo ""
  echo "Global flags:"
  echo "  --dry-run                         Show what would change without mutating"
  echo ""
  echo "Examples:"
  echo "  $0 init                     # Initialize (requires toolkit.toml)"
  echo "  $0 init --from-example      # Initialize with example toolkit.toml"
  echo "  $0 update                   # Update to latest tagged release"
  echo "  $0 update v1.2.0            # Update to specific version"
  echo "  $0 update --latest          # Update to latest main"
  echo "  $0 customize agents/reviewer.md  # Customize an agent"
  echo "  $0 status                   # Show current status"
  echo "  $0 validate                 # Check for issues"
  echo "  $0 generate-settings        # Regenerate config files"
  echo "  $0 explain hooks            # Learn about hooks"
  echo "  $0 explain config           # Learn about configuration"
}

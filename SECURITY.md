# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| 1.x     | Yes       |
| < 1.0   | No        |

## Reporting a Vulnerability

If you discover a security vulnerability in claude-toolkit, please report it
responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, please email the maintainer directly or use GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
feature on this repository.

### What to include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### What to expect

- Acknowledgment within 48 hours
- A plan for a fix within 7 days
- Credit in the release notes (unless you prefer anonymity)

## Security Considerations

This toolkit runs hooks that execute shell commands during Claude Code sessions.
Key security features include:

- **Guard hooks** block destructive operations and sensitive file writes
- **Audit logging** records all denied operations
- **Config-driven** behavior (no hardcoded secrets or paths)
- **Permission deny lists** prevent AI access to credentials and private keys
- **Atomic file writes** prevent corruption from concurrent access
- **Generated files** use restrictive permissions (0600)

## Scope

This policy covers the claude-toolkit repository. Security issues in Claude Code
itself should be reported to [Anthropic](https://www.anthropic.com).

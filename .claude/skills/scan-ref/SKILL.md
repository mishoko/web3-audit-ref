---
name: scan-ref
description: "Scans an audit reference for dangerous patterns: install hooks, encoded payloads, curl-pipe-bash, symlinks, git hooks, suspicious Makefiles, and other supply-chain threats. Use before adding or updating a ref, or on-demand to audit an existing ref. Does NOT modify any files."
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# Scan Audit Reference

Read-only security scanner. Checks for supply-chain threats before pinning.

## Run

```bash
# Full scan (local, ref must exist)
.claude/skills/scan-ref/scan_ref.sh <ref-name>

# Diff scan (only changes between two commits)
.claude/skills/scan-ref/scan_ref.sh <ref-name> <old-sha> <new-sha>

# Remote scan (safe-clones to temp dir, scans, cleans up — use before /add-ref)
.claude/skills/scan-ref/scan_ref.sh <ref-name> --url <repo-url> [<sha>]
```

## What it checks

| Severity | Pattern |
|---|---|
| CRITICAL | package.json install hooks, Python cmdclass, `curl\|bash`, encoded payloads |
| HIGH | Git hooks (`.husky/`, `.githooks/`), symlinks escaping the repo, LLM instruction files |
| MEDIUM | Makefiles with suspicious commands, dangerous CI triggers, eval/exec in scripts |
| INFO | All executable files |

## Interpreting results

The scanner flags patterns, not intent. Security reference repos often contain `curl | bash` in documentation (describing attacks) or `eval` in analysis tools. Review each finding in context. CRITICAL in a `.md` is usually benign; CRITICAL in a `.sh` needs investigation.

Exit codes: `0` = clean, `1` = high findings, `2` = critical findings.

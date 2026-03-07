---
name: remove-ref
description: "Removes a pinned audit reference from this repository. Use when the user explicitly asks to remove, delete, or retire an audit reference. Requires a stated reason before proceeding. Do NOT use for updating a ref's SHA (use update-ref) or temporarily disabling a ref."
allowed-tools:
  - Bash
  - Read
  - Grep
---

# Remove Audit Reference

## Before running

Confirm with the user:

1. The exact ref name (must exist under `audit-refs/`)
2. The reason for removal

## Run

```bash
.claude/skills/remove-ref/remove_ref.sh <ref-name> "<reason>"
```

## After the script finishes

The script stages all changes, prints the diff, and suggests a commit message. It does **not** commit.

1. Present the script's output to the user (it already contains the staged diff).
2. Wait for explicit commit approval before proceeding.
3. Use the commit message the script suggests.

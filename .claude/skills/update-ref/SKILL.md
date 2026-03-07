---
name: update-ref
description: "Updates the pinned SHA for an existing audit reference. Use when the user wants to upgrade or downgrade a ref to a different commit, asks to pull in new changes from an upstream repo, or wants to pin a ref to a specific SHA. Do NOT use for adding a brand new ref (use add-ref) or removing a ref entirely (use remove-ref)."
allowed-tools:
  - Bash
  - Read
  - Grep
---

# Update Pinned Reference

## Before running

Confirm with the user:

1. The ref name to update (must exist under `audit-refs/`)
2. The target SHA — or approval to use latest remote HEAD

## Run

```bash
.claude/skills/update-ref/update_ref.sh <ref-name> [<new-sha>]
```

## After the script finishes

The script stages all changes, prints the diff, and suggests a commit message. It does **not** commit.

1. Present the script's output to the user (it already contains the staged diff).
2. Wait for explicit commit approval before proceeding.
3. Use the commit message the script suggests.

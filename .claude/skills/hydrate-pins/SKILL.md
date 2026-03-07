---
name: hydrate-pins
description: "Initializes and pins all audit reference submodules after a fresh clone. Use when the user has just cloned the repository and needs to set up the submodules, or when submodules are missing or uninitialized. Do NOT use to update a ref to a new SHA (use update-ref) or to add a new ref (use add-ref)."
allowed-tools:
  - Bash
  - Read
---

# Hydrate Pins

Initializes all submodules and checks them out to their audited, pinned SHAs. Run once after a fresh clone.

## Run

```bash
.claude/skills/hydrate-pins/hydrate_pins.sh
```

The script initializes each submodule, blocks direct `git submodule update` in local config, checks out pinned SHAs, and verifies every one. Aborts on any mismatch.

## Verify

```bash
git submodule status
# All entries should show the pinned SHA with no leading + or -
```

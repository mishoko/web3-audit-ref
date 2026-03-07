# Agent Instructions — web3-audit-ref

Entrypoint for AI agents (Claude Code, Codex, Gemini CLI, etc.).

## Rules

- `audit-refs/` is **read-only**. Never modify or execute files inside submodules.
- Every submodule pointer change requires updates to: git index, `CHANGELOG.md`, and `hydrate_pins.sh`.
- Human approval is required before every commit. Never commit automatically.
- Never run `git submodule update` — use the skills below instead.
- Always verify staged SHAs with `git ls-files --stage` before committing.
- **Ref naming convention:** `<org>-<repo>` in lowercase (e.g., `cyfrin-solskill` for `https://github.com/Cyfrin/solskill`). Derive `<org>` and `<repo>` from the GitHub URL.

## Skills

| Task | Skill | Script |
|---|---|---|
| Scan for threats | `/scan-ref` | `.claude/skills/scan-ref/scan_ref.sh <ref-name> [old-sha new-sha]` |
| Add a reference | `/add-ref` | `.claude/skills/add-ref/add_ref.sh <ref-name> <repo-url> [sha]` |
| Update a pin | `/update-ref` | `.claude/skills/update-ref/update_ref.sh <ref-name> [sha]` |
| Remove a reference | `/remove-ref` | `.claude/skills/remove-ref/remove_ref.sh <ref-name> "<reason>"` |
| Initialize after clone | `/hydrate-pins` | `.claude/skills/hydrate-pins/hydrate_pins.sh` |

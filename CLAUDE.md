# Claude Code Instructions — web3-audit-ref

This repository is a **security-critical, read-only reference vault** for Web3 auditors.

`AGENTS.md` is the single source of truth for all rules and workflows. Follow it exactly.

## Claude-specific notes

- `/add-ref` auto-scans before adding (no separate `/scan-ref` needed). Use `/scan-ref` standalone for ad-hoc audits or before `/update-ref`.
- Always show the staged diff to the user before suggesting a commit.
- If the user asks to "add a repo" or gives a GitHub URL, invoke `/add-ref`.
- If the user asks to "update" or "upgrade" a ref, invoke `/update-ref`.
- If the user asks to "remove" or "delete" a ref, invoke `/remove-ref` (requires a stated reason).

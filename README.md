# web3-audit-ref

A curated, version-pinned vault of external security tools and methodologies for Web3 smart contract auditing. Every reference is locked to a specific, human-reviewed commit — not a branch.

## Why This Exists

When you `git submodule update`, git fetches whatever the upstream branch points to *right now*. If that repo gets compromised, you silently pull malicious code into your audit environment.

This repo solves that:

- Every reference is pinned to an **exact commit SHA** — a cryptographic fingerprint
- No code enters without a human reviewing the diff and approving the pin
- No CI/CD, no auto-fetchers, no install-on-clone magic

## Quick Start

```bash
# 1. Clone (never use --recurse-submodules)
git clone https://github.com/mishoko/web3-audit-ref.git
cd web3-audit-ref

# 2. Review the setup script before running it
cat .claude/skills/hydrate-pins/hydrate_pins.sh

# 3. Initialize and pin all references
chmod +x .claude/skills/hydrate-pins/hydrate_pins.sh
.claude/skills/hydrate-pins/hydrate_pins.sh

# 4. Verify
git submodule status
```

All references are now checked out at their audited commits. Browse them freely — just don't run anything inside `audit-refs/` without reading it first.

## Managing References

The easiest way to manage this vault is through an AI coding agent (Claude Code, Codex, Gemini CLI, etc.). Just tell it what you want in plain English:

```
You:   Add the slither-action repo from crytic as an audit reference
Agent: Resolved HEAD at abc123. Here's the summary...
       [shows staged diff, waits for your approval before committing]
```

```
You:   Update tob-skills to the latest commit
Agent: 3 new commits since current pin. Here's what changed...
       [shows diff, waits for your OK]
```

```
You:   Scan tob-skills for dangerous scripts or hooks
Agent: Found 0 critical issues in actual code. 9 flagged in documentation
       files (expected — they describe attack vectors). Safe to pin.
```

```
You:   Remove test-submodules, not needed anymore
Agent: Removing audit-refs/test-submodules...
       [shows staged diff, waits for approval]
```

Every operation verifies SHA integrity, updates all tracking files, and **never commits without your explicit approval**.

### Manual usage (without an agent)

All operations are plain bash scripts in `.claude/skills/`:

| Task | Command |
|---|---|
| Initialize after clone | `.claude/skills/hydrate-pins/hydrate_pins.sh` |
| Scan for threats | `.claude/skills/scan-ref/scan_ref.sh <name>` |
| Add a reference | `.claude/skills/add-ref/add_ref.sh <name> <url> [sha]` |
| Update a pin | `.claude/skills/update-ref/update_ref.sh <name> [sha]` |
| Remove a reference | `.claude/skills/remove-ref/remove_ref.sh <name> "<reason>"` |

Each script stages changes but **never commits** — you review the diff and commit yourself.

## What's Pinned

| Reference | Repository | Pinned SHA |
|---|---|---|
| `audit-refs/pashov-skills` | pashov/skills | `579dca98` |
| `audit-refs/trailofbits-skills` | trailofbits/skills | `c6097699` |
| `audit-refs/cyfrin-solskill` | Cyfrin/solskill | `5fec89ed` |
| `audit-refs/kadenzipfel-scv-scan` | kadenzipfel/scv-scan | `dcb0201a` |
| `audit-refs/quillai-network-qs_skills` | quillai-network/qs_skills | `75d48a8a` |
| `audit-refs/archethect-sc-auditor` | Archethect/sc-auditor | `a7f06020` |
| `audit-refs/auditmos-skills` | auditmos/skills | `c958b3ab` |

Full SHAs and review notes are in [`CHANGELOG.md`](CHANGELOG.md).

## Verifying This Repo

Don't trust us — verify:

```bash
cat .gitmodules                        # verify URLs
git ls-files --stage audit-refs/       # verify pinned SHAs
git log --oneline --all -- audit-refs/ # verify change history
```

## Repository Structure

```
web3-audit-ref/
├── audit-refs/              # Pinned submodules (read-only)
├── .claude/skills/          # Agent skills + bash scripts
│   ├── lib.sh               # Shared functions
│   ├── scan-ref/            # Security pre-flight scanner
│   ├── hydrate-pins/        # Initialize pins after clone
│   ├── add-ref/             # Add a new pinned reference
│   ├── update-ref/          # Update a pin to a new SHA
│   └── remove-ref/          # Remove a pinned reference
├── AGENTS.md                # AI agent entrypoint
├── CLAUDE.md                # Claude Code instructions
├── CHANGELOG.md             # Pin audit trail
├── LICENSE                  # MIT
└── README.md
```

## No CI/CD by Design

This repository has no GitHub Actions, no pre-commit hooks, and no install scripts. Security tooling for auditors must be understood before it is run.

## License

The contents of `audit-refs/` are governed by the licenses of their respective upstream repositories. This repository's own files are released under [MIT](LICENSE).

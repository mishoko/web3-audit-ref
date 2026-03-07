#!/usr/bin/env bash
# hydrate_pins.sh — Initialize and pin all audit references
# ---------------------------------------------------------------------------
# Pins all submodules to their audited SHAs. Run once after a fresh clone.
#
# USAGE:
#   chmod +x .claude/skills/hydrate-pins/hydrate_pins.sh
#   .claude/skills/hydrate-pins/hydrate_pins.sh
#
# After running, verify:  git submodule status
# ---------------------------------------------------------------------------

source "$(dirname "$0")/../lib.sh"

# ---------------------------------------------------------------------------
# PINNED COMMITS — Change these ONLY after a manual code review.
# Document your review in CHANGELOG.md before updating.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
info "Initializing git submodules (fetch only, no auto-execution)..."

command -v python3 >/dev/null 2>&1 || abort "python3 is required to configure the submodule block guard."

info "Configuring local git to block direct submodule updates..."
BLOCK_CMD='!{ printf "\n\033[1;31m[BLOCKED]\033[0m Direct submodule update is not allowed.\n         Run ./update_ref.sh <ref-name> instead.\n         See AGENTS.md for the required workflow.\n\n" >&2; exit 1; }'
REFS=()
for REF in "${REFS[@]}"; do
    git config submodule."${REF}".update "BLOCK_PLACEHOLDER"
done
BLOCK_CMD="$BLOCK_CMD" python3 -c "
import os; c = open('.git/config').read()
c = c.replace('update = BLOCK_PLACEHOLDER', 'update = ' + os.environ['BLOCK_CMD'])
open('.git/config', 'w').write(c)"
ok "Direct submodule updates are now blocked."

info "Verifying SHAs match expected pinned commits..."

echo ""
ok "Setup complete. All references are pinned to audited commits."
warn "DO NOT run any build scripts inside audit-refs/ without reviewing them first."
echo ""
echo "Next step — verify:  git submodule status"

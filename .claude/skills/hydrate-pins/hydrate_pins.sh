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
PIN_PASHOV_SKILLS="579dca98e5ec81852d6e032c99d19b6cfcdb5fa4"
PIN_TRAILOFBITS_SKILLS="c6097699e4553f0dda4db615330f4a5097c4ff99"
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
info "Initializing git submodules (fetch only, no auto-execution)..."
git submodule update --init --checkout --no-recommend-shallow audit-refs/pashov-skills
git submodule update --init --checkout --no-recommend-shallow audit-refs/trailofbits-skills

command -v python3 >/dev/null 2>&1 || abort "python3 is required to configure the submodule block guard."

info "Configuring local git to block direct submodule updates..."
BLOCK_CMD='!{ printf "\n\033[1;31m[BLOCKED]\033[0m Direct submodule update is not allowed.\n         Run ./update_ref.sh <ref-name> instead.\n         See AGENTS.md for the required workflow.\n\n" >&2; exit 1; }'
REFS=("audit-refs/pashov-skills" "audit-refs/trailofbits-skills")
for REF in "${REFS[@]}"; do
    git config submodule."${REF}".update "BLOCK_PLACEHOLDER"
done
BLOCK_CMD="$BLOCK_CMD" python3 -c "
import os; c = open('.git/config').read()
c = c.replace('update = BLOCK_PLACEHOLDER', 'update = ' + os.environ['BLOCK_CMD'])
open('.git/config', 'w').write(c)"
ok "Direct submodule updates are now blocked."

info "Pinning audit-refs/pashov-skills..."
echo "  Repository : https://github.com/pashov/skills"
echo "  Pinned SHA : $PIN_PASHOV_SKILLS"
echo "  Commit msg : $(git -C audit-refs/pashov-skills log -1 --pretty='%s' "$PIN_PASHOV_SKILLS")"
git -C audit-refs/pashov-skills checkout "$PIN_PASHOV_SKILLS"

info "Pinning audit-refs/trailofbits-skills..."
echo "  Repository : https://github.com/trailofbits/skills"
echo "  Pinned SHA : $PIN_TRAILOFBITS_SKILLS"
echo "  Commit msg : $(git -C audit-refs/trailofbits-skills log -1 --pretty='%s' "$PIN_TRAILOFBITS_SKILLS")"
git -C audit-refs/trailofbits-skills checkout "$PIN_TRAILOFBITS_SKILLS"

info "Verifying SHAs match expected pinned commits..."
verify_sha "pashov-skills" "audit-refs/pashov-skills" "$PIN_PASHOV_SKILLS"
verify_sha "trailofbits-skills" "audit-refs/trailofbits-skills" "$PIN_TRAILOFBITS_SKILLS"

echo ""
ok "Setup complete. All references are pinned to audited commits."
warn "DO NOT run any build scripts inside audit-refs/ without reviewing them first."
echo ""
echo "Next step — verify:  git submodule status"

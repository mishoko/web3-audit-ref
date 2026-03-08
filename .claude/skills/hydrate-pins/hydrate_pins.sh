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
PIN_CYFRIN_SOLSKILL="5fec89edae882c19a32ec996a1846dace53eafeb"
PIN_KADENZIPFEL_SCV_SCAN="dcb0201a119a21bcf04ea4b991561f73360ad68c"
PIN_QUILLAI_NETWORK_QS_SKILLS="75d48a8a4abbf7e6938a48beddc2585ee8e4e27f"
PIN_ARCHETHECT_SC_AUDITOR="a7f06020b8ecca4b35ffe39d4eda42cb2293a03a"
PIN_AUDITMOS_SKILLS="c958b3abb0ce189d9f39a05caf94b5a5da655010"
PIN_OPENZEPPELIN_OPENZEPPELIN_SKILLS="0ba03a1dae8aee52d6d945d060eceaa74f7eee24"
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
info "Initializing git submodules (fetch only, no auto-execution)..."
git submodule update --init --checkout --no-recommend-shallow audit-refs/pashov-skills
git submodule update --init --checkout --no-recommend-shallow audit-refs/trailofbits-skills
git submodule update --init --checkout --no-recommend-shallow audit-refs/cyfrin-solskill
git submodule update --init --checkout --no-recommend-shallow audit-refs/kadenzipfel-scv-scan
git submodule update --init --checkout --no-recommend-shallow audit-refs/quillai-network-qs_skills
git submodule update --init --checkout --no-recommend-shallow audit-refs/archethect-sc-auditor
git submodule update --init --checkout --no-recommend-shallow audit-refs/auditmos-skills
git submodule update --init --checkout --no-recommend-shallow audit-refs/openzeppelin-openzeppelin-skills

command -v python3 >/dev/null 2>&1 || abort "python3 is required to configure the submodule block guard."

info "Configuring local git to block direct submodule updates..."
BLOCK_CMD='!{ printf "\n\033[1;31m[BLOCKED]\033[0m Direct submodule update is not allowed.\n         Run ./update_ref.sh <ref-name> instead.\n         See AGENTS.md for the required workflow.\n\n" >&2; exit 1; }'
REFS=("audit-refs/pashov-skills" "audit-refs/trailofbits-skills" "audit-refs/cyfrin-solskill" "audit-refs/kadenzipfel-scv-scan" "audit-refs/quillai-network-qs_skills" "audit-refs/archethect-sc-auditor" "audit-refs/auditmos-skills" "audit-refs/openzeppelin-openzeppelin-skills")
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

info "Pinning audit-refs/cyfrin-solskill..."
echo "  Repository : https://github.com/Cyfrin/solskill"
echo "  Pinned SHA : $PIN_CYFRIN_SOLSKILL"
echo "  Commit msg : $(git -C audit-refs/cyfrin-solskill log -1 --pretty='%s' "$PIN_CYFRIN_SOLSKILL")"
git -C audit-refs/cyfrin-solskill checkout "$PIN_CYFRIN_SOLSKILL"

info "Pinning audit-refs/kadenzipfel-scv-scan..."
echo "  Repository : https://github.com/kadenzipfel/scv-scan"
echo "  Pinned SHA : $PIN_KADENZIPFEL_SCV_SCAN"
echo "  Commit msg : $(git -C audit-refs/kadenzipfel-scv-scan log -1 --pretty='%s' "$PIN_KADENZIPFEL_SCV_SCAN")"
git -C audit-refs/kadenzipfel-scv-scan checkout "$PIN_KADENZIPFEL_SCV_SCAN"

info "Pinning audit-refs/quillai-network-qs_skills..."
echo "  Repository : https://github.com/quillai-network/qs_skills"
echo "  Pinned SHA : $PIN_QUILLAI_NETWORK_QS_SKILLS"
echo "  Commit msg : $(git -C audit-refs/quillai-network-qs_skills log -1 --pretty='%s' "$PIN_QUILLAI_NETWORK_QS_SKILLS")"
git -C audit-refs/quillai-network-qs_skills checkout "$PIN_QUILLAI_NETWORK_QS_SKILLS"

info "Pinning audit-refs/archethect-sc-auditor..."
echo "  Repository : https://github.com/Archethect/sc-auditor"
echo "  Pinned SHA : $PIN_ARCHETHECT_SC_AUDITOR"
echo "  Commit msg : $(git -C audit-refs/archethect-sc-auditor log -1 --pretty='%s' "$PIN_ARCHETHECT_SC_AUDITOR")"
git -C audit-refs/archethect-sc-auditor checkout "$PIN_ARCHETHECT_SC_AUDITOR"

info "Pinning audit-refs/auditmos-skills..."
echo "  Repository : https://github.com/auditmos/skills"
echo "  Pinned SHA : $PIN_AUDITMOS_SKILLS"
echo "  Commit msg : $(git -C audit-refs/auditmos-skills log -1 --pretty='%s' "$PIN_AUDITMOS_SKILLS")"
git -C audit-refs/auditmos-skills checkout "$PIN_AUDITMOS_SKILLS"

info "Pinning audit-refs/openzeppelin-openzeppelin-skills..."
echo "  Repository : https://github.com/OpenZeppelin/openzeppelin-skills"
echo "  Pinned SHA : $PIN_OPENZEPPELIN_OPENZEPPELIN_SKILLS"
echo "  Commit msg : $(git -C audit-refs/openzeppelin-openzeppelin-skills log -1 --pretty='%s' "$PIN_OPENZEPPELIN_OPENZEPPELIN_SKILLS")"
git -C audit-refs/openzeppelin-openzeppelin-skills checkout "$PIN_OPENZEPPELIN_OPENZEPPELIN_SKILLS"

info "Verifying SHAs match expected pinned commits..."
verify_sha "pashov-skills" "audit-refs/pashov-skills" "$PIN_PASHOV_SKILLS"
verify_sha "trailofbits-skills" "audit-refs/trailofbits-skills" "$PIN_TRAILOFBITS_SKILLS"
verify_sha "cyfrin-solskill" "audit-refs/cyfrin-solskill" "$PIN_CYFRIN_SOLSKILL"
verify_sha "kadenzipfel-scv-scan" "audit-refs/kadenzipfel-scv-scan" "$PIN_KADENZIPFEL_SCV_SCAN"
verify_sha "quillai-network-qs_skills" "audit-refs/quillai-network-qs_skills" "$PIN_QUILLAI_NETWORK_QS_SKILLS"
verify_sha "archethect-sc-auditor" "audit-refs/archethect-sc-auditor" "$PIN_ARCHETHECT_SC_AUDITOR"
verify_sha "auditmos-skills" "audit-refs/auditmos-skills" "$PIN_AUDITMOS_SKILLS"
verify_sha "openzeppelin-openzeppelin-skills" "audit-refs/openzeppelin-openzeppelin-skills" "$PIN_OPENZEPPELIN_OPENZEPPELIN_SKILLS"

echo ""
ok "Setup complete. All references are pinned to audited commits."
warn "DO NOT run any build scripts inside audit-refs/ without reviewing them first."
echo ""
echo "Next step — verify:  git submodule status"

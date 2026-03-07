#!/usr/bin/env bash
# update_ref.sh — Update a pinned audit reference to a new SHA
# ---------------------------------------------------------------------------
# USAGE:
#   ./update_ref.sh <ref-name> [<new-sha>]
#
# EXAMPLES:
#   ./update_ref.sh tob-skills              # fetch latest, you choose the SHA
#   ./update_ref.sh tob-skills abc123def    # pin directly to a specific SHA
# ---------------------------------------------------------------------------

source "$(dirname "$0")/../lib.sh"

# --- Validate inputs ---
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <ref-name> [<new-sha>]"
    echo ""
    echo "Available refs:"
    ls audit-refs/
    exit 1
fi

REF_NAME="$1"
validate_ref_name "$REF_NAME"
REF_PATH="audit-refs/${REF_NAME}"
REQUESTED_SHA="${2:-}"
PIN_VAR=$(ref_to_pin_var "$REF_NAME")

[ ! -d "$REF_PATH/.git" ] && [ ! -f "$REF_PATH/.git" ] \
    && abort "'$REF_PATH' is not an initialized submodule. Run hydrate_pins.sh first."

require_managed_ref "$REF_NAME"
OLD_SHA=$(read_pin_sha "$PIN_VAR")

# --- Step 1: Fetch upstream ---
info "Fetching latest commits for ${REF_PATH}..."
git -C "$REF_PATH" fetch origin

REMOTE_HEAD=$(git -C "$REF_PATH" rev-parse origin/HEAD 2>/dev/null \
    || git -C "$REF_PATH" rev-parse origin/main 2>/dev/null \
    || git -C "$REF_PATH" rev-parse origin/master 2>/dev/null \
    || true)
[ -z "$REMOTE_HEAD" ] && abort "Could not determine remote HEAD. Check that the remote has a main/master branch."

echo "  Current pin : $OLD_SHA"
echo "  Remote HEAD : $REMOTE_HEAD"

if [ "$OLD_SHA" = "$REMOTE_HEAD" ] && [ -z "$REQUESTED_SHA" ]; then
    ok "Already at latest remote HEAD. Nothing to update."
    exit 0
fi

# --- Step 2: Resolve target SHA ---
NEW_SHA="${REQUESTED_SHA:-$REMOTE_HEAD}"
# Resolve short SHAs to full 40-char form (needed for verification comparisons)
NEW_SHA=$(git -C "$REF_PATH" rev-parse "$NEW_SHA" 2>/dev/null) \
    || abort "Could not resolve SHA '${REQUESTED_SHA:-HEAD}' in ${REF_PATH}. Is it a valid commit?"

if git -C "$REF_PATH" merge-base --is-ancestor "$NEW_SHA" "$OLD_SHA" 2>/dev/null; then
    DIRECTION="downgrade"
    LOG_RANGE="${NEW_SHA}..${OLD_SHA}"
    warn "This is a DOWNGRADE — moving to an older commit."
    echo "  Commits that will be removed:"
else
    DIRECTION="upgrade"
    LOG_RANGE="${OLD_SHA}..${NEW_SHA}"
    echo "  Commits that will be added:"
fi

info "Commit log (${DIRECTION}):"
git -C "$REF_PATH" log --oneline "${LOG_RANGE}" 2>/dev/null \
    || warn "Could not compute log — SHA may not be in local history."

echo ""
info "File changes (${OLD_SHA:0:8} -> ${NEW_SHA:0:8}):"
git -C "$REF_PATH" diff --stat "${OLD_SHA}" "${NEW_SHA}" 2>/dev/null \
    || warn "Could not compute diff — SHA may not be in local history."

echo ""
warn "Proceeding to pin ${REF_NAME} to ${NEW_SHA:0:8}."

# --- Step 3: Checkout, stage, verify ---
info "Checking out ${NEW_SHA}..."
checkout_and_verify "$REF_PATH" "$NEW_SHA"
stage_and_verify "$REF_PATH" "$NEW_SHA"

# --- Step 4: Update hydrate_pins.sh ---
info "Updating ${HYDRATE_SCRIPT}..."
sedi "s/^${PIN_VAR}=\"${OLD_SHA}\"/${PIN_VAR}=\"${NEW_SHA}\"/" "$HYDRATE_SCRIPT"
UPDATED_SHA=$(read_pin_sha "$PIN_VAR")
[ "$UPDATED_SHA" != "$NEW_SHA" ] && abort "Failed to update ${PIN_VAR} in ${HYDRATE_SCRIPT}"
ok "${HYDRATE_SCRIPT} updated."
git add "$HYDRATE_SCRIPT"

# --- Step 5: Update README.md ---
info "Updating README.md..."
# README table uses 8-char short SHAs — scope replacement to the ref's table row
sedi "/\`audit-refs\/${REF_NAME}\`/s/\`${OLD_SHA:0:8}\`/\`${NEW_SHA:0:8}\`/" README.md
git add README.md
ok "README.md updated."

# --- Step 6: Update CHANGELOG.md ---
info "Updating CHANGELOG.md..."
COMMIT_MSG=$(git -C "$REF_PATH" log -1 --pretty='%s' "$NEW_SHA")
SHORT_OLD="${OLD_SHA:0:8}"
SHORT_NEW="${NEW_SHA:0:8}"

prepend_changelog "## [Updated] — $(date +%Y-%m-%d)

### audit-refs/${REF_NAME}
- **Old SHA:** \`${OLD_SHA}\`
- **New SHA:** \`${NEW_SHA}\`
- **Commit message:** \`${COMMIT_MSG}\`
- **Review notes:** Manually reviewed diff from ${SHORT_OLD} to ${SHORT_NEW}.

---
"

# --- Step 7: Final verification ---
info "Running final verification..."
VERIFIED=true
INDEX_SHA=$(git ls-files --stage "$REF_PATH" | awk '{print $2}')
[ "$INDEX_SHA" = "$NEW_SHA" ] && ok "Index SHA correct." || { warn "Index SHA mismatch"; VERIFIED=false; }
grep -q "${PIN_VAR}=\"${NEW_SHA}\"" "$HYDRATE_SCRIPT" && ok "PIN variable correct." || { warn "PIN variable mismatch"; VERIFIED=false; }
grep -q "$NEW_SHA" CHANGELOG.md && ok "CHANGELOG entry present." || { warn "CHANGELOG missing entry"; VERIFIED=false; }
[ "$VERIFIED" = false ] && abort "Verification failed."

show_staged_diff "audit-refs: update ${REF_NAME} to ${SHORT_NEW} (reviewed: $(date +%Y-%m-%d))"
ok "Update complete. Commit when satisfied with the diff above."

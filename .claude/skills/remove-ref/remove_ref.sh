#!/usr/bin/env bash
# remove_ref.sh — Remove a pinned audit reference
# ---------------------------------------------------------------------------
# USAGE:
#   ./remove_ref.sh <ref-name> "<removal-reason>"
#
# EXAMPLES:
#   ./remove_ref.sh nemesis-auditor "not needed now"
#   ./remove_ref.sh tob-skills "superseded by internal tooling"
# ---------------------------------------------------------------------------

source "$(dirname "$0")/../lib.sh"

# --- Validate inputs ---
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <ref-name> \"<removal-reason>\""
    echo ""
    echo "Available refs:"
    ls audit-refs/
    exit 1
fi

REF_NAME="$1"
validate_ref_name "$REF_NAME"
REMOVAL_REASON="$2"
REF_PATH="audit-refs/${REF_NAME}"
PIN_VAR=$(ref_to_pin_var "$REF_NAME")

require_managed_ref "$REF_NAME"
OLD_SHA=$(read_pin_sha "$PIN_VAR")

echo ""
echo "  Ref path    : $REF_PATH"
echo "  Pinned SHA  : $OLD_SHA"
if [ -d "$REF_PATH" ]; then
    echo "  Commit msg  : $(git -C "$REF_PATH" log -1 --pretty='%s' "$OLD_SHA" 2>/dev/null || echo "(unavailable)")"
fi
echo "  Reason      : $REMOVAL_REASON"
echo ""
warn "Removing $REF_PATH — this cannot be undone without re-adding the submodule."

# --- Step 1: Deinit and remove submodule ---
info "Deinitializing submodule..."
if git submodule status "$REF_PATH" &>/dev/null; then
    git submodule deinit -f "$REF_PATH"
    ok "Submodule deinitialized."
else
    ok "Submodule already deinitialized."
fi

info "Removing from git index and working tree..."
if git ls-files --stage "$REF_PATH" | grep -q .; then
    git rm -f "$REF_PATH"
    ok "Removed from index."
else
    ok "Already absent from index."
fi

info "Clearing .git/modules cache..."
rm -rf ".git/modules/${REF_PATH}"
ok ".git/modules cache cleared."

# --- Step 2: Update hydrate_pins.sh ---
info "Updating ${HYDRATE_SCRIPT}..."

sedi "/^${PIN_VAR}=\"/d" "$HYDRATE_SCRIPT"
sedi "\|git submodule update --init --checkout --no-recommend-shallow ${REF_PATH}|d" "$HYDRATE_SCRIPT"
sedi "s| \"${REF_PATH}\"||g" "$HYDRATE_SCRIPT"
sedi "s|\"${REF_PATH}\" ||g" "$HYDRATE_SCRIPT"
sedi "s|\"${REF_PATH}\"||g" "$HYDRATE_SCRIPT"

# Remove pinning block: info "Pinning audit-refs/<name>..." through next blank line
awk -v ref="$REF_PATH" '
    /^info "Pinning / && index($0, ref) { skip=1; next }
    skip && /^$/ { skip=0; next }
    skip { next }
    { print }
' "$HYDRATE_SCRIPT" | safe_mv "$HYDRATE_SCRIPT"

sedi "/^verify_sha \"${REF_NAME}\" /d" "$HYDRATE_SCRIPT"

git add "$HYDRATE_SCRIPT"
ok "${HYDRATE_SCRIPT} updated."

# --- Step 3: Update README.md ---
info "Updating README.md..."
sedi "/[[:space:]]${REF_NAME}\//d" README.md
sedi "/\`audit-refs\/${REF_NAME}\`/d" README.md
git add README.md
ok "README.md updated."

# --- Step 4: Update CHANGELOG.md ---
info "Updating CHANGELOG.md..."
prepend_changelog "## [Removed] — $(date +%Y-%m-%d)

### audit-refs/${REF_NAME}
- **Reason:** ${REMOVAL_REASON}

---
"

# --- Step 5: Final verification ---
info "Running final verification..."
VERIFIED=true
git ls-files --stage audit-refs/ | grep -q "	audit-refs/${REF_NAME}$" \
    && { warn "Ref still present in git index!"; VERIFIED=false; } \
    || ok "Ref absent from git index."
grep -q "^${PIN_VAR}=" "$HYDRATE_SCRIPT" \
    && { warn "PIN variable still present!"; VERIFIED=false; } \
    || ok "PIN variable removed."
grep -q "### audit-refs/${REF_NAME}" CHANGELOG.md \
    && ok "CHANGELOG removal entry present." \
    || { warn "CHANGELOG missing removal entry"; VERIFIED=false; }
[ "$VERIFIED" = false ] && abort "Verification failed."

show_staged_diff "audit-refs: remove ${REF_NAME} (${REMOVAL_REASON}) on $(date +%Y-%m-%d)"
ok "Removal complete. Commit when satisfied with the diff above."

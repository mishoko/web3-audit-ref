#!/usr/bin/env bash
# add_ref.sh — Add a new pinned audit reference
# ---------------------------------------------------------------------------
# USAGE:
#   ./add_ref.sh [--skip-scan] <ref-name> <repo-url> [<sha>] [<description>] [<review-notes>]
#
# OPTIONS:
#   --skip-scan   Skip the security scan (use only after a scan has already been reviewed)
#
# EXAMPLES:
#   ./add_ref.sh nemesis-auditor https://github.com/0xiehnnkta/nemesis-auditor
#   ./add_ref.sh nemesis-auditor https://github.com/0xiehnnkta/nemesis-auditor 83c28b74...
#   ./add_ref.sh --skip-scan nemesis-auditor https://github.com/0xiehnnkta/nemesis-auditor
# ---------------------------------------------------------------------------

source "$(dirname "$0")/../lib.sh"

# --- Parse flags ---
SKIP_SCAN=false
if [ "${1:-}" = "--skip-scan" ]; then
    SKIP_SCAN=true
    shift
fi

# --- Validate inputs ---
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 [--skip-scan] <ref-name> <repo-url> [<sha>] [<description>] [<review-notes>]"
    exit 1
fi

REF_NAME="$1"
validate_ref_name "$REF_NAME"
REPO_URL="$2"
REQUESTED_SHA="${3:-}"
DESCRIPTION="${4:-$(echo "$REPO_URL" | sed 's|https://github.com/||')}"
REVIEW_NOTES="${5:-Human reviewed and approved at invocation.}"
REF_PATH="audit-refs/${REF_NAME}"
PIN_VAR=$(ref_to_pin_var "$REF_NAME")

# Guards
grep -q "^${PIN_VAR}=" "$HYDRATE_SCRIPT" 2>/dev/null \
    && abort "'${REF_NAME}' is already a managed ref. Use update_ref.sh to change its SHA."
[ -d "${REF_PATH}" ] \
    && abort "'${REF_PATH}' already exists. Remove it first with remove_ref.sh."

# --- Step 1: Resolve SHA ---
info "Resolving SHA..."
if [ -n "$REQUESTED_SHA" ]; then
    PIN_SHA="$REQUESTED_SHA"
    echo "  Using provided SHA : $PIN_SHA"
else
    PIN_SHA=$(git ls-remote "$REPO_URL" HEAD | awk '{print $1}')
    [ -z "$PIN_SHA" ] && abort "Could not resolve HEAD from $REPO_URL"
    echo "  Resolved HEAD      : $PIN_SHA"
fi

echo ""
echo "  Ref path    : $REF_PATH"
echo "  Repository  : $REPO_URL"
echo "  Pin SHA     : $PIN_SHA"
echo "  Description : $DESCRIPTION"
echo ""

# --- Step 1b: Pre-add security scan ---
SCAN_SCRIPT="$(dirname "$0")/../scan-ref/scan_ref.sh"
if [ "$SKIP_SCAN" = true ]; then
    warn "Skipping security scan (--skip-scan). Assuming findings were already reviewed."
elif [ -x "$SCAN_SCRIPT" ]; then
    info "Running security scan before adding..."
    if "$SCAN_SCRIPT" "$REF_NAME" --url "$REPO_URL" "$PIN_SHA"; then
        ok "Security scan passed."
    else
        SCAN_EXIT=$?
        echo ""
        if [ "$SCAN_EXIT" -eq 2 ]; then
            warn "CRITICAL findings detected. The ref has NOT been added."
        else
            warn "HIGH-severity findings detected. The ref has NOT been added."
        fi
        echo "  Review the findings above with the user."
        echo "  If they confirm, re-run with --skip-scan:"
        echo ""
        echo "    $0 --skip-scan $REF_NAME $REPO_URL ${REQUESTED_SHA:+$REQUESTED_SHA}"
        echo ""
        exit "$SCAN_EXIT"
    fi
else
    warn "scan_ref.sh not found or not executable — skipping pre-add scan."
fi

warn "Proceeding to add ${REF_NAME} at ${PIN_SHA:0:8}."

# --- Step 2: Add submodule ---
info "Adding submodule..."
git submodule add "$REPO_URL" "$REF_PATH"
git config -f .gitmodules submodule."${REF_PATH}".update none
git add .gitmodules
ok "Submodule added with update = none."

# --- Step 3: Pin and stage ---
info "Pinning to ${PIN_SHA}..."
checkout_and_verify "$REF_PATH" "$PIN_SHA"
stage_and_verify "$REF_PATH" "$PIN_SHA"

# --- Step 4: Update hydrate_pins.sh (5 locations) ---
info "Updating ${HYDRATE_SCRIPT}..."

# A) PIN variable — insert after last PIN_ line, or after the pinned-commits comment block
awk -v pin="${PIN_VAR}=\"${PIN_SHA}\"" '
    /^PIN_/ { last=NR }
    /^# Document your review/ && !last { last=NR }
    { lines[NR]=$0 }
    END { for (i=1; i<=NR; i++) { print lines[i]; if (i==last) print pin } }
' "$HYDRATE_SCRIPT" | safe_mv "$HYDRATE_SCRIPT"
grep -q "^${PIN_VAR}=" "$HYDRATE_SCRIPT" || abort "Failed to insert ${PIN_VAR} into ${HYDRATE_SCRIPT}"

# B) Init line — insert after last git submodule update --init line, or after the init info message
awk -v newline="git submodule update --init --checkout --no-recommend-shallow ${REF_PATH}" '
    /git submodule update --init --checkout --no-recommend-shallow/ { last=NR }
    /^info "Initializing git submodules/ && !last { last=NR }
    { lines[NR]=$0 }
    END { for (i=1; i<=NR; i++) { print lines[i]; if (i==last) print newline } }
' "$HYDRATE_SCRIPT" | safe_mv "$HYDRATE_SCRIPT"
grep -q "git submodule update --init --checkout --no-recommend-shallow ${REF_PATH}" "$HYDRATE_SCRIPT" \
    || abort "Failed to insert init line for ${REF_PATH} into ${HYDRATE_SCRIPT}"

# C) REFS array — append new ref (handle empty and non-empty arrays)
if grep -q '^REFS=()' "$HYDRATE_SCRIPT"; then
    sedi "s|^REFS=()$|REFS=(\"${REF_PATH}\")|" "$HYDRATE_SCRIPT"
else
    sedi "s|^REFS=(\(.*\))$|REFS=(\1 \"${REF_PATH}\")|" "$HYDRATE_SCRIPT"
fi

# D) Pinning block — insert before "info "Verifying SHAs..."
TMP_BLOCK=$(mktemp)
cat > "$TMP_BLOCK" << BLOCKEOF
info "Pinning ${REF_PATH}..."
echo "  Repository : ${REPO_URL}"
echo "  Pinned SHA : \$${PIN_VAR}"
echo "  Commit msg : \$(git -C ${REF_PATH} log -1 --pretty='%s' "\$${PIN_VAR}")"
git -C ${REF_PATH} checkout "\$${PIN_VAR}"
BLOCKEOF
awk -v blockfile="$TMP_BLOCK" '
    /^info "Verifying SHAs/ { while ((getline line < blockfile) > 0) print line; print "" }
    { print }
' "$HYDRATE_SCRIPT" | safe_mv "$HYDRATE_SCRIPT"
rm "$TMP_BLOCK"

# E) verify_sha line — insert after last verify_sha call, or after the verify info message
awk -v ref="$REF_NAME" -v refpath="$REF_PATH" -v pinvar="$PIN_VAR" '
    /^verify_sha / { last=NR }
    /^info "Verifying SHAs/ && !last { last=NR }
    { lines[NR]=$0 }
    END { for (i=1; i<=NR; i++) { print lines[i]; if (i==last) print "verify_sha \"" ref "\" \"" refpath "\" \"$" pinvar "\"" } }
' "$HYDRATE_SCRIPT" | safe_mv "$HYDRATE_SCRIPT"

git add "$HYDRATE_SCRIPT"
ok "${HYDRATE_SCRIPT} updated."

# --- Step 5: Update README.md ---
info "Updating README.md..."
ORG_REPO=$(echo "$REPO_URL" | sed 's|https://github.com/||')

# Pinned SHAs table: append new row after the last audit-refs row, or after the table header
TICK='`'
TABLE_ROW="| ${TICK}${REF_PATH}${TICK} | ${ORG_REPO} | ${TICK}${PIN_SHA:0:8}${TICK} |"
awk -v row="$TABLE_ROW" '
    /^\| `audit-refs\// { last=NR }
    /^\|---\|---\|---\|/ && !last { last=NR }
    { lines[NR]=$0 }
    END { for (i=1; i<=NR; i++) { print lines[i]; if (i==last) print row } }
' README.md | safe_mv README.md
git add README.md
ok "README.md updated."

# --- Step 6: Update CHANGELOG.md ---
info "Updating CHANGELOG.md..."
COMMIT_MSG=$(git -C "$REF_PATH" log -1 --pretty='%s' "$PIN_SHA")
prepend_changelog "## [Added] — $(date +%Y-%m-%d)

### ${REF_PATH}
- **Repository:** ${REPO_URL}
- **Pinned SHA:** \`${PIN_SHA}\`
- **Commit message:** \`${COMMIT_MSG}\`
- **Review notes:** ${REVIEW_NOTES}

---
"

# --- Step 7: Final verification ---
info "Running final verification..."
VERIFIED=true
STAGED=$(git ls-files --stage "$REF_PATH" | awk '{print $2}')
[ "$STAGED" = "$PIN_SHA" ] && ok "Index SHA correct." || { warn "Index SHA mismatch!"; VERIFIED=false; }
grep -q "^${PIN_VAR}=\"${PIN_SHA}\"" "$HYDRATE_SCRIPT" && ok "PIN variable correct." || { warn "PIN variable missing!"; VERIFIED=false; }
grep -q "$PIN_SHA" CHANGELOG.md && ok "CHANGELOG entry present." || { warn "CHANGELOG missing entry!"; VERIFIED=false; }
[ "$VERIFIED" = false ] && abort "Verification failed."

show_staged_diff "audit-refs: add ${REF_NAME} at ${PIN_SHA:0:8} (reviewed: $(date +%Y-%m-%d))"
ok "Addition complete. Commit when satisfied with the diff above."

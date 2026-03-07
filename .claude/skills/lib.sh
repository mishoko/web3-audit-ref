#!/usr/bin/env bash
# lib.sh — Shared functions for audit-ref scripts
# ---------------------------------------------------------------------------
# Source this at the top of every skill script:
#   source "$(dirname "$0")/../lib.sh"
# ---------------------------------------------------------------------------

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

HYDRATE_SCRIPT=".claude/skills/hydrate-pins/hydrate_pins.sh"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
info()  { printf '\n\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
abort() { printf '\033[1;31m[ABORT]\033[0m %s\n' "$*" >&2; exit 1; }

# Portable sed in-place that preserves file permissions
sedi() {
    local perms file
    # Last argument is the file
    for file; do :; done
    perms=$(stat -f '%A' "$file" 2>/dev/null || stat -c '%a' "$file" 2>/dev/null)
    if [[ "$OSTYPE" == darwin* ]]; then sed -i '' "$@"; else sed -i "$@"; fi
    chmod "$perms" "$file"
}

# ---------------------------------------------------------------------------
# Ref name helpers
# ---------------------------------------------------------------------------
# Validate ref name: lowercase alphanumeric, hyphens, underscores only
validate_ref_name() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9_-]*$ ]] \
        || abort "Invalid ref name '$1'. Use only lowercase alphanumeric, hyphens, and underscores (e.g., 'cyfrin-solskill')."
}

# Convert ref-name to PIN variable name: tob-skills → PIN_TOB_SKILLS
# Sanitizes all non-alphanumeric chars to underscores
ref_to_pin_var() { echo "PIN_$(echo "$1" | tr '[:lower:]' '[:upper:]' | tr -c '[:alnum:]\n' '_')"; }

# Read the current PIN SHA from hydrate_pins.sh
read_pin_sha() {
    local pin_var="$1"
    grep "^${pin_var}=" "$HYDRATE_SCRIPT" | cut -d'"' -f2
}

# Verify the PIN variable exists in hydrate_pins.sh
require_managed_ref() {
    local ref_name="$1"
    local pin_var
    pin_var=$(ref_to_pin_var "$ref_name")
    if ! grep -q "^${pin_var}=" "$HYDRATE_SCRIPT"; then
        abort "'${pin_var}' not found in ${HYDRATE_SCRIPT}. Is '${ref_name}' a managed ref?"
    fi
}

# ---------------------------------------------------------------------------
# SHA verification
# ---------------------------------------------------------------------------
# Checkout a SHA in a submodule and verify HEAD matches
checkout_and_verify() {
    local ref_path="$1"
    local target_sha="$2"
    # Resolve short SHAs to full 40-char form before comparing
    target_sha=$(git -C "$ref_path" rev-parse "$target_sha" 2>/dev/null) \
        || abort "Could not resolve SHA '$2' in $ref_path"
    git -C "$ref_path" checkout "$target_sha"
    local actual_sha
    actual_sha=$(git -C "$ref_path" rev-parse HEAD)
    if [ "$actual_sha" != "$target_sha" ]; then
        abort "SHA mismatch after checkout!
  Expected: $target_sha
  Got:      $actual_sha"
    fi
    ok "Pinned to $target_sha."
}

# Stage a submodule pointer and verify the staged SHA matches
stage_and_verify() {
    local ref_path="$1"
    local expected_sha="$2"
    # Resolve short SHAs to full 40-char form before comparing
    expected_sha=$(git -C "$ref_path" rev-parse "$expected_sha" 2>/dev/null) \
        || abort "Could not resolve SHA '$2' in $ref_path"
    git add "$ref_path"
    local staged_sha
    staged_sha=$(git ls-files --stage "$ref_path" | awk '{print $2}')
    if [ "$staged_sha" != "$expected_sha" ]; then
        abort "Staged SHA mismatch!
  Expected: $expected_sha
  Got:      $staged_sha"
    fi
    ok "Submodule pointer staged at correct SHA."
}

verify_sha() {
    local name="$1"
    local path="$2"
    local expected="$3"
    local actual
    actual=$(git -C "$path" rev-parse HEAD)
    if [ "$actual" = "$expected" ]; then
        ok "$name is pinned to $expected"
    else
        abort "$name SHA mismatch!
  Expected: $expected
  Got:      $actual
  This submodule is NOT at the audited commit. Aborting."
    fi
}

# ---------------------------------------------------------------------------
# Safe file replacement (preserves permissions across mktemp+mv)
# ---------------------------------------------------------------------------
# Usage: generate_content | safe_mv target_file
safe_mv() {
    local target="$1"
    local tmp
    tmp=$(mktemp)
    cat > "$tmp"
    chmod --reference="$target" "$tmp" 2>/dev/null \
        || chmod "$(stat -f '%A' "$target")" "$tmp"
    mv "$tmp" "$target"
}

# ---------------------------------------------------------------------------
# CHANGELOG helpers
# ---------------------------------------------------------------------------
# Prepend an entry to CHANGELOG.md (before the first ## [...] line)
prepend_changelog() {
    local entry="$1"
    local tmp
    tmp=$(mktemp)
    {
        awk '/^## \[/{exit} {print}' CHANGELOG.md
        printf '%s\n' "$entry"
        awk '/^## \[/{found=1} found{print}' CHANGELOG.md
    } > "$tmp" && mv "$tmp" CHANGELOG.md
    git add CHANGELOG.md
    ok "CHANGELOG.md updated."
}

# ---------------------------------------------------------------------------
# Safe temporary clone (for pre-add scanning)
# ---------------------------------------------------------------------------
# Clones a remote repo into a temp directory with all hooks disabled.
# Returns the temp directory path. Caller must clean up.
# Usage: tmpdir=$(safe_clone_to_temp <repo-url> [<sha>])
safe_clone_to_temp() {
    local repo_url="$1"
    local sha="${2:-}"
    local tmpdir
    tmpdir=$(mktemp -d)

    info "Safe-cloning ${repo_url} into temp directory..." >&2
    echo "  Hooks disabled: GIT_TEMPLATE_DIR='', core.hooksPath=/dev/null" >&2

    GIT_TEMPLATE_DIR="" git clone \
        --no-checkout \
        --depth 1 \
        ${sha:+--no-single-branch} \
        -c core.hooksPath=/dev/null \
        -c core.fsmonitor=false \
        -c core.symlinks=false \
        "$repo_url" "$tmpdir/repo" >&2 || {
        rm -rf "$tmpdir"
        abort "Failed to clone ${repo_url}"
    }

    # Checkout files with hooks disabled
    GIT_TEMPLATE_DIR="" git -C "$tmpdir/repo" \
        -c core.hooksPath=/dev/null \
        checkout ${sha:-HEAD} -- . >&2 || {
        rm -rf "$tmpdir"
        abort "Failed to checkout ${sha:-HEAD}"
    }

    local file_count
    file_count=$(find "$tmpdir/repo" -type f -not -path '*/.git/*' | wc -l | tr -d ' ')
    ok "Safe clone complete (${file_count} files)." >&2
    # Only the path goes to stdout (for capture)
    echo "$tmpdir"
}

# ---------------------------------------------------------------------------
# Final diff + commit suggestion
# ---------------------------------------------------------------------------
show_staged_diff() {
    local commit_msg="$1"
    echo ""
    info "Staged diff (review before committing):"
    git diff --cached
    echo ""
    warn "Changes are staged but NOT committed."
    echo "When ready, commit with:"
    echo ""
    echo "  ALLOW_SUBMODULE_UPDATE=1 git commit -m \"${commit_msg}\""
    echo ""
}

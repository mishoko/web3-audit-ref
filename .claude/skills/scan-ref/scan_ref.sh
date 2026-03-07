#!/usr/bin/env bash
# scan_ref.sh
# ---------------------------------------------------------------------------
# Security pre-flight scanner for audit references.
# Detects supply-chain threats: install hooks, encoded payloads, suspicious
# scripts, git hooks, symlinks, and other dangerous patterns.
#
# USAGE:
#   ./scan_ref.sh <ref-name>                        # full scan
#   ./scan_ref.sh <ref-name> <old-sha> <new-sha>    # diff scan
#
# EXAMPLES:
#   ./scan_ref.sh tob-skills
#   ./scan_ref.sh tob-skills abc123 def456
#
# This script is READ-ONLY. It never modifies files or executes anything
# inside audit-refs/.
# ---------------------------------------------------------------------------

source "$(dirname "$0")/../lib.sh"

# Severity-specific helpers (supplement the shared info/ok/warn/abort)
critical() { printf '\033[1;31m[CRITICAL]\033[0m %s\n' "$*"; }
high()     { printf '\033[1;35m[HIGH]\033[0m     %s\n' "$*"; }
medium()   { printf '\033[1;33m[MEDIUM]\033[0m   %s\n' "$*"; }
finding()  { printf '\033[0;36m[INFO]\033[0m     %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <ref-name> [<old-sha> <new-sha>]"
    echo "       $0 <ref-name> --url <repo-url> [<sha>]"
    echo ""
    echo "Examples:"
    echo "  $0 tob-skills                                # full scan (local)"
    echo "  $0 tob-skills abc123 def456                  # diff scan (changes only)"
    echo "  $0 skills --url https://github.com/x/skills  # scan remote before adding"
    echo ""
    echo "Available refs:"
    ls audit-refs/ 2>/dev/null || echo "  (none — run hydrate_pins.sh first)"
    exit 1
fi

REF_NAME="$1"
validate_ref_name "$REF_NAME"
REF_PATH="audit-refs/${REF_NAME}"
OLD_SHA=""
NEW_SHA=""
REPO_URL=""
REMOTE_SHA=""
DIFF_MODE=false
REMOTE_MODE=false
TEMP_CLONE_DIR=""

# Parse arguments
shift
while [ $# -gt 0 ]; do
    case "$1" in
        --url)
            REPO_URL="${2:-}"
            [ -z "$REPO_URL" ] && abort "--url requires a repository URL"
            REMOTE_MODE=true
            shift 2
            # Optional SHA after URL
            if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
                REMOTE_SHA="$1"
                shift
            fi
            ;;
        *)
            if [ -z "$OLD_SHA" ]; then
                OLD_SHA="$1"
            elif [ -z "$NEW_SHA" ]; then
                NEW_SHA="$1"
            fi
            shift
            ;;
    esac
done

if [ -n "$OLD_SHA" ] && [ -n "$NEW_SHA" ]; then
    DIFF_MODE=true
fi

# Remote mode: safe-clone to temp, scan, clean up
if [ "$REMOTE_MODE" = true ]; then
    TEMP_CLONE_DIR=$(safe_clone_to_temp "$REPO_URL" "$REMOTE_SHA")
    REF_PATH="$TEMP_CLONE_DIR/repo"
    trap 'rm -rf "$TEMP_CLONE_DIR"' EXIT
elif [ ! -d "$REF_PATH" ]; then
    echo "Error: '$REF_PATH' does not exist."
    echo "  To scan a remote repo before adding, use: $0 $REF_NAME --url <repo-url>"
    exit 1
fi

# Counters
CRIT_COUNT=0
HIGH_COUNT=0
MED_COUNT=0
INFO_COUNT=0

# ---------------------------------------------------------------------------
# Build file list (full scan vs diff scan)
# ---------------------------------------------------------------------------
SCAN_FILES=$(mktemp)
cleanup() { rm -f "$SCAN_FILES"; [ -n "${TEMP_CLONE_DIR:-}" ] && rm -rf "$TEMP_CLONE_DIR"; }
trap cleanup EXIT

if [ "$DIFF_MODE" = true ]; then
    info "Diff scan: ${REF_NAME} (${OLD_SHA:0:8} -> ${NEW_SHA:0:8})"
    while read -r f; do
        echo "${REF_PATH}/${f}"
    done < <(git -C "$REF_PATH" diff --name-only "$OLD_SHA" "$NEW_SHA" 2>/dev/null) > "$SCAN_FILES"
    FILE_COUNT=$(wc -l < "$SCAN_FILES" | tr -d ' ')
    echo "  Files changed: $FILE_COUNT"
else
    info "Full scan: ${REF_PATH}"
    find "$REF_PATH" -type f -not -path '*/.git/*' > "$SCAN_FILES"
    FILE_COUNT=$(wc -l < "$SCAN_FILES" | tr -d ' ')
    echo "  Files to scan: $FILE_COUNT"
fi

if [ "$FILE_COUNT" -eq 0 ]; then
    ok "No files to scan."
    exit 0
fi

# ---------------------------------------------------------------------------
# Check: Package.json install hooks
# ---------------------------------------------------------------------------
info "Checking for package.json install hooks..."
FOUND=false
while IFS= read -r f; do
    case "$f" in
        */package.json)
            if [ -f "$f" ]; then
                for hook in preinstall postinstall prepare preuninstall postuninstall; do
                    if grep -q "\"${hook}\"" "$f" 2>/dev/null; then
                        critical "Install hook '${hook}' found in $f"
                        CRIT_COUNT=$((CRIT_COUNT + 1))
                        FOUND=true
                    fi
                done
            fi
            ;;
    esac
done < "$SCAN_FILES"
[ "$FOUND" = false ] && ok "No package.json install hooks."

# ---------------------------------------------------------------------------
# Check: Python install hooks
# ---------------------------------------------------------------------------
info "Checking for Python install hooks..."
FOUND=false
while IFS= read -r f; do
    case "$f" in
        */setup.py|*/setup.cfg|*/pyproject.toml)
            if [ -f "$f" ]; then
                if grep -qE "(cmdclass|custom_command|install_requires.*subprocess|build_ext)" "$f" 2>/dev/null; then
                    critical "Potential custom install command in $f"
                    CRIT_COUNT=$((CRIT_COUNT + 1))
                    FOUND=true
                fi
            fi
            ;;
    esac
done < "$SCAN_FILES"
[ "$FOUND" = false ] && ok "No Python install hooks."

# ---------------------------------------------------------------------------
# Check: Shell pipe execution (curl|bash, wget|sh, etc.)
# ---------------------------------------------------------------------------
info "Checking for shell pipe execution patterns..."
FOUND=false
while IFS= read -r f; do
    if [ -f "$f" ]; then
        if grep -nE '(curl|wget)\s.*\|\s*(ba)?sh' "$f" 2>/dev/null; then
            critical "Shell pipe execution in $f"
            CRIT_COUNT=$((CRIT_COUNT + 1))
            FOUND=true
        fi
    fi
done < "$SCAN_FILES"
[ "$FOUND" = false ] && ok "No shell pipe execution patterns."

# ---------------------------------------------------------------------------
# Check: Encoded payloads (base64, hex)
# ---------------------------------------------------------------------------
info "Checking for encoded payloads..."
FOUND=false
while IFS= read -r f; do
    if [ -f "$f" ]; then
        if grep -nE '(base64\s+(--)?decode|base64\s+-d|xxd\s+-r|printf.*\\x[0-9a-fA-F]{2}.*\\x[0-9a-fA-F]{2}.*\\x[0-9a-fA-F]{2})' "$f" 2>/dev/null; then
            critical "Encoded payload pattern in $f"
            CRIT_COUNT=$((CRIT_COUNT + 1))
            FOUND=true
        fi
    fi
done < "$SCAN_FILES"
[ "$FOUND" = false ] && ok "No encoded payload patterns."

# ---------------------------------------------------------------------------
# Check: Git hooks
# ---------------------------------------------------------------------------
info "Checking for git hooks..."
FOUND=false
while IFS= read -r f; do
    case "$f" in
        */.git/hooks/*|*/.husky/*|*/.githooks/*|*/.lefthook/*)
            if [ -f "$f" ]; then
                high "Git hook found: $f"
                HIGH_COUNT=$((HIGH_COUNT + 1))
                FOUND=true
            fi
            ;;
    esac
done < "$SCAN_FILES"
[ "$FOUND" = false ] && ok "No git hooks."

# ---------------------------------------------------------------------------
# Check: Makefiles and task runners
# ---------------------------------------------------------------------------
info "Checking for Makefiles and task runners..."
FOUND=false
while IFS= read -r f; do
    case "$(basename "$f")" in
        Makefile|makefile|GNUmakefile|Justfile|Taskfile|Taskfile.yml|Rakefile)
            if [ -f "$f" ]; then
                medium "Task runner found: $f"
                MED_COUNT=$((MED_COUNT + 1))
                FOUND=true
                # Check for suspicious targets
                if grep -nE '(curl|wget|rm\s+-rf|chmod|eval|exec|sudo)' "$f" 2>/dev/null; then
                    high "Suspicious commands in task runner: $f"
                    HIGH_COUNT=$((HIGH_COUNT + 1))
                fi
            fi
            ;;
    esac
done < "$SCAN_FILES"
[ "$FOUND" = false ] && ok "No task runners."

# ---------------------------------------------------------------------------
# Check: CI/CD with dangerous triggers
# ---------------------------------------------------------------------------
info "Checking for CI/CD with dangerous triggers..."
FOUND=false
while IFS= read -r f; do
    case "$f" in
        */.github/workflows/*)
            if [ -f "$f" ]; then
                if grep -qE '(pull_request_target|self-hosted|runs-on:.*self)' "$f" 2>/dev/null; then
                    medium "Dangerous CI trigger in $f"
                    MED_COUNT=$((MED_COUNT + 1))
                    FOUND=true
                fi
            fi
            ;;
    esac
done < "$SCAN_FILES"
[ "$FOUND" = false ] && ok "No dangerous CI triggers."

# ---------------------------------------------------------------------------
# Check: Symlinks pointing outside the repo
# ---------------------------------------------------------------------------
info "Checking for suspicious symlinks..."
FOUND=false
while IFS= read -r f; do
    if [ -L "$f" ]; then
        TARGET=$(readlink "$f")
        case "$TARGET" in
            /*|../*/../*|*/../../../*)
                high "Symlink escapes repo: $f -> $TARGET"
                HIGH_COUNT=$((HIGH_COUNT + 1))
                FOUND=true
                ;;
        esac
    fi
done < "$SCAN_FILES"
# Also scan for symlinks via find (catches things the file list might miss in full mode)
if [ "$DIFF_MODE" = false ]; then
    while IFS= read -r f; do
        TARGET=$(readlink "$f")
        case "$TARGET" in
            /*)
                high "Absolute symlink: $f -> $TARGET"
                HIGH_COUNT=$((HIGH_COUNT + 1))
                FOUND=true
                ;;
        esac
    done < <(find "$REF_PATH" -type l -not -path '*/.git/*' 2>/dev/null)
fi
[ "$FOUND" = false ] && ok "No suspicious symlinks."

# ---------------------------------------------------------------------------
# Check: Hidden executables
# ---------------------------------------------------------------------------
info "Checking for hidden executables..."
FOUND=false
if [ "$DIFF_MODE" = false ]; then
    while IFS= read -r f; do
        if [ -x "$f" ] && [ -f "$f" ]; then
            medium "Hidden executable: $f"
            MED_COUNT=$((MED_COUNT + 1))
            FOUND=true
        fi
    done < <(find "$REF_PATH" -name '.*' -type f \( -perm -u=x -o -perm -g=x -o -perm -o=x \) -not -path '*/.git/*' 2>/dev/null)
fi
[ "$FOUND" = false ] && ok "No hidden executables."

# ---------------------------------------------------------------------------
# Check: eval/exec patterns in scripts
# ---------------------------------------------------------------------------
info "Checking for eval/exec patterns..."
FOUND=false
while IFS= read -r f; do
    if [ -f "$f" ]; then
        case "$f" in
            *.js|*.ts|*.py|*.rb|*.sh|*.bash|*.pl)
                if grep -nE '(\beval\s*\(|child_process|subprocess\.call.*shell\s*=\s*True|subprocess\.Popen.*shell\s*=\s*True|\bexec\s*\()' "$f" 2>/dev/null; then
                    medium "eval/exec pattern in $f"
                    MED_COUNT=$((MED_COUNT + 1))
                    FOUND=true
                fi
                ;;
        esac
    fi
done < "$SCAN_FILES"
[ "$FOUND" = false ] && ok "No eval/exec patterns in scripts."

# ---------------------------------------------------------------------------
# Check: Executable shell scripts (informational)
# ---------------------------------------------------------------------------
info "Checking for executable scripts..."
EXEC_COUNT=0
if [ "$DIFF_MODE" = false ]; then
    while IFS= read -r f; do
        EXEC_COUNT=$((EXEC_COUNT + 1))
        finding "Executable: $f"
    done < <(find "$REF_PATH" -type f \( -perm -u=x -o -perm -g=x -o -perm -o=x \) -not -path '*/.git/*' 2>/dev/null)
fi
if [ "$EXEC_COUNT" -gt 0 ]; then
    INFO_COUNT=$((INFO_COUNT + EXEC_COUNT))
    finding "$EXEC_COUNT executable file(s) found (review before running any)."
else
    ok "No executable files."
fi

# ---------------------------------------------------------------------------
# Check: LLM instruction files (prompt injection surface)
# ---------------------------------------------------------------------------
info "Checking for LLM instruction/config files..."
FOUND=false
while IFS= read -r f; do
    case "$(basename "$f")" in
        CLAUDE.md|AGENTS.md|.cursorrules|.clinerules|.windsurfrules|CONVENTIONS.md|copilot-instructions.md)
            high "LLM instruction file: $f"
            HIGH_COUNT=$((HIGH_COUNT + 1))
            FOUND=true
            # Dump contents so they survive temp-dir cleanup and can be reviewed
            echo "  ┌── contents of $(basename "$f") ──"
            sed 's/^/  │ /' "$f"
            echo "  └── end of $(basename "$f") ──"
            ;;
    esac
done < "$SCAN_FILES"
# Check for LLM config directories
for d in ".claude" ".cursor" ".copilot"; do
    if [ -d "${REF_PATH}/${d}" ]; then
        high "LLM config directory: ${REF_PATH}/${d}"
        HIGH_COUNT=$((HIGH_COUNT + 1))
        FOUND=true
        # Dump contents of all files in the LLM config directory
        while IFS= read -r llm_file; do
            rel_path="${llm_file#${REF_PATH}/}"
            echo "  ┌── contents of ${rel_path} ──"
            sed 's/^/  │ /' "$llm_file"
            echo "  └── end of ${rel_path} ──"
        done < <(find "${REF_PATH}/${d}" -type f -not -path '*/.git/*' 2>/dev/null | sort)
    fi
done
[ "$FOUND" = false ] && ok "No LLM instruction files."

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo "  SCAN SUMMARY: ${REF_NAME}"
echo "============================================"
echo ""
printf "  \033[1;31mCRITICAL : %d\033[0m\n" "$CRIT_COUNT"
printf "  \033[1;35mHIGH     : %d\033[0m\n" "$HIGH_COUNT"
printf "  \033[1;33mMEDIUM   : %d\033[0m\n" "$MED_COUNT"
printf "  \033[0;36mINFO     : %d\033[0m\n" "$INFO_COUNT"
echo ""

if [ "$CRIT_COUNT" -gt 0 ]; then
    critical "CRITICAL findings detected. Do NOT pin this ref without thorough manual review."
    exit 2
elif [ "$HIGH_COUNT" -gt 0 ]; then
    warn "HIGH findings detected. Review carefully before pinning."
    exit 1
else
    ok "No critical or high-severity findings. Ref appears safe to pin."
    exit 0
fi

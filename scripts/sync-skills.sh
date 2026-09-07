#!/usr/bin/env bash
# Refresh the vendored agent skills in skills/ from their source repos.
#
# The copies here are exactly that — copies. Each skill's source of truth lives
# in the repo that owns it. Edit the skill there, then run this to propagate.
# Never edit skills/<name>/ directly: the next sync overwrites it, and a CI job
# in each source repo fails while the two differ.
#
# Usage:
#   ./scripts/sync-skills.sh            copy sources over skills/
#   ./scripts/sync-skills.sh --check    report drift, write nothing (exit 1 if any)
#
# Override the source locations if your checkouts live elsewhere:
#   PRELUDE_CLAUDE=/path/to/prelude-claude PRELUDE_MCP=/path/to/prelude-mcp ./scripts/sync-skills.sh
set -euo pipefail

check_only=false
case "${1:-}" in
    --check) check_only=true ;;
    "") ;;
    *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prelude_claude="${PRELUDE_CLAUDE:-$repo_root/../prelude-claude}"
prelude_mcp="${PRELUDE_MCP:-$repo_root/../prelude-mcp}"

# skill name -> source directory
sync_one() {
    local name="$1" source_dir="$2"
    local dest="$repo_root/skills/$name"

    if [[ ! -d "$source_dir" ]]; then
        echo "error: source for '$name' not found at $source_dir" >&2
        echo "       set PRELUDE_CLAUDE / PRELUDE_MCP to your checkout locations" >&2
        return 1
    fi
    if [[ ! -f "$source_dir/SKILL.md" ]]; then
        echo "error: $source_dir has no SKILL.md — wrong directory?" >&2
        return 1
    fi

    if [[ "$check_only" == true ]]; then
        local drift
        drift="$(rsync -a --delete --dry-run --itemize-changes \
            --exclude '.DS_Store' "$source_dir/" "$dest/" | grep -v '^\.d\.\.t' || true)"
        if [[ -n "$drift" ]]; then
            echo "drift  skills/$name  <-  $source_dir"
            echo "$drift" | sed 's/^/         /'
            return 1
        fi
        echo "in sync  skills/$name"
        return 0
    fi

    mkdir -p "$dest"
    rsync -a --delete --exclude '.DS_Store' "$source_dir/" "$dest/"
    echo "synced skills/$name  <-  $source_dir"
}

status=0
sync_one prelude-collector-api "$prelude_claude/skills/prelude-collector-api" || status=1
sync_one prelude-mcp-companion "$prelude_mcp/skills/prelude-mcp-companion" || status=1

if [[ $status -ne 0 ]]; then
    exit $status
fi

if [[ "$check_only" == true ]]; then
    exit 0
fi

if command -v git >/dev/null && git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
    if git -C "$repo_root" diff --quiet -- skills && git -C "$repo_root" diff --quiet --cached -- skills; then
        echo "skills/ already up to date"
    else
        echo
        echo "skills/ changed — review and commit:"
        git -C "$repo_root" --no-pager diff --stat -- skills
    fi
fi

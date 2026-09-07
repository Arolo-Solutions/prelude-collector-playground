#!/usr/bin/env bash
# Publish this repo to its public GitHub mirror.
#
# Authoring happens on GitLab (origin). GitHub is the only surface a customer
# can read — including the Playground link the collector renders on every
# vendor-profile row — so publishing is a deliberate act with gates, not a
# background sync. Every gate here exists because skipping it has a cost:
# content that is wrong, stale, or internal becomes public the moment it lands.
#
# Usage:
#   ./scripts/publish.sh --check-only        run the gates, touch nothing
#   ./scripts/publish.sh --dry-run v1.1.2    full rehearsal, no writes
#   ./scripts/publish.sh v1.1.2              tag, push both remotes, cut a Release
#   ./scripts/publish.sh                     push main to both remotes, no tag
#
# Options:
#   --check-only   run every gate, then stop; nothing is tagged, pushed or released
#   --dry-run      run everything and print the actions instead of doing them
#   --yes          skip the confirmation prompt
#   --no-release   tag and push, but do not create the GitHub Release
#
# Credentials, in order of preference:
#   1. GITHUB_TOKEN in the environment. Used for both the push and the Release,
#      never written to git config or the command line. This is the CI path: a
#      masked, protected GitLab CI variable holding a fine-grained PAT scoped to
#      this one repo with Contents: read/write.
#   2. Otherwise the laptop's own credentials — gh's git credential helper for
#      the push, gh's stored token for the Release. Nothing to configure if
#      `gh auth login` and `gh auth setup-git` have been run.
#
# Environment overrides:
#   GITHUB_REPO      default Arolo-Solutions/prelude-collector-playground
#   GITHUB_REMOTE    default github
#   PUBLISH_BRANCH   default main
#   GITHUB_TOKEN     optional; see above
#   PRELUDE_CLAUDE / PRELUDE_MCP   skill sources, for the sync gate
set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-Arolo-Solutions/prelude-collector-playground}"
GITHUB_REMOTE="${GITHUB_REMOTE:-github}"
GITHUB_URL="https://github.com/${GITHUB_REPO}.git"
PUBLISH_BRANCH="${PUBLISH_BRANCH:-main}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# ---------------------------------------------------------------- arguments

version=""
dry_run=false
check_only=false
assume_yes=false
want_release=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)     dry_run=true ;;
        --check-only)  check_only=true ;;
        --yes|-y)      assume_yes=true ;;
        --no-release)  want_release=false ;;
        -h|--help)     sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
        v[0-9]*)       version="$1" ;;
        *)             echo "unknown argument: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

if [[ -n "$version" && ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version must look like vX.Y.Z, got '$version'" >&2
    exit 2
fi

# ------------------------------------------------------------------ output

if [[ -t 1 ]]; then
    C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_BAD=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
    C_OK=""; C_WARN=""; C_BAD=""; C_DIM=""; C_OFF=""
fi

fails=0
warns=0
ok()   { printf '  %s✓%s %s\n'  "$C_OK"   "$C_OFF" "$1"; }
warn() { printf '  %s!%s %s\n'  "$C_WARN" "$C_OFF" "$1"; warns=$((warns + 1)); }
bad()  { printf '  %s✗%s %s\n'  "$C_BAD"  "$C_OFF" "$1"; fails=$((fails + 1)); }
note() { printf '    %s%s%s\n'  "$C_DIM"  "$1"     "$C_OFF"; }
head2(){ printf '\n%s\n' "$1"; }

abort() { printf '\n%serror:%s %s\n' "$C_BAD" "$C_OFF" "$1" >&2; exit 1; }

# ----------------------------------------------------------- leak patterns

# Must never reach the public repo. A hit here blocks the publish.
BLOCKING_PATTERNS=(
    'arolo\.net'
    'arolo123'
    'prelude-collector\.test'
    '172\.31\.[0-9]'
    '-----BEGIN [A-Z ]*PRIVATE KEY'
    'gh[pousr]_[A-Za-z0-9]{30,}'
    'xox[baprs]-[A-Za-z0-9-]{10,}'
    'AKIA[0-9A-Z]{16}'
)

# Legitimate in documentation (example configs, prose about login prompts).
# Reported so a human can glance, never blocking.
ADVISORY_PATTERNS=(
    'password'
    '10\.0\.0\.'
    '192\.168\.'
)

# Consciously accepted blocking hits, as "<path>|<substring on the line>".
# Every entry needs a reason. Fix the source before adding a line here.
ALLOWLIST=(
    # GoTTP's canonical Go module path. Not publicly resolvable, but it is the
    # path a reader sees in Go build errors, so the docs are right to name it.
    # Any fix belongs upstream in prelude-claude / prelude-mcp, not in the
    # vendored copy under skills/.
    'skills/prelude-collector-api/references/gottp-templates.md|git.arolo.net/arolo/gottp'
    'skills/prelude-mcp-companion/references/gottp-templates.md|git.arolo.net/arolo/gottp'
)

allowlisted() {
    local hit="$1" path="${1%%:*}" entry
    for entry in "${ALLOWLIST[@]}"; do
        [[ "$path" == "${entry%%|*}" ]] || continue
        [[ "$hit" == *"${entry#*|}"* ]] && return 0
    done
    return 1
}

# ------------------------------------------------------------ preflight

head2 "Preflight"

git rev-parse --git-dir >/dev/null 2>&1 || abort "not a git repository: $repo_root"

if git remote get-url "$GITHUB_REMOTE" >/dev/null 2>&1; then
    actual="$(git remote get-url "$GITHUB_REMOTE")"
    if [[ "$actual" == "$GITHUB_URL" || "$actual" == "${GITHUB_URL%.git}" ]]; then
        ok "remote '$GITHUB_REMOTE' -> $GITHUB_REPO"
    else
        abort "remote '$GITHUB_REMOTE' points at $actual, expected $GITHUB_URL"
    fi
else
    # Local config only — nothing leaves the machine, and the fast-forward gate
    # below needs this remote to have anything to compare against.
    git remote add "$GITHUB_REMOTE" "$GITHUB_URL"
    ok "added remote '$GITHUB_REMOTE' -> $GITHUB_REPO"
fi

# gh reads GH_TOKEN/GITHUB_TOKEN from the environment on its own, so a CI job
# needs no `gh auth login`.
TOKEN_HELPER='!f() { echo username=oauth2; echo "password=$GITHUB_TOKEN"; }; f'
git_github() {
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        git -c credential.helper="$TOKEN_HELPER" "$@"
    else
        git "$@"
    fi
}

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    ok "credentials: GITHUB_TOKEN from the environment"
elif command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    ok "credentials: gh ($(gh api user --jq .login 2>/dev/null || echo 'authenticated'))"
else
    bad "no credentials — set GITHUB_TOKEN, or run: gh auth login && gh auth setup-git"
fi

if [[ "$want_release" == true && -n "$version" ]] && ! command -v gh >/dev/null; then
    bad "gh not installed — needed to create the Release (or pass --no-release)"
fi

# ---------------------------------------------------------- repo state

head2 "Repository state"

branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$branch" == "$PUBLISH_BRANCH" ]]; then
    ok "on $PUBLISH_BRANCH"
else
    bad "on '$branch', expected '$PUBLISH_BRANCH' — publish only from the release branch"
fi

dirty="$(git status --porcelain --untracked-files=no)"
if [[ -z "$dirty" ]]; then
    ok "working tree clean"
else
    bad "working tree has uncommitted changes"
    note "$(echo "$dirty" | head -5 | tr '\n' ' ')"
fi

untracked="$(git ls-files --others --exclude-standard)"
if [[ -n "$untracked" ]]; then
    warn "untracked files will NOT be published:"
    echo "$untracked" | sed 's/^/      /'
fi

if git fetch --quiet --tags origin 2>/dev/null; then
    ok "fetched origin (GitLab)"
else
    warn "could not fetch origin — is git.arolo.net reachable?"
fi

if git remote get-url "$GITHUB_REMOTE" >/dev/null 2>&1; then
    if git_github fetch --quiet --tags "$GITHUB_REMOTE" 2>/dev/null; then
        ok "fetched $GITHUB_REMOTE"
    else
        warn "could not fetch $GITHUB_REMOTE"
    fi
fi

head="$(git rev-parse HEAD)"

# GitLab is the source of truth: never publish something it has not accepted.
if gitlab_ref="$(git rev-parse --verify --quiet "refs/remotes/origin/$PUBLISH_BRANCH")"; then
    if [[ "$gitlab_ref" == "$head" ]]; then
        ok "origin/$PUBLISH_BRANCH matches HEAD"
    elif git merge-base --is-ancestor "$gitlab_ref" "$head"; then
        bad "HEAD is ahead of origin/$PUBLISH_BRANCH by $(git rev-list --count "$gitlab_ref..$head") commit(s)"
        note "push to GitLab first: git push origin $PUBLISH_BRANCH"
    else
        bad "HEAD and origin/$PUBLISH_BRANCH have diverged"
    fi
else
    warn "no origin/$PUBLISH_BRANCH to compare against"
fi

# The GitHub push must fast-forward, or history a customer already fetched moves.
if gh_ref="$(git rev-parse --verify --quiet "refs/remotes/$GITHUB_REMOTE/$PUBLISH_BRANCH")"; then
    if [[ "$gh_ref" == "$head" ]]; then
        ok "$GITHUB_REMOTE/$PUBLISH_BRANCH already at HEAD — nothing new to publish"
    elif git merge-base --is-ancestor "$gh_ref" "$head"; then
        ok "fast-forward: $(git rev-list --count "$gh_ref..$head") commit(s) to publish"
        git --no-pager log --oneline --no-decorate "$gh_ref..$head" | sed 's/^/      /'
    else
        bad "$GITHUB_REMOTE/$PUBLISH_BRANCH is not an ancestor of HEAD — pushing would rewrite public history"
        note "GitHub has $(git rev-list --count "$head..$gh_ref") commit(s) HEAD lacks; merge them down first"
        git --no-pager log --oneline --no-decorate "$head..$gh_ref" | sed 's/^/      /'
    fi
else
    warn "no $GITHUB_REMOTE/$PUBLISH_BRANCH yet — this would be the first publish"
fi

# ----------------------------------------------------------- content gates

head2 "Content"

# Every artifact here exists to be imported. Invalid JSON is a dead artifact.
bad_json=""
while IFS= read -r f; do
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null || bad_json+="$f"$'\n'
done < <(git ls-files 'vendors/*.json' 'shared/*.json')
if [[ -z "$bad_json" ]]; then
    ok "$(git ls-files 'vendors/*.json' 'shared/*.json' | wc -l | tr -d ' ') JSON artifacts parse"
else
    bad "invalid JSON:"
    echo "$bad_json" | sed '/^$/d; s/^/      /'
fi

# A renamed repo or org silently breaks the in-app Playground link on every
# vendor-profile row, and nothing in the collector complains.
wrong_url="$(git grep -nE 'https://github\.com/' -- 'vendors/*/profile.json' \
    | grep -vE "https://github\.com/${GITHUB_REPO}/" || true)"
if [[ -z "$wrong_url" ]]; then
    ok "vendor profile playground URLs point at $GITHUB_REPO"
else
    bad "profile.json playground URL does not match $GITHUB_REPO:"
    echo "$wrong_url" | sed 's/^/      /'
fi

# Leak scan. Tracked files only — git grep never sees gitignored or untracked
# content, which is exactly the set that does not get published.
leak_hits=""
# ':(exclude)scripts/publish.sh' — this script defines the patterns above, so it
# is the one file guaranteed to contain them; scanning it is a false positive.
scan_scope=(-- . ':(exclude)scripts/publish.sh')
for pat in "${BLOCKING_PATTERNS[@]}"; do
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        allowlisted "$hit" || leak_hits+="$hit"$'\n'
    done < <(git grep -nIE "$pat" "${scan_scope[@]}" 2>/dev/null || true)
done
leak_hits="$(echo "$leak_hits" | sed '/^$/d' | sort -u)"
if [[ -z "$leak_hits" ]]; then
    ok "leak scan clean (${#ALLOWLIST[@]} allowlisted hit(s) skipped)"
else
    bad "internal references in publishable content:"
    echo "$leak_hits" | sed 's/^/      /'
fi

advisory_count=0
for pat in "${ADVISORY_PATTERNS[@]}"; do
    n="$(git grep -cIE "$pat" "${scan_scope[@]}" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')"
    advisory_count=$((advisory_count + n))
done
note "advisory patterns (password / RFC-1918 examples): $advisory_count hit(s) — expected in docs"

# Skills are copies. A stale copy ships silently wrong advice to every agent
# that reads it, which is how the pre-1.1.3 mapping-key regression escaped.
if [[ -d "${PRELUDE_CLAUDE:-$repo_root/../prelude-claude}" || -d "${PRELUDE_MCP:-$repo_root/../prelude-mcp}" ]]; then
    if out="$("$repo_root/scripts/sync-skills.sh" --check 2>&1)"; then
        ok "vendored skills in sync with their sources"
    else
        bad "vendored skills have drifted — fix upstream, then ./scripts/sync-skills.sh"
        echo "$out" | sed 's/^/      /'
    fi
else
    warn "skill sources not checked out — cannot verify skills/ is current"
    note "set PRELUDE_CLAUDE / PRELUDE_MCP to verify before a tagged release"
fi

# The tag answers "which playground matches my collector", so it has to agree
# with the compatibility line a reader actually sees.
readme_version="$(grep -oE 'Verified against \*\*Prelude Collector v[0-9]+\.[0-9]+\.[0-9]+\*\*' README.md \
    | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || true)"
if [[ -z "$readme_version" ]]; then
    warn "no 'Verified against **Prelude Collector vX.Y.Z**' line found in README.md"
elif [[ -z "$version" ]]; then
    note "README compatibility line: $readme_version"
elif [[ "$readme_version" == "$version" ]]; then
    ok "README compatibility line matches $version"
else
    bad "README says $readme_version but you are tagging $version"
    note "the tag tracks the collector version the content was verified against — bump one of them"
fi

# --------------------------------------------------------------- verdict

head2 "Verdict"
if [[ $fails -gt 0 ]]; then
    printf '  %s%d gate(s) failed%s, %d warning(s). Nothing published.\n' "$C_BAD" "$fails" "$C_OFF" "$warns"
    exit 1
fi
printf '  %sall gates passed%s, %d warning(s).\n' "$C_OK" "$C_OFF" "$warns"

if [[ "$check_only" == true ]]; then
    echo "  --check-only: stopping here."
    exit 0
fi

# ------------------------------------------------- manual import re-verify

if [[ -n "$version" ]]; then
    cat <<'REMINDER'

  Not automatable from here: import every model and profile into a collector at
  the target version and spot-check one in the UI for fields AND mappings. A
  model can import with its fields and silently lose its mappings when the
  export format moves on. The runbook has the loop.
REMINDER
fi

# ---------------------------------------------------------------- confirm

echo
echo "About to publish to the PUBLIC repo $GITHUB_REPO:"
echo "  branch  $PUBLISH_BRANCH -> $(git rev-parse --short HEAD)"
[[ -n "$version" ]] && echo "  tag     $version"
[[ -n "$version" && "$want_release" == true ]] && echo "  release $version + 2 .skill bundles"
[[ "$dry_run" == true ]] && echo "  (dry run — no writes)"

if [[ "$assume_yes" != true && "$dry_run" != true ]]; then
    read -r -p "Proceed? [y/N] " reply
    [[ "$reply" == [yY] ]] || abort "aborted by user"
fi

run() {
    if [[ "$dry_run" == true ]]; then
        printf '  %swould run:%s %s\n' "$C_DIM" "$C_OFF" "$*"
    else
        printf '  %s$%s %s\n' "$C_DIM" "$C_OFF" "$*"
        "$@"
    fi
}

# -------------------------------------------------------------------- tag

head2 "Publishing"

if [[ -n "$version" ]]; then
    if git rev-parse --verify --quiet "refs/tags/$version" >/dev/null; then
        tagged="$(git rev-list -n1 "$version")"
        if [[ "$tagged" == "$head" ]]; then
            ok "tag $version already on HEAD"
        else
            abort "tag $version exists but points at ${tagged:0:7}, not HEAD"
        fi
    else
        run git tag -a "$version" -m "$version — verified against Prelude Collector $version"
    fi
fi

# ------------------------------------------------------------------- push

# GitLab first: it is the source of truth, and a failure there should stop the
# public push rather than leave the two remotes disagreeing.
run git push origin "$PUBLISH_BRANCH" --follow-tags
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    run git -c credential.helper="$TOKEN_HELPER" push "$GITHUB_REMOTE" "$PUBLISH_BRANCH" --follow-tags
else
    run git push "$GITHUB_REMOTE" "$PUBLISH_BRANCH" --follow-tags
fi

# ---------------------------------------------------------------- release

if [[ -n "$version" && "$want_release" == true ]]; then
    head2 "Release"

    bundle_dir="$(mktemp -d)"
    trap 'rm -rf "$bundle_dir"' EXIT
    bundles=()
    for name in prelude-collector-api prelude-mcp-companion; do
        ( cd "$repo_root/skills" && zip -qr "$bundle_dir/$name.skill" "$name" -x '*.DS_Store' )
        bundles+=("$bundle_dir/$name.skill")
        ok "built $name.skill ($(du -h "$bundle_dir/$name.skill" | cut -f1 | tr -d ' '))"
    done

    prev_tag="$(git describe --tags --abbrev=0 "$version^" 2>/dev/null || true)"
    if [[ -n "$prev_tag" ]]; then
        changes="$(git --no-pager log --format='- %s' --no-merges "$prev_tag..$version")"
        range_note="Changes since $prev_tag:"
    else
        changes="- First published release."
        range_note="Changes:"
    fi

    notes="$(cat <<NOTES
Verified against **Prelude Collector ${readme_version:-$version}**.

$range_note

$changes

## Agent skills

The two agent skills are attached as \`.skill\` bundles — no clone needed. Unzip
either into \`~/.claude/skills/\`:

\`\`\`bash
unzip prelude-collector-api.skill -d ~/.claude/skills/
\`\`\`
NOTES
)"

    if [[ "$dry_run" == true ]]; then
        printf '  %swould run:%s gh release create %s --repo %s (+%d assets)\n' \
            "$C_DIM" "$C_OFF" "$version" "$GITHUB_REPO" "${#bundles[@]}"
        echo "$notes" | sed 's/^/      /'
    else
        gh release create "$version" \
            --repo "$GITHUB_REPO" \
            --title "$version" \
            --notes "$notes" \
            "${bundles[@]}"
        ok "release published: https://github.com/$GITHUB_REPO/releases/tag/$version"
    fi
fi

head2 "Done"
if [[ "$dry_run" == true ]]; then
    echo "  Dry run — nothing was written."
else
    echo "  https://github.com/$GITHUB_REPO"
    echo
    echo "  Still by hand: refresh the customer-portal pointer to this repo."
fi

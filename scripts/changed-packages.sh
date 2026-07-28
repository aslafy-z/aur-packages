#!/usr/bin/env bash
# Selects the packages CI should build and prints them as a JSON array.
#
# Given no base ref, or one that no longer resolves after a force push, every
# package is selected. Otherwise selection is limited to the packages whose own
# files differ from the base ref.
set -euo pipefail

# Paths CI actually executes. A change to any of them can alter how every
# package is built, so it invalidates per-package selection. mise.toml and the
# repository docs are deliberately absent: nothing in the build path reads them.
readonly TOOLING_PATTERN='^(\.github/workflows/ci\.yml|scripts/)'

list_all() {
    find packages -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
}

list_changed() {
    local base=$1 changed pkg

    # Three-dot, so the comparison starts at the merge base rather than at the
    # tip of the base branch. On a pull request that excludes commits landed on
    # the base since the branch diverged.
    changed=$(git diff --name-only "${base}...HEAD")

    if grep -qE "$TOOLING_PATTERN" <<<"$changed"; then
        list_all
        return
    fi

    # Deleted and renamed-away packages still show up in the diff. Only the ones
    # surviving in the worktree can be handed to makepkg.
    while IFS= read -r pkg; do
        if [[ -d "packages/$pkg" ]]; then
            echo "$pkg"
        fi
    done < <(sed -n 's|^packages/\([^/]*\)/.*|\1|p' <<<"$changed")
}

base=${1-}

if [[ -n $base ]] && git rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
    list_changed "$base"
else
    list_all
fi | sort -u | jq -R . | jq -cs .

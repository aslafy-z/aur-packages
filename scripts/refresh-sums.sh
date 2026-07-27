#!/usr/bin/env bash
# Recompute every checksum array in a PKGBUILD.
#
# This replaces updpkgsums, which downloads each source to its `name::` target.
# Packages whose per-architecture sources rename to the same local filename
# therefore get one download and one hash copied into every sha256sums_* array,
# silently corrupting every architecture but the first.
# Here each source is fetched to a slot-unique path instead, so no collision is possible.
#
# Runs in three places: an operator's shell, a mise task, and the Renovate
# container. It must therefore take plain arguments, read no mise-injected
# variables, and depend on nothing beyond bash, curl, awk and coreutils.
set -euo pipefail

reset_pkgrel=false
pkgdir=

while (($#)); do
    case "$1" in
    --reset-pkgrel) reset_pkgrel=true ;;
    -h | --help)
        echo "usage: ${0##*/} [--reset-pkgrel] <package-dir>"
        exit 0
        ;;
    -*)
        echo "unknown option: $1" >&2
        exit 2
        ;;
    *) pkgdir=$1 ;;
    esac
    shift
done

[[ -n $pkgdir ]] || {
    echo "usage: ${0##*/} [--reset-pkgrel] <package-dir>" >&2
    exit 2
}

cd "$pkgdir"
[[ -f PKGBUILD ]] || {
    echo "no PKGBUILD in $pkgdir" >&2
    exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Only the checksum arrays actually declared in the file, in declaration order.
mapfile -t sumvars < <(
    grep -oP '^\s*\K(?:md5|sha1|sha224|sha256|sha384|sha512|b2)sums(?:_[a-z0-9_]+)?(?==\()' PKGBUILD
)
((${#sumvars[@]})) || {
    echo "$pkgdir: no checksum arrays to refresh"
    exit 0
}

# Read an array out of the PKGBUILD by name. Sourcing in a subshell keeps any
# side effects out of this process and expands $pkgver in the source URLs.
read_array() {
    (
        # shellcheck disable=SC1091
        source ./PKGBUILD >/dev/null 2>&1
        declare -n arr="$1" 2>/dev/null || exit 0
        printf '%s\n' "${arr[@]}"
    )
}

for sumvar in "${sumvars[@]}"; do
    algo=${sumvar%%sums*}
    suffix=${sumvar#*sums} # "" or "_x86_64"

    mapfile -t entries < <(read_array "source${suffix}")
    mapfile -t old < <(read_array "$sumvar")

    ((${#entries[@]})) || {
        echo "$pkgdir: $sumvar is declared but source${suffix} is empty" >&2
        exit 1
    }

    new=()
    for i in "${!entries[@]}"; do
        entry=${entries[$i]}
        url=${entry#*::}
        target=${entry%%::*}
        [[ $entry == *::* ]] || target=${url##*/}

        # VCS sources and slots the maintainer marked SKIP carry no checksum.
        if [[ $url == *+*://* || ${old[$i]:-} == SKIP ]]; then
            new+=(SKIP)
            continue
        fi

        if [[ $url == *://* ]]; then
            # Slot-unique destination: this is the updpkgsums bug fix.
            dest="$work/${sumvar}.${i}"
            echo "  fetch ${sumvar}[$i] $url" >&2
            curl -fsSL --retry 3 --retry-delay 2 -o "$dest" "$url"
        else
            dest=$target
            [[ -f $dest ]] || {
                echo "$pkgdir: missing local source $dest" >&2
                exit 1
            }
        fi

        new+=("$("${algo}sum" "$dest" | cut -d' ' -f1)")
    done

    # Replace the whole `name=( ... )` block, keeping one entry per line and
    # aligning continuation lines under the opening parenthesis.
    printf '%s\n' "${new[@]}" >"$work/values"
    awk -v var="$sumvar" -v values="$work/values" '
        BEGIN { while ((getline line < values) > 0) v[n++] = line }
        !inside && $0 ~ "^[[:space:]]*" var "=\\(" {
            indent = $0; sub(/[^[:space:]].*/, "", indent)
            printf "%s%s=(", indent, var
            for (i = 0; i < n; i++)
                printf "%s%c%s%c",
                    (i ? "\n" indent sprintf("%*s", length(var) + 2, "") : ""),
                    39, v[i], 39
            printf ")\n"
            if ($0 ~ /\)[[:space:]]*$/) next
            inside = 1; next
        }
        inside { if ($0 ~ /\)[[:space:]]*$/) inside = 0; next }
        { print }
    ' PKGBUILD >"$work/PKGBUILD.new"
    mv "$work/PKGBUILD.new" PKGBUILD
done

# A new upstream version restarts the package release count. Renovate only
# rewrites pkgver, so the reset happens here.
if [[ $reset_pkgrel == true ]]; then
    sed -i 's/^pkgrel=.*/pkgrel=1/' PKGBUILD
fi

echo "$pkgdir: checksums refreshed"

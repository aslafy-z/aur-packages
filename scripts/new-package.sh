#!/usr/bin/env bash
# Scaffold a package directory from a PKGBUILD skeleton.
set -euo pipefail

pkgname=${1:?usage: ${0##*/} <pkgname>}
maintainer=${AUR_MAINTAINER:?AUR_MAINTAINER is not set}
dir="packages/$pkgname"

[[ -e $dir ]] && {
    echo "$dir already exists" >&2
    exit 1
}

mkdir -p "$dir"
cat >"$dir/PKGBUILD" <<EOF
# Maintainer: $maintainer
# Repository: https://github.com/aslafy-z/aur-packages

# The trailing comment tells Renovate where upstream lives. Without it the
# package is never considered for automatic upgrades.
pkgname=$pkgname
pkgver= # renovate: datasource=github-releases depName=OWNER/REPO
pkgrel=1
pkgdesc=''
arch=('x86_64')
url=''
license=('')
depends=('')
makedepends=('')
source=("")
sha256sums=('SKIP')

build() {
    :
}

package() {
    :
}
EOF

echo "created $dir/PKGBUILD"
echo "next: fill it in, then run 'mise run pkg:refresh $pkgname'"

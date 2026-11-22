#!/usr/bin/env sh
# Builds the technical documentation as PDF (main format) and HTML into ./out.
set -eu
cd "$(dirname "$0")"
mkdir -p out
# Version on the title page: the first argument, else $MUSICUS_VERSION, else the
# workspace version of the Musicus checkout this submodule sits in
# (../../Cargo.toml), else "dev".
VERSION="${1:-${MUSICUS_VERSION:-}}"
if [ -z "$VERSION" ] && grep -qs 'crates/musicus-server' ../../Cargo.toml; then
    VERSION="$(sed -n '/^\[workspace\.package\]/,/^\[/s/^version *= *"\(.*\)"/\1/p' ../../Cargo.toml)"
fi
VERSION="${VERSION:-dev}"
typst compile --font-path fonts --input version="$VERSION" main.typ out/musicus-technical.pdf
typst compile --features html --font-path fonts --input version="$VERSION" main.typ out/musicus-technical.html
echo "out/musicus-technical.pdf and out/musicus-technical.html written (version $VERSION)"

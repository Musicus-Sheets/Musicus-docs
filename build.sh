#!/usr/bin/env sh
# Builds the technical documentation as PDF (main format) and HTML into ./out.
set -eu
cd "$(dirname "$0")"
mkdir -p out
typst compile --font-path fonts main.typ out/musicus-technical.pdf
typst compile --features html --font-path fonts main.typ out/musicus-technical.html
echo "out/musicus-technical.pdf and out/musicus-technical.html written"

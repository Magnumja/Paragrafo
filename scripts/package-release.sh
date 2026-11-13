#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
./build-app.sh
# Stage a fresh, unregistered bundle: Finder/icon services can attach metadata to an app in use.
STAGE="$(mktemp -d .build/package-stage.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
ditto 'dist/Parágrafo.app' "$STAGE/Parágrafo.app"
xattr -cr "$STAGE/Parágrafo.app"
codesign --force --sign - "$STAGE/Parágrafo.app"
codesign --verify --strict "$STAGE/Parágrafo.app"
# macOS metadata is kept by ditto; build caches, test PDFs and model weights stay out.
ditto -c -k --sequesterRsrc --keepParent "$STAGE/Parágrafo.app" dist/Paragrafo.zip
(cd dist && shasum -a 256 Paragrafo.zip > SHA256SUMS.txt)
print 'Release assets: dist/Paragrafo.zip and dist/SHA256SUMS.txt'

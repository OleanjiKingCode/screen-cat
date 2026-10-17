#!/bin/bash
# Builds Screen Cat and zips it for a GitHub release:
#   ./release.sh            -> dist/ScreenCat-mac-1.1.0.zip
#   VERSION=1.2.0 ./release.sh
# The app is ad-hoc signed, not notarized, so people open it the first time
# with right-click > Open (see the README). Signing and notarizing needs an
# Apple Developer ID.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.1.0}"
export VERSION
./build.sh

mkdir -p dist
ZIP="dist/ScreenCat-mac-$VERSION.zip"
rm -f "$ZIP"
# ditto keeps the bundle's signature and metadata intact; zip does not.
ditto -c -k --keepParent ScreenCat.app "$ZIP"
echo "release: $(pwd)/$ZIP"
shasum -a 256 "$ZIP"

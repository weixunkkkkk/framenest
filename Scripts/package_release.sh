#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source version.env
bash Scripts/package_app.sh release
"$ROOT/$APP_NAME.app/Contents/MacOS/$APP_NAME" --self-test
codesign --verify --deep --strict "$ROOT/$APP_NAME.app"
ARCH=$(uname -m)
mkdir -p dist
ARCHIVE="$APP_NAME-$MARKETING_VERSION-macOS-$ARCH.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
echo "Created dist/$ARCHIVE"

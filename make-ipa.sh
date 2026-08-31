#!/bin/bash
# Build Notes va dong goi .ipa KHONG ky vao build/. Sideloadly lo phan ky.
set -euo pipefail
cd "$(dirname "$0")"

xcodebuild -scheme Notes -sdk iphoneos -configuration Release \
  -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build > /tmp/notes-build.log || { grep -E 'error:|BUILD FAILED' /tmp/notes-build.log | head; exit 1; }

APP=build/dd/Build/Products/Release-iphoneos/Notes.app
[ -d "$APP" ] || { echo "Notes.app not found at $APP"; exit 1; }

rm -rf build/Payload && mkdir -p build/Payload
cp -R "$APP" build/Payload/
rm -f build/Notes.ipa
(cd build && zip -qry Notes.ipa Payload && rm -rf Payload)

echo "→ $(pwd)/build/Notes.ipa"

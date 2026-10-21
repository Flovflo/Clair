#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
clair_developer_dir="$(xcode-select -p)"
clair_swiftc="$clair_developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
clair_sdk="$clair_developer_dir/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
clair_app="$PWD/build/Clair.app"
mkdir -p "$clair_app/Contents/MacOS" "$clair_app/Contents/Resources"
"$clair_swiftc" -O -whole-module-optimization -swift-version 6 \
  -sdk "$clair_sdk" -target "$(uname -m)-apple-macosx14.0" \
  Sources/CleanerCore/*.swift Sources/Clair/*.swift \
  -o "$clair_app/Contents/MacOS/Clair"
cp Resources/Info.plist "$clair_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable Clair' "$clair_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.clair.mac' "$clair_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 14.0' "$clair_app/Contents/Info.plist"
cp Resources/AppIcon.icns "$clair_app/Contents/Resources/AppIcon.icns"
# Prefer a certificate-backed identity: ad-hoc designated requirements contain the
# binary hash and can invalidate TCC permissions after each rebuild.
clair_sign_identity="${CLAIR_SIGN_IDENTITY:-}"
if [ -z "$clair_sign_identity" ]; then
  clair_sign_identity="$(security find-identity -v -p codesigning | awk '/"Developer ID Application:/ { print $2; exit }')"
fi
if [ -z "$clair_sign_identity" ]; then
  clair_sign_identity="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ { print $2; exit }')"
fi
if [ -z "$clair_sign_identity" ]; then
  clair_sign_identity="-"
  printf 'Attention : signature ad hoc ; macOS peut redemander les droits après une recompilation.\n'
fi
codesign --force --sign "$clair_sign_identity" --options runtime --timestamp=none "$clair_app"
codesign --verify --strict "$clair_app"
printf '\nApp prête : %s\n' "$clair_app"

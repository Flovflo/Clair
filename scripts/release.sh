#!/bin/bash
# Build only. Publishing and notarization are deliberate, separate operations.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
: "${CLAIR_SIGN_IDENTITY:?Set CLAIR_SIGN_IDENTITY to a Developer ID Application certificate name or SHA-1.}"
clair_release="$PWD/build/release"
clair_app="$clair_release/Clair.app"
clair_sdk="$(xcrun --sdk macosx --show-sdk-path)"
clair_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
if [ -e "$clair_app" ]; then
  printf 'Release bundle already exists: %s. Move it aside before rebuilding.\n' "$clair_app" >&2
  exit 1
fi
mkdir -p "$clair_app/Contents/MacOS" "$clair_app/Contents/Resources"
for clair_arch in arm64 x86_64; do
  xcrun swiftc -O -whole-module-optimization -swift-version 6 \
    -sdk "$clair_sdk" -target "$clair_arch-apple-macosx14.0" \
    -file-prefix-map "$PWD=." -debug-prefix-map "$PWD=." \
    Sources/CleanerCore/*.swift Sources/Clair/*.swift \
    -o "$clair_release/Clair-$clair_arch"
done
xcrun lipo -create "$clair_release/Clair-arm64" "$clair_release/Clair-x86_64" \
  -output "$clair_app/Contents/MacOS/Clair"
cp Resources/Info.plist "$clair_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable Clair' "$clair_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.clair.mac' "$clair_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 14.0' "$clair_app/Contents/Info.plist"
cp Resources/AppIcon.icns "$clair_app/Contents/Resources/AppIcon.icns"
chmod 755 "$clair_app/Contents/MacOS/Clair"
chmod -R u=rwX,go=rX "$clair_app"
# Strip only build-generated extended attributes before signing, never user files.
xattr -cr "$clair_app"
codesign --force --sign "$CLAIR_SIGN_IDENTITY" --options runtime --timestamp "$clair_app"
codesign --verify --strict --verbose=2 "$clair_app"
clair_signature="$(codesign -dvv "$clair_app" 2>&1)"
if ! printf '%s\n' "$clair_signature" | /usr/bin/grep -q '^Authority=Developer ID Application:'; then
  printf 'Release requires a Developer ID Application signature.\n' >&2
  exit 1
fi
if ! printf '%s\n' "$clair_signature" | /usr/bin/grep -q '^Timestamp='; then
  printf 'Release requires a secure Apple timestamp.\n' >&2
  exit 1
fi
clair_archs="$(xcrun lipo -archs "$clair_app/Contents/MacOS/Clair")"
if [ "$clair_archs" != "x86_64 arm64" ] && [ "$clair_archs" != "arm64 x86_64" ]; then
  printf 'Unexpected release architectures: %s\n' "$clair_archs" >&2
  exit 1
fi
ditto -c -k --keepParent "$clair_app" "$clair_release/Clair-$clair_version-notarization.zip"
printf '\nSigned universal app ready for notarization: %s\n' "$clair_app"

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Explicit SDK and bundled runner also support Xcode beta command-line setups.
clair_developer_dir="$(xcode-select -p)"
clair_swiftc="$clair_developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
clair_sdk="$clair_developer_dir/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
clair_frameworks="$clair_developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks"
clair_tests="$PWD/build/tests"
clair_bundle="$clair_tests/CleanerCoreTests.xctest"
mkdir -p "$clair_bundle/Contents/MacOS"
"$clair_swiftc" -swift-version 6 -sdk "$clair_sdk" -target "$(uname -m)-apple-macosx14.0" \
  -emit-library -emit-module -enable-testing -module-name CleanerCore \
  Sources/CleanerCore/*.swift -o "$clair_tests/libCleanerCore.dylib" \
  -emit-module-path "$clair_tests/CleanerCore.swiftmodule"
"$clair_swiftc" -swift-version 6 -sdk "$clair_sdk" -target "$(uname -m)-apple-macosx14.0" \
  -emit-library -module-name CleanerCoreTests -I "$clair_tests" -L "$clair_tests" -lCleanerCore \
  -I "$clair_developer_dir/Platforms/MacOSX.platform/Developer/usr/lib" \
  -L "$clair_developer_dir/Platforms/MacOSX.platform/Developer/usr/lib" \
  -F "$clair_frameworks" -framework XCTest \
  -Xlinker -rpath -Xlinker "$clair_developer_dir/Platforms/MacOSX.platform/Developer/usr/lib" \
  -Xlinker -rpath -Xlinker "$clair_frameworks" -Xlinker -rpath -Xlinker "$clair_tests" \
  Tests/CleanerCoreTests/*.swift -o "$clair_bundle/Contents/MacOS/CleanerCoreTests"
cat > "$clair_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.clair.tests</string>
<key>CFBundleExecutable</key><string>CleanerCoreTests</string>
<key>CFBundlePackageType</key><string>BNDL</string>
</dict></plist>
PLIST
"$clair_developer_dir/Platforms/MacOSX.platform/Developer/Library/Xcode/Agents/xctest" "$clair_bundle"

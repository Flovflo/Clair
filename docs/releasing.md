# Release procedure

Requirements: Xcode 16+, a Developer ID Application certificate in the Keychain,
and Apple notarization credentials. Keep all keys and credentials outside the
repository. Version numbers live in `Resources/Info.plist`, independently of Git
commit counts.

1. Run `bash scripts/test.sh` and inspect all source changes.
2. Set `CLAIR_SIGN_IDENTITY` to your certificate name or SHA-1 and run
   `bash scripts/release.sh`. This builds ARM64 and Intel executables with the
   hardened runtime, a Developer ID signature and a secure timestamp.
3. Submit `build/release/Clair-<version>-notarization.zip` with
   `asc notarization submit --file <zip> --wait`. Require **Accepted**.
4. Run `xcrun stapler staple build/release/Clair.app`, then
   `xcrun stapler validate build/release/Clair.app` and
   `spctl --assess --type execute --verbose=2 build/release/Clair.app`.
5. Create a distribution ZIP from the stapled app. For a DMG, stage only the app,
   an Applications shortcut and installation instructions; build and sign the
   image with Developer ID, submit that DMG for notarization, then staple and
   validate it too.
6. Verify the mounted DMG and extracted ZIP, generate SHA-256 checksums, and
   publish assets only after the source, license and privacy checks pass.

Never publish local inventories, scan reports, diagnostic JSON, build logs,
signing exports or development screenshots containing personal filenames.
Check Git author and committer metadata as well as file content. A Developer ID
certificate intentionally reveals its registered publisher name and team ID;
do not claim the signed binary hides that identity.

The release script does not notarize, upload, tag, or publish automatically.
CI builds and tests without signing credentials. Release credentials stay local.

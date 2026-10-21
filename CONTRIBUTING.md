# Contributing

Clair is a native SwiftUI application for macOS 14 or later, written in Swift 6.
Install Xcode 16 or later and select its developer directory with `xcode-select`.
No third-party runtime dependency is required.

```sh
bash scripts/test.sh
bash scripts/build.sh
open build/Clair.app
```

Run the tests before submitting a pull request. Use small Conventional Commits
and explain behavior changes, validation, and any storage or permission impact.
Tests must operate on temporary fixtures; never run real cleanup on a user's Mac.

Keep path classification separate from deletion authorization. Do not widen the
cleanup allowlist without negative tests for personal data, symlinks, changed
files and protected project directories. Never add automatic deletion, remote
telemetry, or permission bypasses.

Do not attach real inventories, user paths, signing keys or account credentials.
Use fictional project names and temporary directories in examples and tests.
See [SECURITY.md](SECURITY.md) for private vulnerability reports.

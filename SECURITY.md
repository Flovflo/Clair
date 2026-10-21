# Security

Please report vulnerabilities through GitHub's private vulnerability reporting
on this repository (Security → Report a vulnerability). Do not include disk
inventories, private filenames, credentials, or personal documents in public
issues. Reproduce problems with temporary, synthetic files where possible.

The latest published release receives security fixes. This project does not
promise that every large file is safe to remove.

## Security boundaries

- Clair runs as the current user, without root access or a privileged helper.
- Full Disk Access is granted by macOS, explicitly by the user. It is powerful:
  download binaries only from this repository's releases.
- Analysis reads filesystem names and metadata. No analytics, upload service,
  language model, or remote content processing is included.
- The local SQLite inventory contains sensitive paths and timestamps. It is
  created with owner-only file permissions. Treat exported reports as private.
- Cleanup requires an explicit selection and confirmation. The app revalidates
  approved paths and metadata, rejects symbolic links, and uses the macOS Trash.
  It never empties the Trash or deletes system files with elevated privileges.
- Revalidation reduces accidental changes; it is not an atomic filesystem
  transaction against another process changing directories concurrently. Stop
  builds and applications using the selected files before cleanup.
- A size estimate is not a guarantee of recoverable disk space. APFS clones,
  snapshots, hard links and cloud storage can affect results.

Apple signing and notarization establish provenance and pass Apple's checks;
they do not guarantee the absence of vulnerabilities. The signing certificate's
publisher identity is visible in every Developer ID signed application.

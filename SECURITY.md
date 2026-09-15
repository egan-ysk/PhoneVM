# Security Policy

## Supported Versions

PhoneVM is in early development. Security fixes are provided for the latest commit on the default branch and the latest GitHub Release.

## Reporting a Vulnerability

Please do not open a public issue for sensitive security reports.

Report suspected vulnerabilities by emailing the maintainer listed in the repository metadata or by using GitHub private vulnerability reporting if it is enabled for this repository.

When reporting, include:

- affected version or commit
- macOS version
- steps to reproduce
- expected and actual behavior
- whether local paths, commands, or external tools are involved

## Security Design Notes

- PhoneVM executes emulator tools through `Process` with argument arrays instead of shell string interpolation.
- User-provided paths are stored locally and are not uploaded by the app.
- The app does not require tokens, cloud credentials, or account secrets.
- Default scan locations are derived from the current user's home directory at runtime instead of hard-coded personal paths.
- Physical-device identifiers are used locally to target the selected device. Screenshots are copied to the macOS clipboard and are not uploaded by PhoneVM.
- iOS discovery JSON and screenshots use separate temporary directories, which are removed after each operation succeeds or fails. Force-quitting or a system crash can leave temporary files until system cleanup.
- The optional iOS screenshot backend is installed separately from the app. Its setup script downloads Python dependencies from PyPI; device pairing remains managed by the local Apple tools and backend.
- Release packages contain only the app bundle. Local device captures, settings, Python environments, analysis notes, extended attributes, and debug symbols are excluded.

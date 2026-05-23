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

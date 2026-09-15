# Contributing

Thanks for considering a contribution to PhoneVM.

## Development

```bash
swift build
Scripts/run-self-tests.sh
Scripts/build-app.sh
```

## Commit Messages

Use one of the following prefixes:

```text
feat:, fix:, docs:, style:, refactor:, perf:, test:, chore:, revert:, build:
```

Prefer concise Chinese descriptions when working in this repository.

## Pull Requests

- Keep changes focused and easy to review.
- Include validation commands in the PR description.
- Avoid committing generated build output such as `.build/` or `dist/`.
- Do not include private tokens, local account data, or machine-specific absolute paths.

## Architecture

New virtual machine integrations should implement `VirtualMachineProvider` and keep platform-specific scan/start/stop/status logic isolated from UI code.

## Releases

1. Update the default `BUNDLE_VERSION` in `Scripts/build-app.sh`, `CHANGELOG.md`, and the README version.
2. Review the exact staged files for credentials, personal paths, real device identifiers, screenshots, and local working notes. Use the existing GitHub noreply commit identity.
3. Run `swift test`, `Scripts/run-self-tests.sh`, and `BUILD_CONFIGURATION=release Scripts/build-app.sh`. Verify bundle version, architecture, and ad-hoc signature; scan the bundle for personal paths and secrets. Ad-hoc signing does not provide Apple notarization.
4. Commit the scoped changes, push `main`, and wait for GitHub CI to pass for that commit.
5. Create an annotated `v<version>` tag for the verified commit. Package `PhoneVM.app` with `ditto -c -k --norsrc --noextattr --noqtn --keepParent` as `PhoneVM-v<version>-macos.zip`.
6. Create a GitHub Release draft with the ZIP, `setup-ios-screenshot.sh`, and `SHA256SUMS.txt`. Mention the required macOS version, CPU architecture, optional iOS dependency, validation scope, and notarization status.
7. Verify draft assets, publish the release, and confirm the published tag, asset sizes, and SHA-256 digests match the local build. Do not include `.build`, local settings, or device captures.

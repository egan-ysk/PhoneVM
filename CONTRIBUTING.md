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

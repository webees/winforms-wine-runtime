# Contributing

## Development setup

Requirements: Docker 24+ with BuildKit, `make`, and (for linting) `shellcheck`,
`hadolint` and `actionlint`.

```bash
make build      # build runtime and self-test images
make test       # run the self-test suite
make lint       # dockerfile + shell + workflow lint
```

Building takes 6–8 minutes on 8 vCPU; the Wine prefix and WebView2 runtime
layers are cached afterwards.

## Ground rules

- Keep the image **amd64-only**. A `.NET win-x64` application cannot run on
  arm64 Wine without an x86-64 emulator, and shipping one would be misleading.
- Do not raise `WEBVIEW2_VERSION` without evidence. Run
  `scripts/bisect-webview2.sh <version>` and attach the result to the pull
  request.
- Keep the runtime free of application code. The `demo` target exists only for
  CI and must stay small.
- Shell scripts must pass `shellcheck` and use `set -euo pipefail`.
- Pin new GitHub Actions by version tag and add the action to
  `.github/dependabot.yml`.

## Pull requests

1. One logical change per pull request.
2. Update `CHANGELOG.md` under `Unreleased`.
3. Describe how you verified the change. Image changes require a CI run or a
   local `make test` transcript.
4. Update the docs when behaviour, ports, volumes or environment variables
   change.

## Commit messages

Conventional Commits, for example:

```
feat(vnc): require a password for non-loopback binds
fix(entrypoint): wait for Xvfb instead of sleeping
docs: document /wine persistence across upgrades
```

## Release process

Maintainers tag `vX.Y.Z`; the release workflow publishes
`ghcr.io/webees/winforms-wine-runtime` with semver tags, SBOM and provenance.

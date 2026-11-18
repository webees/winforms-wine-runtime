# Versioning

This image uses [CalVer](https://calver.org/): `vYYYY.MM.DD`, dated in
`Asia/Shanghai` (override with `CALVER_TZ`). Every release appends `N`:
`v2026.11.19.1`, `v2026.11.19.2`.

## Why not SemVer

SemVer promises backwards-compatible patches; a base image cannot: a rebuild can
change Ubuntu, Wine, WebView2 or fonts and thus runtime behaviour. A date pins
the exact release without a claim it cannot keep. Test every release.

## Tags

| Ref | Example | Meaning |
|---|---|---|
| Git tag | `v<version>` | Canonical release, immutable |
| Image tag | `<version>` | Canonical image, immutable |
| Image alias | `latest` | Newest release (moves) |
| Local tag | `dev`, `dev-demo` | Local builds only, never published |

The `latest` alias is a convenience, not a pin. Prod should use an exact date
tag or, better, its digest:

```dockerfile
FROM ghcr.io/webees/winforms-wine-runtime:<version>
```

```bash
docker pull ghcr.io/webees/winforms-wine-runtime@sha256:...
```

## Publishing

Releases are automated end to end. A push to `main` with `## [Unreleased]`
entries makes the Release workflow run `scripts/version.sh bump`, open a
`chore(release): v<version>` pull request, wait for checks, rebase-merge it,
tag that commit and publish. It needs a `RELEASE_TOKEN` fine-grained PAT for
this repository (Contents, Pull requests: read and write), because pull requests
opened by `GITHUB_TOKEN` never run workflows. Create it at
[personal-access-tokens/new](https://github.com/settings/personal-access-tokens/new),
then `gh secret set RELEASE_TOKEN`; until then the job warns and skips.

Every release gets the next `.N`; tags are never reused. Re-run a failed
publish with `gh workflow run release.yml -f tag=v<version>`.

The retired 1.0.0 image was the noVNC runtime, incompatible with the current
KasmVNC runtime. The `2` alias was removed: it duplicated `latest`.

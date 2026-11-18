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

The `latest` alias is a convenience, not a reproducible pin. Production
deployments should use an exact date tag or, better, its digest:

```dockerfile
FROM ghcr.io/webees/winforms-wine-runtime:<version>
```

```bash
docker pull ghcr.io/webees/winforms-wine-runtime@sha256:...
```

## Publishing

Releases are automated end to end. A push to `main` with `## [Unreleased]`
entries makes the Release workflow run `scripts/version.sh bump`, open a
`chore(release): v<version>` pull request, dispatch CI on it, rebase-merge it
once green, tag the result and publish image, release and attestation.

The tag must be a `vYYYY.MM.DD[.N]` tag with a matching dated
`CHANGELOG.md` section reachable from `main`; re-run a failed publish with
`gh workflow run release.yml -f tag=v<version>`.

Same-day rebuilds get `.1`, `.2`, and so on. Tags are never reused.

The retired 1.0.0 image was the noVNC runtime, incompatible with the current
KasmVNC runtime. The `2` alias was removed: it duplicated `latest`.

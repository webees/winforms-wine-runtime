# Versioning

This image uses [CalVer](https://calver.org/): `vYYYY.MM.DD`, where the date is
the UTC release date. A rebuild published on the same day appends an incrementing
`N`: `v2026.11.17`, `v2026.11.17.1`, `v2026.11.17.2`.

## Why not SemVer

SemVer promises that a patch release is backwards compatible. A base image
cannot honestly promise that: rebuilding can change Ubuntu, Wine, WebView2 or
fonts underneath an application, and any of those can change runtime behaviour
without touching this repository’s own interface. A date identifies the exact
release without making a compatibility claim it cannot keep.

The stable contract is documented explicitly: environment variables, ports and
paths in the README. Treat every release as potentially behaviour-changing and
test before rolling it out.

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

Releases are automated. A push to `main` whose `## [Unreleased]` section has
entries makes the Release workflow open a `chore(release): v<version>` pull
request (`scripts/version.sh bump` moves the changelog and pinned references).
Merging it tags the commit and publishes the image, release and attestation.
The tag must be a `vYYYY.MM.DD[.N]` tag with a matching dated
`CHANGELOG.md` section reachable from `main`; re-run a failed publish with
`gh workflow run release.yml -f tag=v<version>`.

Same-day rebuilds get `.1`, `.2`, and so on. Tags are never reused.

The retired 1.0.0 image was the old noVNC runtime. It is not compatible with the
current KasmVNC runtime and is no longer published. The retired `2` alias was
removed as well: a numeric major alias duplicates `latest`, invites deployments
that silently move, and was never needed after CalVer tags became the contract.

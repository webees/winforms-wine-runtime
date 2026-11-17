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
| Git tag | `v2026.11.17` | Canonical release, immutable |
| Image tag | `2026.11.17` | Canonical image, immutable |
| Image alias | `2` | Latest release of the 2.x line (moves) |
| Image alias | `latest` | Newest release (moves) |
| Local tag | `dev`, `dev-demo` | Local builds only, never published |

The `2` and `latest` aliases are conveniences, not reproducible pins. Production
deployments should use an exact date tag or, better, its digest:

```dockerfile
FROM ghcr.io/webees/winforms-wine-runtime:2026.11.17
```

```bash
docker pull ghcr.io/webees/winforms-wine-runtime@sha256:...
```

## Publishing

`scripts/version.sh next` computes the next tag for today; `make version` runs
it. The release workflow accepts only `vYYYY.MM.DD[.N]`, requires a matching,
dated `CHANGELOG.md` section, and requires the tag to be on `main`.

```bash
git switch main && git pull --ff-only
make version                  # e.g. v2026.11.17
# move the Unreleased changelog entries under that version and date
git commit -am "release: 2026.11.17"
git tag -a v2026.11.17 -m "2026.11.17"
git push origin main v2026.11.17
```

Same-day rebuilds get `.1`, `.2`, and so on. Tags are never reused.

The retired 1.0.0 image was the old noVNC runtime. It is not compatible with the
2.x KasmVNC runtime and is no longer published.

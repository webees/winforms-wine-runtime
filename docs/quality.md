# Quality score

Engineering quality is graded by `scripts/quality.py`; runtime performance is
graded by `scripts/score.py`. In both rubrics every dimension is scored out of
100 and the overall score is the mean of the dimensions, so both must report
100 before a release.

| Axis | Script | Input | Question |
|---|---|---|---|
| Engineering | `scripts/quality.py` | checkout | Is the repository correct, pinned, documented and testable? |
| Performance | `scripts/score.py` | `bench.json` | Is the image small, fast and lean at runtime? |

The engineering audit is offline and deterministic. It reads the checkout only:
no network, no Docker, no built image. That keeps it usable in every lint job
and reproducible on a laptop.

## Scoring

Every dimension is scored out of **100**: its checks carry points, and the
dimension score is the share of those points that pass. The repository score is
the mean of the ten dimension scores, so **100 requires every dimension at
100**. A run below `--min` (default `100`) exits non-zero and prints every
failing check with evidence.

```
make quality                      # human-readable table, fails below 100
./scripts/quality.py --json q.json  # machine-readable report
```

## Dimensions

| Dimension | Score | What it proves |
|---|---|---|
| `hygiene` | 100 | Required community files, no generated artifacts, no TODO markers, clean whitespace, no empty or bloated text files |
| `shell` | 100 | `set -euo pipefail`, exec bits, 120-column limit, no `eval`/pipe-to-shell, header comment |
| `python` | 100 | shebang and exec bit, 100-column limit, module docstring, `__main__` entry |
| `supply-chain` | 100 | Base images pinned by digest, downloads checksum-verified, actions pinned to commit SHAs, apt lists removed, multi-stage build, bounded Dependabot updates |
| `runtime` | 100 | `tini` as PID 1, health check with a realistic boot window, one exposed port, TLS on by default, fail-closed authentication, no secrets baked in |
| `governance` | 100 | Least-privilege token, run cancellation, Dependabot coverage, CODEOWNERS, PR/issue templates, cleanup workflows, supported version |
| `release` | 100 | No numeric moving aliases, pinned runners, credential-free checkouts, scoped tokens, manual-only tag deletion, CalVer changelog |
| `docs` | 100 | Language switch and bilingual parity, environment/argument/port/benchmark tables derived from code, resolvable links, documented rubric, CalVer and current image references |
| `verification` | 100 | Rubric unit tests, strict self-test, Make targets, quality gate wired into `make lint` and CI |
| `leanness` | 100 | Small tracked tree, bounded file size, every script referenced, a single audit entry point |

## Check rules

The rules are implemented once, in `scripts/quality.py`; this table mirrors them
so reviewers can read the intent without reading Python.

| Check | Passes when |
|---|---|
| `hygiene.files` | README (both languages), LICENSE, SECURITY, CONTRIBUTING, CODE_OF_CONDUCT, CHANGELOG, THIRD-PARTY-NOTICES, .gitignore, .dockerignore, .editorconfig and Makefile exist |
| `hygiene.artifacts` | No screenshots, SARIF files or bench reports are committed at the repository root |
| `hygiene.markers` | No TODO, FIXME, XXX or HACK in Markdown, shell, Python or workflows |
| `hygiene.whitespace` | LF endings, final newline, no trailing spaces |
| `hygiene.empty` | No tracked text file is zero bytes |
| `hygiene.size` | No tracked text file exceeds 32 KiB |
| `hygiene.naming` | Lowercase kebab-case (PEP 8 snake_case for Python), fixed uppercase docs, PascalCase .NET |
| `shell.strict` | Every `docker/*.sh` and `scripts/*.sh` sets `-euo pipefail` |
| `shell.exec` | Every shell script is executable |
| `shell.length` | No shell line exceeds 120 columns |
| `shell.banned` | No `eval`, no curl-to-shell pipe, no `set +e` |
| `shell.header` | Each script starts with a comment |
| `python.entry` | Each `scripts/*.py` has the python3 shebang and the exec bit |
| `python.length` | No Python line exceeds 100 columns |
| `python.docstring` | Each module has a docstring |
| `python.main` | Each script has a `__main__` guard |
| `supply.digest` | Every `FROM` resolves to `name:tag@sha256:<64 hex>`; ARG indirection is expanded |
| `supply.checksums` | At least two downloads and one `sha256sum -c` per download; `WEBVIEW2_SHA256` is declared |
| `supply.actions` | Every `uses:` is a 40-character commit SHA with a `# vX` comment |
| `supply.apt` | `rm -rf /var/lib/apt/lists/*` is present and no `:latest` tag is used |
| `supply.stages` | The Dockerfile is multi-stage (at least three `FROM` lines) |
| `supply.dependabot-hygiene` | `github-actions`, `docker` and `nuget` are grouped and bounded by `open-pull-requests-limit` |
| `runtime.tini` | `ENTRYPOINT` starts with `tini --` |
| `runtime.healthcheck` | `HEALTHCHECK` probes `xdpyinfo` and the KasmVNC port inline |
| `runtime.port` | Exactly one `EXPOSE`, and it is `6901` |
| `runtime.tls` | `KASMVNC_SSL` defaults to `1` |
| `runtime.auth` | The entrypoint requires `VNC_PASSWORD` unless `KASMVNC_ALLOW_NO_AUTH` is set, and exits non-zero otherwise |
| `runtime.secrets` | No `ENV`/`ARG` credential and no copied key material |
| `runtime.healthcheck-window` | `--start-period` is at least 60s and `--retries` at least 3 |
| `runtime.no-auth-warning` | An unset `VNC_PASSWORD` with `KASMVNC_ALLOW_NO_AUTH=1` logs a warning |
| `gov.permissions` | CI declares `permissions: contents: read` |
| `gov.concurrency` | CI cancels superseded runs |
| `gov.dependabot` | Dependabot covers `github-actions`, `docker` and `nuget` |
| `gov.codeowners` | `.github/CODEOWNERS` exists |
| `gov.templates` | PR template plus at least two issue forms |
| `gov.cleanup` | Workflow-run and GHCR cleanup workflows exist |
| `gov.security` | The latest CHANGELOG release appears in `SECURITY.md` |
| `release.immutable-tags` | Release metadata produces only the CalVer tag and `latest` |
| `release.runner-pinned` | No workflow runs on a `*-latest` runner label |
| `release.checkout` | Every `actions/checkout` sets `persist-credentials: false` |
| `release.cleanup` | The GHCR cleanup workflow exposes `delete_tags` and no longer pins the retired `2` alias |
| `release.changelog` | `CHANGELOG.md` keeps an `Unreleased` section and dated CalVer headings |
| `release.permissions` | Every workflow declares `permissions:` and none uses `write-all` |
| `release.guarded-delete` | Retired-tag deletion only runs on `workflow_dispatch` and exposes `dry_run` |
| `docs.switch` | Both READMEs link to each other within the first eight lines |
| `docs.parity` | Both READMEs carry the same translated section set |
| `docs.env-docs` | Every variable read by `docker/entrypoint.sh` is in both README tables, and no table entry is unread |
| `docs.args-docs` | The README build-argument table and the Dockerfile `ARG` set are identical |
| `docs.port-docs` | The single `EXPOSE` port appears in both READMEs, the ports doc and both examples |
| `docs.bench-docs` | `docs/benchmark.md` documents exactly the keys `bench.sh` emits, every `score.py` dimension, and a perfect report still scores 100 |
| `docs.image-docs` | Markdown and examples reference the `Makefile` image, never a `:dev` or retired tag |
| `docs.calver` | `docs/versioning.md` explains CalVer and points at `scripts/version.sh` |
| `docs.app-path` | No document advertises a Windows path for `APP` |
| `docs.rubric` | This document names every dimension and the 100-point budget |
| `docs.version` | Every `ghcr.io/...:<CalVer>` reference matches the latest CHANGELOG release |
| `docs.links` | Every relative Markdown link resolves against its own directory |
| `docs.env-parity` | The English and Chinese environment tables list the same variables in the same order |
| `docs.alias` | No Markdown outside `CHANGELOG.md` still advertises the retired `2` alias |
| `verif.tests` | `test_rubrics.py` covers both rubrics with at least fifteen tests |
| `verif.harness` | `selftest.sh`, `bench.sh` and `score.py` exist |
| `verif.make` | `make` exposes `lint`, `quality`, `test`, `bench` and `score` |
| `verif.ci` | The lint job runs `scripts/quality.py` |
| `verif.strict` | `scripts/selftest.sh` runs `--selftest --strict` and fails on a non-zero exit |
| `verif.gate` | `make lint` includes the `quality` target |
| `lean.files` | At most 50 tracked files |
| `lean.lines` | At most 5,000 tracked lines |
| `lean.largest` | No tracked file exceeds 760 lines |
| `lean.orphans` | Every `scripts/*` and `docker/*` file is referenced elsewhere in the tree |
| `lean.audits` | No `scripts/check-*.sh` remains; `quality.py` is the single audit entry point |

## Relationship to the performance score

`docs/benchmark.md` defines the runtime rubric: image size, cold start, first
window, idle RSS and self-test results. The two scores are independent gates:
a change that shrinks the image but breaks documentation lowers the engineering
score, and a change that documents everything but doubles RSS lowers the
performance score. Releases require both at 100.

## Changing the rubric

1. Add or adjust the check in `scripts/quality.py`.
2. Update this document and `scripts/test_rubrics.py` in the same commit.
3. Keep every dimension at 100 points and let `make quality` prove the
   repository still scores 100.

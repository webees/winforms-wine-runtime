# Quality score

Engineering quality is graded by `scripts/quality.py`; runtime performance is
graded by `scripts/score.py`. Both use a 100-point rubric and both must report
100 before a release.

| Axis | Script | Input | Question |
|---|---|---|---|
| Engineering | `scripts/quality.py` | checkout | Is the repository correct, pinned, documented and testable? |
| Performance | `scripts/score.py` | `bench.json` | Is the image small, fast and lean at runtime? |

The engineering audit is offline and deterministic. It reads the checkout only:
no network, no Docker, no built image. That keeps it usable in every lint job
and reproducible on a laptop.

## Scoring

Each check carries points; a dimension scores the sum of passing checks. The
total is the weighted sum of all dimensions (budget 100). A run below `--min`
(default `100`) exits non-zero and prints every failing check with evidence.

```
make quality                      # human-readable table, fails below 100
./scripts/quality.py --json q.json  # machine-readable report
```

## Dimensions

| Dimension | Max | What it proves |
|---|---|---|
| `hygiene` | 10 | Required community files, no generated artifacts, no TODO markers, clean whitespace |
| `shell` | 12 | `set -euo pipefail`, exec bits, 120-column limit, no `eval`/pipe-to-shell, header comment |
| `python` | 8 | shebang and exec bit, 100-column limit, module docstring, `__main__` entry |
| `supply-chain` | 20 | Base images pinned by digest, downloads checksum-verified, actions pinned to commit SHAs, apt lists removed, multi-stage build |
| `runtime` | 15 | `tini` as PID 1, health check, one exposed port, TLS on by default, fail-closed authentication, no secrets baked in |
| `governance` | 10 | Least-privilege token, run cancellation, Dependabot coverage, CODEOWNERS, PR/issue templates, cleanup workflows, supported version |
| `docs` | 15 | Language switch and bilingual parity, code/docs agreement, documented rubric, current release references |
| `verification` | 10 | Rubric unit tests, self-test harness, Make targets, quality gate in CI |

## Check rules

The rules are implemented once, in `scripts/quality.py`; this table mirrors them
so reviewers can read the intent without reading Python.

| Check | Passes when |
|---|---|
| `hygiene.files` | README (both languages), LICENSE, SECURITY, CONTRIBUTING, CODE_OF_CONDUCT, CHANGELOG, THIRD-PARTY-NOTICES, .gitignore, .dockerignore, .editorconfig and Makefile exist |
| `hygiene.artifacts` | No screenshots, SARIF files or bench reports are committed at the repository root |
| `hygiene.markers` | No TODO, FIXME, XXX or HACK in Markdown, shell, Python or workflows |
| `hygiene.whitespace` | LF endings, final newline, no trailing spaces |
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
| `runtime.tini` | `ENTRYPOINT` starts with `tini --` |
| `runtime.healthcheck` | `HEALTHCHECK` calls `healthcheck.sh` |
| `runtime.port` | Exactly one `EXPOSE`, and it is `6901` |
| `runtime.tls` | `KASMVNC_SSL` defaults to `1` |
| `runtime.auth` | The entrypoint requires `VNC_PASSWORD` unless `KASMVNC_ALLOW_NO_AUTH` is set, and exits non-zero otherwise |
| `runtime.secrets` | No `ENV`/`ARG` credential and no copied key material |
| `gov.permissions` | CI declares `permissions: contents: read` |
| `gov.concurrency` | CI cancels superseded runs |
| `gov.dependabot` | Dependabot covers `github-actions`, `docker` and `nuget` |
| `gov.codeowners` | `.github/CODEOWNERS` exists |
| `gov.templates` | PR template plus at least two issue forms |
| `gov.cleanup` | Workflow-run and GHCR cleanup workflows exist |
| `gov.security` | The latest CHANGELOG release appears in `SECURITY.md` |
| `docs.switch` | Both READMEs link to each other within the first eight lines |
| `docs.parity` | Both READMEs carry the same translated section set |
| `docs.sync` | `scripts/check-docs.sh` passes (environment variables, ports, links, build arguments) |
| `docs.rubric` | This document names every dimension and the 100-point budget |
| `docs.version` | Every `ghcr.io/...:<CalVer>` reference matches the latest CHANGELOG release |
| `verif.tests` | `test_score.py` and `test_quality.py` each declare at least five tests |
| `verif.harness` | `selftest.sh`, `bench.sh` and `score.py` exist |
| `verif.make` | `make` exposes `lint`, `quality`, `test`, `bench` and `score` |
| `verif.ci` | The lint job runs `scripts/quality.py` |

## Relationship to the performance score

`docs/benchmark.md` defines the runtime rubric: image size, cold start, first
window, idle RSS and self-test results. The two scores are independent gates:
a change that shrinks the image but breaks documentation lowers the engineering
score, and a change that documents everything but doubles RSS lowers the
performance score. Releases require both at 100.

## Changing the rubric

1. Add or adjust the check in `scripts/quality.py`.
2. Update this document and `scripts/test_quality.py` in the same commit.
3. Keep the budget at 100 points and let `make quality` prove the repository
   still scores 100.

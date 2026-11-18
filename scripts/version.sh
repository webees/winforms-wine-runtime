#!/usr/bin/env bash
# CalVer helpers for this repository: vYYYY.MM.DD[.N]
#
#   ./scripts/version.sh next            print the next tag for today (Asia/Shanghai)
#   ./scripts/version.sh current         print the newest tag
#   ./scripts/version.sh check v2026.11.17   validate and print 2026.11.17
#   ./scripts/version.sh bump 2026.11.18     promote Unreleased to that release
set -euo pipefail
cd "$(dirname "$0")/.."
export TZ=${CALVER_TZ:-Asia/Shanghai}

die() {
  printf 'version: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'usage: %s {next|current|check <tag>|bump <version>}\n' "$0" >&2
}

valid_date() {
  local year=$1 month=$2 day=$3 max
  [[ $month =~ ^(0[1-9]|1[0-2])$ ]] || return 1
  case $month in
  01 | 03 | 05 | 07 | 08 | 10 | 12) max=31 ;;
  04 | 06 | 09 | 11) max=30 ;;
  02) if (((year % 4 == 0 && year % 100 != 0) || year % 400 == 0)); then max=29; else max=28; fi ;;
  esac
  [[ $day =~ ^(0[1-9]|[12][0-9]|3[01])$ ]] || return 1
  ((10#$day <= max))
}

check() {
  local tag=$1
  [[ $tag =~ ^v?([0-9]{4})\.([0-9]{2})\.([0-9]{2})(\.([1-9][0-9]*))?$ ]] ||
    die "not a CalVer tag: $tag (expected vYYYY.MM.DD or vYYYY.MM.DD.N)"
  local year=${BASH_REMATCH[1]} month=${BASH_REMATCH[2]} day=${BASH_REMATCH[3]}
  local build=${BASH_REMATCH[5]:-}
  valid_date "$year" "$month" "$day" || die "invalid calendar date: $year-$month-$day"
  local stamp="${year}${month}${day}" today
  today=$(date +%Y%m%d)
  ((10#$stamp <= 10#$today)) || die "release date is in the future: $year-$month-$day"
  printf '%s.%s.%s' "$year" "$month" "$day"
  if [[ -n $build ]]; then printf '.%s' "$build"; fi
  printf '\n'
}

next() {
  local date base max=-1 tag build
  date=$(date +%Y.%m.%d)
  base="v${date}"
  while IFS= read -r tag; do
    [[ -n $tag ]] || continue
    [[ $tag == "$base" ]] && max=0
    if [[ $tag =~ ^v${date//./\\.}\.([1-9][0-9]*)$ ]]; then
      build=$((10#${BASH_REMATCH[1]}))
      ((build > max)) && max=$build
    fi
  done < <(git tag --list "v${date}*")
  if ((max < 0)); then
    printf '%s\n' "$base"
  else
    printf '%s.%d\n' "$base" "$((max + 1))"
  fi
}

current() {
  git tag --list 'v[0-9]*' --sort=-v:refname | head -n1
}

bump() {
  local version=${1#v} day base=https://github.com/webees/winforms-wine-runtime
  IFS=. read -r a b c _ <<<"$version"
  day="$a-$b-$c"
  awk -v v="$version" -v d="$day" -v base="$base" '
    /^## \[Unreleased\]$/ { print; print ""; print "## [" v "] - " d; next }
    /^\[Unreleased\]:/ { print "[Unreleased]: " base "/compare/v" v "...HEAD"
                         print "[" v "]: " base "/releases/tag/v" v; next }
    { print }' CHANGELOG.md >CHANGELOG.md.tmp
  mv CHANGELOG.md.tmp CHANGELOG.md
  VERSION=$version perl -pi -e \
    's{(winforms-wine-runtime:)\d{4}\.\d{2}\.\d{2}(?:\.\d+)?}{$1$ENV{VERSION}}g;
     s{(\| `)\d{4}\.\d{2}\.\d{2}(?:\.\d+)?(` \(latest\))}{$1$ENV{VERSION}$2}' \
    README.md README.zh-CN.md SECURITY.md examples/kubernetes.yaml \
    docs/ports-and-volumes.md docs/versioning.md
}

case "${1:-}" in
next) next ;;
current) current ;;
bump)
  [[ $# -eq 2 ]] || {
    usage
    exit 2
  }
  bump "$2"
  ;;
check)
  [[ $# -eq 2 ]] || {
    usage
    exit 2
  }
  check "$2"
  ;;
*)
  usage
  exit 2
  ;;
esac

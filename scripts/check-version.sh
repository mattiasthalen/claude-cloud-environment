#!/bin/bash
# Version check seam, shared by CI and CD.
#
# Usage: scripts/check-version.sh <version> [tag ...]
#
# <version> is a bare MAJOR.MINOR.PATCH value — the `SCRIPT_VERSION` constant
# from the working tree. The remaining arguments are the repository's existing
# tag set, in any order, exactly as `git tag -l` prints them; tags that are not
# of the form vMAJOR.MINOR.PATCH are ignored.
#
# Exits zero only if the version is well formed and strictly greater than the
# highest existing tag. An empty tag set (no releases yet) accepts any
# well-formed version.
#
# This is one script rather than logic inlined in a workflow because the same
# check runs on `pull_request` and again in the release workflow. Two copies
# could disagree; one cannot.
set -euo pipefail

readonly VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
readonly TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'

die() {
  echo "check-version: $*" >&2
  exit 1
}

# Numeric comparison per field, so 1.10.0 ranks above 1.9.0 where a string
# comparison would rank it below.
# Prints -1, 0 or 1 for a<b, a==b, a>b.
compare_versions() {
  local a=$1 b=$2
  local -a af bf
  IFS=. read -r -a af <<<"$a"
  IFS=. read -r -a bf <<<"$b"

  local i
  for i in 0 1 2; do
    if ((10#${af[i]} > 10#${bf[i]})); then
      echo 1
      return 0
    fi
    if ((10#${af[i]} < 10#${bf[i]})); then
      echo -1
      return 0
    fi
  done

  echo 0
}

main() {
  if (($# < 1)); then
    die "usage: check-version.sh <version> [tag ...]"
  fi

  local version=$1
  shift

  if [[ ! $version =~ $VERSION_RE ]]; then
    die "version '${version}' is not of the form MAJOR.MINOR.PATCH"
  fi

  # Highest existing release tag, ignoring anything not of the pinned tag form.
  # Truncated forms such as `v1` or `v1.2` are not release tags here; accepting
  # them would tempt a moving tag.
  local highest=""
  local tag bare
  for tag in "$@"; do
    [[ $tag =~ $TAG_RE ]] || continue
    bare=${tag#v}
    if [[ -z $highest || $(compare_versions "$bare" "$highest") == 1 ]]; then
      highest=$bare
    fi
  done

  if [[ -z $highest ]]; then
    echo "check-version: ${version} accepted — no existing release tags"
    return 0
  fi

  if [[ $(compare_versions "$version" "$highest") != 1 ]]; then
    die "version '${version}' is not greater than the highest existing tag 'v${highest}'"
  fi

  echo "check-version: ${version} accepted — greater than highest existing tag v${highest}"
}

main "$@"

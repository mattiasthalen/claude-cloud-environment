#!/bin/bash
# The agent docs are the contract a session follows in whatever repository it is
# working in, and #89 makes them shipped artifacts rather than files a repo
# keeps. Either way a repository named in one of them is wrong everywhere else,
# so this pins the rule they are written to: the tracker doc says to infer the
# repository from the git remote, and neither it nor domain.md names one.
#
# It runs no container — it is a drift guard over a doc, so what it reads is the
# working tree (see docs/agents/testing.md, "What the tests are allowed to
# assert on"). Issue #88 asks for it in the quick tier, which is where the tier
# line puts it.
# tier: quick
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

docs=(
  "${REPO_ROOT}/docs/agents/issue-tracker.md"
  "${REPO_ROOT}/docs/agents/domain.md"
)

# The tracker doc has to say what to do instead of hardcoding: infer the
# repository from the git remote.
grep -qF 'git remote' "${REPO_ROOT}/docs/agents/issue-tracker.md" ||
  harness_fail "docs/agents/issue-tracker.md does not say to infer the repository from the git remote"

# What binds a doc to one repository, as message-then-pattern pairs so every
# check runs the same way. First: a concrete owner/name pair under github.com,
# in either clone form. Placeholders are written `<owner>/<repo>`, and a
# single-segment path (api.github.com/graphql) is not a repository, so neither
# trips this.
checks=(
  $'names a repository by URL\tgithub\\.com[:/][A-Za-z0-9._-]+/[A-Za-z0-9._-]+'
)

# Then the repository this working tree is in, which is the one a doc would
# drift into naming with no URL around it. No remote (a bare export, an archive)
# means nothing to compare against, and the checks above still stand.
remote=$(git -C "${REPO_ROOT}" remote get-url origin 2> /dev/null)
if [ -n "${remote}" ]; then
  # Both clone forms end in <owner>/<name> — https://host/owner/name and
  # git@host:owner/name — so make ':' a separator too and take the last two.
  slug=${remote%.git}
  slug=${slug%/}
  slug=${slug//:/\/}
  name=${slug##*/}
  owner=${slug%/*}
  owner=${owner##*/}
  for token in "${owner}" "${name}"; do
    [ -n "${token}" ] || continue
    checks+=("names this repository ('${token}')"$'\t'"$(printf '%s' "${token}" | sed 's/[.[\^$*]/\\&/g')")
  done
fi

for doc in "${docs[@]}"; do
  for check in "${checks[@]}"; do
    hits=$(grep -nE -- "${check#*$'\t'}" "${doc}") &&
      harness_fail "$(basename "${doc}") ${check%%$'\t'*}: ${hits}"
  done

  # A bare `owner/repo` slug for some *other* repository, which neither a URL
  # match nor the remote comparison catches. Only inline code spans count, since
  # that is how a slug gets written; a two-segment span that resolves to a path
  # in this repo is a file reference, not a slug.
  hits=$(grep -oE '`[^`]+`' "${doc}" | tr -d '`' |
    grep -xE '[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' |
    while read -r span; do
      [ -e "${REPO_ROOT}/${span}" ] || printf '%s\n' "${span}"
    done)
  [ -z "${hits}" ] ||
    harness_fail "$(basename "${doc}") names a repository by slug: ${hits}"
done

echo "the shipped agent docs name no repository"

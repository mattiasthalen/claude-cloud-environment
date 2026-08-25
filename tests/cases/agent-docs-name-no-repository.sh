#!/bin/bash
# The agent docs are shipped as-is into whatever repository a session is working
# in, so naming one repository in them makes the shipped copy wrong everywhere
# else. This is the drift guard for that: it fails if the tracker doc — or
# domain.md, which travels with it — hardcodes a repository rather than leaving
# it to be inferred from the git remote.
#
# It runs no container: the artifact under test is the file the release ships,
# and reading it needs nothing but the working tree.
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

# A concrete owner/name pair under github.com. Placeholders are written
# `<owner>/<repo>`, and a single-segment path (api.github.com/graphql) is not a
# repository, so neither trips this.
for doc in "${docs[@]}"; do
  hits=$(grep -nE 'github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' "${doc}") &&
    harness_fail "$(basename "${doc}") names a repository by URL: ${hits}"
done

# The repository this working tree is in, which is the one a doc would drift
# into naming. No remote (a bare export, an archive) means nothing to compare
# against, and the URL check above still stands.
remote=$(git -C "${REPO_ROOT}" remote get-url origin 2> /dev/null)
if [ -n "${remote}" ]; then
  slug=${remote%.git}
  owner=$(basename "$(dirname "${slug}")")
  name=$(basename "${slug}")
  for doc in "${docs[@]}"; do
    for token in "${owner}" "${name}"; do
      hits=$(grep -nF -- "${token}" "${doc}") &&
        harness_fail "$(basename "${doc}") names this repository ('${token}'): ${hits}"
    done
  done
fi

echo "the shipped agent docs name no repository"

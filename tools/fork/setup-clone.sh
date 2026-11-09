#!/usr/bin/env bash
# One-time setup for a clone of the Storyteller Lofi fork. See FORK.md.
#
# - adds the canonical upstream repository as the `upstream` remote, without
#   its 1,000+ tags (some sit on history GitHub rejects)
# - fetches upstream's main branch and this fork's tags
# - turns on git rerere, so a resolved merge conflict is remembered next time
# - points the GitHub CLI at this fork, so `gh pr create` can never default to
#   the original repository
set -euo pipefail

upstream_url="https://gitlab.com/storyteller-platform/storyteller.git"

cd "$(git rev-parse --show-toplevel)"

if git remote get-url upstream >/dev/null 2>&1; then
  echo "upstream remote: $(git remote get-url upstream)"
else
  git remote add upstream "$upstream_url"
  echo "Added the upstream remote: $upstream_url"
fi
git config remote.upstream.tagOpt --no-tags
git fetch upstream main
git fetch --tags origin

git config rerere.enabled true
git config rerere.autoUpdate true

origin_url=$(git remote get-url origin)
fork=$(echo "$origin_url" |
  sed -n 's#^.*github\.com[:/]\([^/]*/[^/]*\)$#\1#p' |
  sed 's#\.git$##')
if [ -z "$fork" ]; then
  echo "origin ($origin_url) is not a GitHub repository; skipping gh setup."
elif command -v gh >/dev/null 2>&1; then
  gh repo set-default "$fork"
  echo "gh now targets $fork."
else
  echo "Install the GitHub CLI and run: gh repo set-default $fork"
fi

base_tag=$(node tools/fork/upstream-base.mjs HEAD)
if [ -n "$base_tag" ]; then
  echo "This branch is based on upstream $base_tag."
fi

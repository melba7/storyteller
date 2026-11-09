#!/usr/bin/env bash
# Merges a new upstream Storyteller mobile release into a sync branch, for
# review as a pull request. See FORK.md ("Upstream updates").
#
# Usage: tools/fork/sync-upstream.sh [--tag <upstream tag or branch>]
#                                    [--base <ref>] [--dry-run]
#
#   --tag      What to merge. Defaults to upstream's newest stable
#              mobile-vX.Y.Z tag. An upstream branch name (such as main) is
#              accepted for testing.
#   --base     The fork branch to start from. Defaults to origin/main.
#   --dry-run  Report what would happen without creating a branch or merging.
#
# It prints key=value results, and appends them to $GITHUB_OUTPUT in GitHub
# Actions: tag, base_tag, branch, status and, on conflicts, conflicts.
# status is one of:
#   up-to-date        the base already contains the tag
#   already-proposed  origin already has the sync branch
#   would-merge       dry run: the merge would succeed
#   would-conflict    dry run: the merge would conflict
#   merged            the sync branch holds a clean merge
#   merged-lockfile   only yarn.lock conflicted; it was regenerated from
#                     upstream's lockfile with yarn install
#   conflict          other files conflicted; the merge is left in progress
set -euo pipefail

upstream_url="${UPSTREAM_URL:-https://gitlab.com/storyteller-platform/storyteller.git}"
target=""
base="origin/main"
dry_run=false

while [ $# -gt 0 ]; do
  case "$1" in
    --tag)
      target="${2:?--tag needs a value}"
      shift 2
      ;;
    --base)
      base="${2:?--base needs a value}"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h | --help)
      sed -n '2,25p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

cd "$(git rev-parse --show-toplevel)"

output() {
  echo "$1=$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "$1=$2" >>"$GITHUB_OUTPUT"
  fi
}

# Newest stable mobile-vX.Y.Z among the tag names on stdin.
newest_stable() {
  sed -n 's#^mobile-v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$#\1#p' |
    sort -t. -k1,1n -k2,2n -k3,3n |
    tail -n 1 |
    sed 's#^#mobile-v#'
}

if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$upstream_url"
  # Upstream has over a thousand tags, some on history GitHub rejects. Only
  # fetch the ones this script asks for.
  git config remote.upstream.tagOpt --no-tags
fi

if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
  echo "Base $base not found. Run git fetch origin first." >&2
  exit 1
fi

if [ -z "$target" ]; then
  target=$(git ls-remote --tags --refs upstream 'refs/tags/mobile-v*' |
    sed 's#^.*refs/tags/##' | newest_stable)
  if [ "$target" = "mobile-v" ] || [ -z "$target" ]; then
    echo "Found no stable mobile-vX.Y.Z tags upstream." >&2
    exit 1
  fi
fi

if git ls-remote --exit-code --tags upstream "refs/tags/$target" >/dev/null; then
  merge_ref="refs/tags/$target"
  branch="sync/$target"
  git fetch --no-tags upstream "+refs/tags/$target:$merge_ref"
elif git ls-remote --exit-code --heads upstream "refs/heads/$target" >/dev/null; then
  merge_ref="refs/remotes/upstream/$target"
  git fetch --no-tags upstream "+refs/heads/$target:$merge_ref"
  branch="sync/upstream-$target-$(git rev-parse --short "$merge_ref")"
else
  echo "Upstream has no tag or branch named $target." >&2
  exit 1
fi

base_tag=$(node tools/fork/upstream-base.mjs "$base")

output tag "$target"
output base_tag "$base_tag"
output branch "$branch"

if git merge-base --is-ancestor "$merge_ref" "$base"; then
  echo "$base already contains $target."
  output status up-to-date
  exit 0
fi

if git ls-remote --exit-code --heads origin "refs/heads/$branch" >/dev/null; then
  echo "origin already has $branch; review its pull request."
  output status already-proposed
  exit 0
fi

write_conflicts() {
  echo "Conflicting files:"
  echo "$1" | sed 's#^#  #'
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "conflicts<<CONFLICTS_EOF"
      echo "$1"
      echo "CONFLICTS_EOF"
    } >>"$GITHUB_OUTPUT"
  fi
}

if $dry_run; then
  if git merge-tree --write-tree --name-only --no-messages \
    "$base" "$merge_ref" >/dev/null; then
    output status would-merge
  else
    conflicts=$(git merge-tree --write-tree --name-only --no-messages \
      "$base" "$merge_ref" | tail -n +2 || true)
    write_conflicts "$conflicts"
    output status would-conflict
  fi
  exit 0
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "The working tree has uncommitted changes. Commit or stash them first." >&2
  exit 1
fi

git switch --no-track --create "$branch" "$base"
if git merge --no-ff --no-stat --no-edit -m "Merge upstream $target" "$merge_ref"; then
  output status merged
  exit 0
fi

conflicts=$(git diff --name-only --diff-filter=U)
if [ "$conflicts" = "yarn.lock" ]; then
  # Take upstream's lockfile and let yarn add the fork's own dependencies back.
  git checkout --theirs yarn.lock
  yarn install --mode=update-lockfile
  git add yarn.lock
  git commit --no-edit
  output status merged-lockfile
  exit 0
fi

write_conflicts "$conflicts"
output status conflict
echo "The merge is still in progress on $branch. Resolve the files above,"
echo "then: git add -A && git commit --no-edit && git push -u origin $branch"

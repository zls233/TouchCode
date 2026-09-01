#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 task/<short-task-name> <worktree-path>"
  echo "Removes a merged local task worktree and local branch after verifying its GitHub PR merged into main."
}

branch="${1:-}"
worktree_path="${2:-}"
if [[ ! "$branch" =~ ^task/[a-z0-9]+([a-z0-9-]*[a-z0-9]+)?$ || -z "$worktree_path" ]]; then
  usage >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel)"
primary_root="$(git worktree list --porcelain | awk '/^worktree / { print substr($0, 10); exit }')"
if [[ "$repo_root" != "$primary_root" ]]; then
  echo "Run this script from the primary checkout: $primary_root" >&2
  exit 1
fi
if [[ ! -d "$worktree_path" ]]; then
  echo "Worktree does not exist: $worktree_path" >&2
  exit 1
fi
if ! git worktree list --porcelain | grep -Fqx "worktree $worktree_path"; then
  echo "Not a registered Git worktree: $worktree_path" >&2
  exit 1
fi
actual_branch="$(git -C "$worktree_path" symbolic-ref --quiet --short HEAD || true)"
if [[ "$actual_branch" != "$branch" ]]; then
  echo "Worktree checks out '$actual_branch', expected '$branch'; refusing cleanup." >&2
  exit 1
fi

pr_status="$(gh pr view "$branch" --json state,mergedAt,baseRefName --jq '[.state, .mergedAt, .baseRefName] | @tsv' 2>/dev/null || true)"
if [[ -z "$pr_status" ]]; then
  echo "Could not read a GitHub PR for $branch; refusing cleanup." >&2
  exit 1
fi
IFS=$'\t' read -r pr_state merged_at base_branch <<< "$pr_status"
if [[ "$pr_state" != "MERGED" || -z "$merged_at" || "$base_branch" != "main" ]]; then
  echo "PR for $branch is not a merged PR targeting main; refusing cleanup." >&2
  exit 1
fi

git fetch origin main
git worktree remove "$worktree_path"
# A squash merge intentionally leaves the task tip outside main's ancestry, so
# branch -d rejects a branch that GitHub has already verified as merged. The
# worktree is gone and the PR state/base were checked above, making this local
# forced deletion narrowly scoped and safe here.
git branch -D "$branch"
git switch main
git pull --ff-only origin main

echo "Removed worktree and local branch: $branch"
echo "Delete the remote branch through the merged PR settings or with explicit authorization."

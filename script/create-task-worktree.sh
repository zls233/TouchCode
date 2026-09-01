#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <short-task-name>"
  echo "Creates task/<short-task-name> from the freshly fetched origin/main."
}

task_name="${1:-}"
if [[ -z "$task_name" || ! "$task_name" =~ ^[a-z0-9]+([a-z0-9-]*[a-z0-9]+)?$ ]]; then
  usage >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel)"
primary_root="$(git worktree list --porcelain | awk '/^worktree / { print substr($0, 10); exit }')"
if [[ "$repo_root" != "$primary_root" ]]; then
  echo "Run this script from the primary checkout: $primary_root" >&2
  exit 1
fi

branch="task/$task_name"
worktree_root="${TOUCHCODE_TASK_WORKTREE_ROOT:-$(dirname "$repo_root")/TouchCode-worktrees}"
worktree_path="$worktree_root/$task_name"

if git show-ref --verify --quiet "refs/heads/$branch" || git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
  echo "Task branch already exists: $branch" >&2
  exit 1
fi
if [[ -e "$worktree_path" ]]; then
  echo "Task worktree path already exists: $worktree_path" >&2
  exit 1
fi

git fetch origin main
mkdir -p "$worktree_root"
git worktree add -b "$branch" "$worktree_path" origin/main

echo "Created task worktree: $worktree_path"
echo "Branch: $branch"
echo "Next: cd '$worktree_path'"

#!/usr/bin/env bash
set -euo pipefail

# Isolated regression fixture for squash-merged branches. Nothing under the
# checkout running this test is removed.
fixture="$(mktemp -d "${TMPDIR:-/tmp}/touchcode-cleanup-test.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
remote="$fixture/remote.git"
repo="$fixture/repo"
git init --bare -q "$remote"
git init -q -b main "$repo"
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name test
echo base > "$repo/file"
git -C "$repo" add file && git -C "$repo" commit -qm base
git -C "$repo" remote add origin "$remote"
git -C "$repo" push -q -u origin main
git -C "$repo" switch -qc task/fixture
echo task >> "$repo/file"
git -C "$repo" commit -qam task
git -C "$repo" push -q -u origin task/fixture
git -C "$repo" switch -q main
echo squash >> "$repo/file"
git -C "$repo" commit -qam 'squash merge'
git -C "$repo" push -q origin main
worktree="$fixture/worktree"
git -C "$repo" worktree add -q "$worktree" task/fixture
worktree="$(cd "$worktree" && pwd -P)"
fixture_head="$(git -C "$repo" rev-parse refs/heads/task/fixture)"
stale="$fixture/stale-worktree"
git -C "$repo" branch -q task/stale main
git -C "$repo" worktree add -q "$stale" task/stale
stale="$(cd "$stale" && pwd -P)"
stale_head="$(git -C "$repo" rev-parse refs/heads/task/stale)"
echo stale >> "$stale/file"
git -C "$stale" commit -qam stale
wrong="$fixture/wrong-worktree"
git -C "$repo" branch -q task/other main
git -C "$repo" worktree add -q "$wrong" task/other
wrong="$(cd "$wrong" && pwd -P)"

bin="$fixture/bin"
mkdir "$bin"
cat > "$bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'MERGED\t2026-09-01T00:00:00Z\tmain\t%s\n' "$GH_HEAD_SHA"
EOF
chmod +x "$bin/gh"
if (cd "$repo" && GH_HEAD_SHA="$fixture_head" PATH="$bin:$PATH" "$script_dir/cleanup-task-worktree.sh" task/fixture "$wrong") >/dev/null 2>&1; then
  echo "mismatch fixture unexpectedly succeeded" >&2
  exit 1
fi
test -e "$wrong/file"
test -d "$worktree"
git -C "$repo" worktree remove "$wrong" >/dev/null
if (cd "$repo" && GH_HEAD_SHA="$stale_head" PATH="$bin:$PATH" "$script_dir/cleanup-task-worktree.sh" task/stale "$stale") >/dev/null 2>&1; then
  echo "stale-head fixture unexpectedly succeeded" >&2
  exit 1
fi
test -e "$stale/file"
git -C "$repo" worktree remove "$stale" >/dev/null
(cd "$repo" && GH_HEAD_SHA="$fixture_head" PATH="$bin:$PATH" "$script_dir/cleanup-task-worktree.sh" task/fixture "$worktree") \
  >/dev/null
! git -C "$repo" show-ref --verify --quiet refs/heads/task/fixture
test ! -e "$worktree"
echo "cleanup squash-merge fixture: passed"

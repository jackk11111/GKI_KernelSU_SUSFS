#!/usr/bin/env bash
# K1 only: prepare a disposable, non-buildable 6.6.158 conflict-review branch.
# Does not modify the known-good GKI 831d9bce8 worktree or Android ROM workspace.
set -Eeuo pipefail

R="$HOME/annibale-kernel-port"
S="$R/staging-6.6.145"
D="$R/report-6.6.158-direct"
DEST="$R/staging-6.6.158-virtual-review"
BRANCH="annibale-6.6.158-virtual-review-20261011"
EXPECTED_SHORT="831d9bce8"
EXPECTED_TREE="f39a279e5e9f2daf0aa318f6a041e7e531577f1e"
EXPECTED_N=114

echo '=== GATE K1: guard baseline ==='
[ -d "$S" ] || { echo 'STOP: missing source staging checkpoint'; exit 2; }
[ -s "$D/conflict-files.txt" ] || { echo 'STOP: missing conflict list'; exit 2; }
[ -s "$D/threeway-report.txt" ] || { echo 'STOP: missing merge-tree report'; exit 2; }
[ "$(git -C "$S" rev-parse --short=9 HEAD)" = "$EXPECTED_SHORT" ] || { echo 'STOP: checkpoint HEAD changed'; exit 2; }
[ -z "$(git -C "$S" status --porcelain)" ] || { echo 'STOP: checkpoint worktree dirty'; exit 2; }
[ "$(head -n 1 "$D/threeway-report.txt" | tr -d '\r')" = "$EXPECTED_TREE" ] || { echo 'STOP: unexpected virtual tree'; exit 2; }
[ "$(wc -l < "$D/conflict-files.txt")" -eq "$EXPECTED_N" ] || { echo 'STOP: unexpected count of conflicted files'; exit 2; }
[ "$(grep -c '^CONFLICT' "$D/threeway-report.txt")" -eq "$EXPECTED_N" ] || { echo 'STOP: unexpected count of conflict reports'; exit 2; }
[ "$(git -C "$S" cat-file -t "$EXPECTED_TREE")" = tree ] || { echo 'STOP: virtual tree unavailable'; exit 2; }
[ ! -e "$DEST" ] || { echo "STOP: separate destination exists: $DEST"; exit 2; }
if git -C "$S" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "STOP: separate branch exists: $BRANCH"; exit 2
fi
for ref in v6.6.144 v6.6.158; do
  git -C "$S" rev-parse --verify "$ref^{commit}" >/dev/null
 done

# Ensure every one of the 114 expected conflicts really contains markers
# inside the stored virtual tree, before creating any independent worktree.
echo '=== Cross-check 114 conflict markers ==='
n=0
while IFS= read -r path || [ -n "$path" ]; do
  case "$path" in ''|/*|../*|*/../*|*/..) echo 'STOP: unsafe conflict path'; exit 2;; esac
  if ! git -C "$S" show "$EXPECTED_TREE:$path" | grep '^<<<<<<< ' >/dev/null; then
    echo "STOP: missing conflict markers: $path"; exit 2
  fi
  n=$((n + 1))
done < "$D/conflict-files.txt"
[ "$n" -eq "$EXPECTED_N" ] || { echo 'STOP: fewer conflict files than expected'; exit 2; }

HEAD_FULL="$(git -C "$S" rev-parse HEAD)"
echo '=== Create isolated review commit and worktree ==='
# This intentionally records the ENTIRE UNREVIEWED virtual tree as WIP.
# The new branch must NEVER be used to build or flash without a full audit.
WIP_COMMIT="$(printf '%s\n' \
  'WIP TRIAGE ONLY: Linux 6.6.158 virtual merge with 114 unresolved conflicts' \
  '' \
  'Base is the compiled Android GKI checkpoint 831d9bce8.' \
  'Artificial three-way base v6.6.144. NOT ABI checked. NEVER FLASH.' \
  | git -C "$S" -c user.name="Annibale Kernel Triage" \
                    -c user.email="triage@localhost" \
      commit-tree "$EXPECTED_TREE" -p "$HEAD_FULL")"
git -C "$S" branch "$BRANCH" "$WIP_COMMIT"
git -C "$S" worktree add "$DEST" "$BRANCH"

[ "$(git -C "$S" rev-parse HEAD)" = "$HEAD_FULL" ] || { echo 'STOP: baseline unexpectedly changed'; exit 9; }
[ -z "$(git -C "$S" status --porcelain)" ] || { echo 'STOP: baseline unexpectedly dirty'; exit 9; }
[ "$(git -C "$DEST" rev-parse HEAD)" = "$WIP_COMMIT" ] || { echo 'STOP: review worktree HEAD mismatch'; exit 9; }

echo "K1_WIP_BRANCH=$BRANCH"
echo "K1_WIP_COMMIT=$WIP_COMMIT"
echo "K1_WIP_WORKTREE=$DEST"
echo "K1_BASELINE_PRESERVED=$HEAD_FULL"
echo 'K1_READY_FOR_SOURCE_REVIEW (NOT BUILDABLE / NOT FLASHABLE)'

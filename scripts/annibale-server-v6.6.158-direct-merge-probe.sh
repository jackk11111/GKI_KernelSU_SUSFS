#!/usr/bin/env bash
# Non-destructive feasibility probe: 6.6.144/145 experimental ACK GKI KMI8
# against true upstream stable Linux v6.6.158. Does not merge into the
# worktree, change any branch ref, alter .config, flash, or build the ROM.
set -Eeuo pipefail
ROOT="$HOME/annibale-kernel-port"
GIT="$ROOT/ack"
S="$ROOT/staging-6.6.145"
REPORT="$ROOT/UPSTREAM_6.6.158_MERGE_PROBE.txt"
ERROR="$ROOT/UPSTREAM_6.6.158_MERGE_PROBE.stderr"
LATEST="$ROOT/UPSTREAM_6.6.158_HEAD.txt"
TAG="refs/tags/v6.6.158"
EXPECTED="831d9bce8"
echo "=== EXACT COMPILED CHECKPOINT ==="
test "$(git -C "$S" rev-parse --short=9 HEAD)" = "$EXPECTED"
test -z "$(git -C "$S" status --porcelain)"
test -s "$ROOT/out-checkpoint-ABCDE/arch/arm64/boot/Image"
test -s "$ROOT/out-checkpoint-ABCDE/Module.symvers"
test "$(git -C "$GIT" rev-parse --show-toplevel)" = "$(git -C "$S" rev-parse --show-toplevel | sed 's@/staging-6.6.145$@/ack@')" || {
  # Staging is a worktree; root base may reside separately in a linked git dir.
  echo "NOTE: path mismatch between base and linked worktree; checking common refs instead."
}
echo "STAGING=$(git -C "$S" rev-parse --short=12 HEAD)"
echo "KERNEL=$(git -C "$S" show HEAD:Makefile | sed -n -E '/^(VERSION|PATCHLEVEL|SUBLEVEL) =/p' | tr '\n' ' ')"

echo "=== RETRIEVE OFFICIAL UPSTREAM v6.6.158 TAG ==="
if ! git -C "$GIT" show-ref --verify --quiet "$TAG"; then
  # No working tree is updated.  Tag bytes may take several minutes to fetch.
  git -C "$GIT" fetch --no-tags \
    https://github.com/gregkh/linux.git \
    "refs/tags/v6.6.158:refs/tags/v6.6.158"
fi
git -C "$GIT" cat-file -e "$TAG^{commit}"
test "$(git -C "$GIT" show "$TAG:Makefile" | sed -n 's/^SUBLEVEL = //p' | head -1)" = "158"
echo "UPSTREAM_6.6.158_TAG_OK"

echo "=== CHECK COMMON HISTORY ==="
if ! BASE="$(git -C "$S" merge-base HEAD "$TAG")"; then
  echo "ERROR_NO_COMMON_ANCESTOR"
  exit 3
fi
echo "COMMON_ANCESTOR=$(git -C "$S" rev-parse --short=12 "$BASE")"
echo "UPSTREAM_COMMITS_SINCE_BASE=$(git -C "$S" rev-list --count "$BASE..$TAG")"
echo "ACK_COMMITS_SINCE_BASE=$(git -C "$S" rev-list --count "$BASE..HEAD")"

echo "=== DRY-RUN THREE-WAY MERGE TO v6.6.158 (READ-ONLY WORKTREE) ==="
echo "No files in staging or the Evolution X ROM will be changed."
: > "$REPORT"
: > "$ERROR"
set +e
timeout 900s git -C "$S" merge-tree \
    --write-tree --name-only --messages \
    HEAD "$TAG" >"$REPORT" 2>"$ERROR"
rc=$?
set -e
echo "MERGE_PROBE_RC=$rc"
echo "=== FIRST 55 REPORT LINES ==="
head -n 55 "$REPORT" || true
echo "=== CONFLICT SUMMARY ==="
grep -E -c '(^CONFLICT|^Auto-merging)' "$REPORT" || true
grep -E '^CONFLICT' "$REPORT" | head -35 || true
if [[ $rc -eq 0 ]]; then
  echo "MERGE_FEASIBLE_NO_REPORTED_CONFLICTS"
elif [[ $rc -eq 1 ]]; then
  echo "MERGE_CONFLICTS_EXIST_REVIEW_REQUIRED"
else
  echo "MERGE_PROBE_ERROR_OR_TIMEOUT"
  tail -n 35 "$ERROR" || true
fi
echo "=== VERIFY STAGING UNCHANGED ==="
test "$(git -C "$S" rev-parse --short=9 HEAD)" = "$EXPECTED"
test -z "$(git -C "$S" status --porcelain)"
echo "STAGING_AND_COMPILED_IMAGE_PRESERVED"
echo "REPORT=$REPORT"
echo "PROBE_FINISHED"

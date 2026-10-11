#!/usr/bin/env bash
# K1 / Binder: close exactly one proven duplicate stable merge hunk.
# Must run only in the separate virtual-review worktree, never baseline.
set -Eeuo pipefail
R="$HOME/annibale-kernel-port"
BASE="$R/staging-6.6.145"
W="$R/staging-6.6.158-virtual-review"
LIST="$R/report-6.6.158-direct/conflict-files.txt"
P="drivers/android/binder.c"
EXPECTED_WIP="ce713d0652b19d8e208f144bd6b432f7bd9d3c62"
EXPECTED_BASE="831d9bce8371e23466e06129d1fbfcb6eadc1979"
EXPECTED_BEFORE="b70be96d18307bce88d3581585a21d3c5cad189e2daeb84fdd9a58dfd4364ca1"
EXPECTED_AFTER="b79512106fc27f50340f5136abe845faee7d43e0423ebb5c16ae85b54098786a"
BRANCH="annibale-6.6.158-virtual-review-20261011"

stop() { echo "STOP: $*" >&2; exit 2; }
echo "=== K1 BINDER: preconditions ==="
[ "$(git -C "$BASE" rev-parse HEAD)" = "$EXPECTED_BASE" ] || stop "baseline SHA changed"
[ -z "$(git -C "$BASE" status --porcelain)" ] || stop "baseline dirty"
[ "$(git -C "$W" rev-parse HEAD)" = "$EXPECTED_WIP" ] || stop "review HEAD not at expected virtual merge"
[ "$(git -C "$W" branch --show-current)" = "$BRANCH" ] || stop "unexpected branch"
[ -z "$(git -C "$W" status --porcelain)" ] || stop "review worktree dirty"
[ -f "$W/$P" ] && [ -f "$LIST" ] || stop "missing review inputs"
[ "$(sha256sum "$W/$P" | cut -d' ' -f1)" = "$EXPECTED_BEFORE" ] || stop "Binder conflict differs from audited bundle"

# Only edit the *single* empty-HEAD block in binder_free_transaction.
# Verify complete resulting file matches compiled Android baseline byte-for-byte.
python3 - "$W/$P" <<'PY'
from pathlib import Path
import re, sys
f = Path(sys.argv[1])
data = f.read_bytes()
pattern = rb"(?ms)^<<<<<<< HEAD\n(.*?)^=======\n(.*?)^>>>>>>> v6\.6\.158\n"
matches = list(re.finditer(pattern, data))
if len(matches) != 1 or matches[0].group(1) != b"":
    raise SystemExit("STOP: unexpected Binder conflict structure")
a = matches[0]
fixed = data[:a.start()] + data[a.end():]
import hashlib
assert hashlib.sha256(fixed).hexdigest() == "b79512106fc27f50340f5136abe845faee7d43e0423ebb5c16ae85b54098786a", "STOP: resulting binder does not match audited compiled baseline"
f.write_bytes(fixed)
PY

[ "$(sha256sum "$W/$P" | cut -d' ' -f1)" = "$EXPECTED_AFTER" ] || stop "Binder output hash mismatch"
git -C "$BASE" show "HEAD:$P" | cmp - "$W/$P" || stop "Binder differs from compiled Android baseline"
git -C "$W" diff --check -- "$P" || stop "Binder whitespace errors"
git -C "$W" add -- "$P"
git -C "$W" diff --cached --check || stop "staged diff check failed"
[ "$(git -C "$W" diff --cached --name-only)" = "$P" ] || stop "more than Binder staged"
git -C "$W" -c user.name="Annibale Kernel Port" -c user.email="kernel-port@localhost" commit -m "K1: keep existing ACK Binder tmp_ref fix (stable duplicate)"

count=0
while IFS= read -r path || [ -n "$path" ]; do
  [ -n "$path" ] || continue
  if grep -q '^<<<<<<< ' "$W/$path"; then count=$((count + 1)); fi
done < "$LIST"
[ "$count" -eq 113 ] || stop "unexpected number of remaining conflict files: $count"
[ "$(git -C "$BASE" rev-parse HEAD)" = "$EXPECTED_BASE" ] || stop "baseline SHA modified"
[ -z "$(git -C "$BASE" status --porcelain)" ] || stop "baseline dirty"
[ -z "$(git -C "$W" status --porcelain)" ] || stop "review tree dirty"
echo "K1_BINDER_RESOLVED_EQUIVALENT_TO_BASELINE"
echo "K1_REMAINING_CONFLICT_FILES=$count"
echo "K1_REVIEW_HEAD=$(git -C "$W" rev-parse HEAD)"
echo "K1_BASELINE_PRESERVED=$(git -C "$BASE" rev-parse HEAD)"
echo "NOT_BUILDABLE_NOT_FLASHABLE"

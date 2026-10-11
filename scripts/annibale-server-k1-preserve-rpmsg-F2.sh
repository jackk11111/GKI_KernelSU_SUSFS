#!/usr/bin/env bash
# K1 RPMSG F2 regression guard: revert only auto-merged, unsupported
# driver_override infrastructure in the isolated 6.6.158 review tree.
# The ACK compiled checkpoint contains a deliberate read-only override.
set -Eeuo pipefail

R="$HOME/annibale-kernel-port"
BASE="$R/staging-6.6.145"
W="$R/staging-6.6.158-virtual-review"
LIST="$R/report-6.6.158-direct/conflict-files.txt"
P="drivers/rpmsg/rpmsg_core.c"
WIP_HEAD="1e2b18346a4a684a918773d6f13a45c70c332fee"
BASE_HEAD="831d9bce8371e23466e06129d1fbfcb6eadc1979"
MERGED_SHA="849cdd8ff08706de76a6b70cbd51b2fec92397e01083c2e445f8d02285ce1293"
BASE_SHA="6046a3933a5ecc4fd98e60406ad6ddd296da5473c7341be1c980c6f71883ed3f"

fail() { echo "STOP: $*" >&2; exit 2; }
echo "=== K1 RPMSG: verify isolated checkpoint ==="
[ "$(git -C "$BASE" rev-parse HEAD)" = "$BASE_HEAD" ] || fail "baseline changed"
[ -z "$(git -C "$BASE" status --porcelain)" ] || fail "baseline worktree not clean"
[ "$(git -C "$W" rev-parse HEAD)" = "$WIP_HEAD" ] || fail "review commit changed or already patched"
[ "$(git -C "$W" branch --show-current)" = "annibale-6.6.158-virtual-review-20261011" ] || fail "review branch mismatch"
[ -z "$(git -C "$W" status --porcelain)" ] || fail "review worktree dirty"
[ -s "$LIST" ] || fail "missing 114-file conflict manifest"
[ "$(sha256sum "$W/$P" | cut -d' ' -f1)" = "$MERGED_SHA" ] || fail "RPMSG staged file differs from audited archive"
grep -Fq 'device_match_driver_override(dev, drv)' "$W/$P" || fail "expected automatic merge regression absent"
grep -Fq 'device_set_driver_override(dev, driver_override)' "$W/$P" || fail "expected automatic merge regression absent"
grep -Fq '<<<<<<< HEAD' "$W/$P" || fail "expected conflict absent"

# Inspect checkpoint RPMSG in git, not a possibly edited local copy.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
git -C "$BASE" show "HEAD:$P" > "$TMP"
[ "$(sha256sum "$TMP" | cut -d' ' -f1)" = "$BASE_SHA" ] || fail "compiled checkpoint RPMSG differs from archived F2"
grep -Fq 'static DEVICE_ATTR_RO(driver_override);' "$TMP" || fail "F2 read-only override missing"
if grep -Eq 'device_match_driver_override|device_set_driver_override' "$TMP"; then
  fail "compiled F2 still contains unavailable API"
fi

# The only changes in this file were the previously rejected
# generic driver-override migration. Keep exactly the compile-proven F2.
cp "$TMP" "$W/$P"
cmp "$TMP" "$W/$P" || fail "RPMSG copy mismatch"
git -C "$W" diff --check -- "$P" || fail "whitespace errors"
git -C "$W" add -- "$P"
[ "$(git -C "$W" diff --cached --name-only)" = "$P" ] || fail "unexpected staged paths"
git -C "$W" diff --cached --check || fail "staged whitespace errors"
git -C "$W" -c user.name="Annibale Kernel Port" \
  -c user.email="kernel-port@localhost" commit -m \
  "K1: preserve compiled ACK RPMSG F2 against unsupported stable auto-merge"

n=0
while IFS= read -r path || [ -n "$path" ]; do
  [ -n "$path" ] || continue
  if grep -q '^<<<<<<< ' "$W/$path"; then n=$((n + 1)); fi
done < "$LIST"
[ "$n" -eq 112 ] || fail "unexpected unresolved file count: $n"
[ "$(git -C "$BASE" rev-parse HEAD)" = "$BASE_HEAD" ] || fail "baseline HEAD modified"
[ -z "$(git -C "$BASE" status --porcelain)" ] || fail "baseline dirty"
[ -z "$(git -C "$W" status --porcelain)" ] || fail "review worktree dirty"

echo "K1_RPMSG_F2_RESTORED_COMPILED_BASELINE"
echo "K1_REMAINING_CONFLICT_FILES=$n"
echo "K1_REVIEW_HEAD=$(git -C "$W" rev-parse HEAD)"
echo "K1_BASELINE_PRESERVED=$(git -C "$BASE" rev-parse HEAD)"
echo "NOT_BUILDABLE_NOT_FLASHABLE"

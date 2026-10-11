#!/usr/bin/env bash
# EXPERIMENTAL: advance the stable 6.6.145 patch series, quarantine failures.
# Not a release, not a kernel build, and not equivalent to Linux v6.6.145.
set -Eeuo pipefail
ROOT="$HOME/annibale-kernel-port"
ACK="$ROOT/ack"
STAGING="$ROOT/staging-6.6.145"
REPORT="$ROOT/report-6.6.145"
COMMITS="$REPORT/commits.txt"
PREVIOUS="$REPORT/sequential-progress.tsv"
OUT="$REPORT/batch-progress.tsv"
FIRST="f344a2d77d47e5fad74e1b72399380b0a8f11fdc"

for f in "$ACK/.git" "$STAGING/Makefile" "$COMMITS" "$PREVIOUS"; do
  test -e "$f" || { echo "STOP: missing prerequisite: $f" >&2; exit 2; }
done
test "$(awk 'NR>1 && $2=="APPLIED"{n++}END{print n+0}' "$PREVIOUS")" -eq 11 || {
  echo 'STOP: staging does not match expected 11 applied patches.' >&2; exit 2;
}
test "$(awk '$2=="NEEDS_MANUAL_MERGE"{print $1;exit}' "$PREVIOUS")" = "$FIRST" || {
  echo 'STOP: first conflict changed. Do not resume blindly.' >&2; exit 2;
}
test "$(sed -n 's/^SUBLEVEL = //p' "$STAGING/Makefile" | head -1)" = 144 || {
  echo 'STOP: staging already reports newer version; cannot classify safely.' >&2; exit 2;
}
if [[ -e "$OUT" ]]; then
  echo "STOP: prior batch report exists; this script is intentionally non-reentrant." >&2
  exit 2
fi
printf 'sha\tresult\tsubject\n' > "$OUT"
printf '%s\n' "START: existing 11 patches preserved; all failures quarantined without aborting"
mkdir -p "$REPORT/deferred"
PATCH="$(mktemp "$ROOT/stable-patch.XXXXXXXX")"
trap 'rm -f "$PATCH"' EXIT
start=0
processed=0
added=0
quarantined=0
equiv=0
version_skipped=0
while IFS= read -r sha; do
  if [[ "$sha" == "$FIRST" ]]; then
    start=1
    echo "$sha: documented MediaTek btmtk source divergence, postponed"
  fi
  [[ $start -eq 1 ]] || continue
  subject="$(git -C "$ACK" log -1 --format=%s "$sha" | tr '\t' ' ')"
  ((processed+=1))
  if [[ "$sha" == "$FIRST" ]]; then
    result=DEFERRED_MTK_SOURCE_DIVERGENCE
    ((quarantined+=1))
  elif git -C "$ACK" diff-tree --no-commit-id --name-only -r "$sha" | grep -qx 'Makefile'; then
    # Do not give a partially updated kernel an upstream Linux version number.
    result=DEFERRED_LINUX_VERSION_PATCH
    ((version_skipped+=1))
  elif ! git -C "$ACK" show --format= --binary --no-ext-diff "$sha" > "$PATCH"; then
    result=DEFERRED_PATCH_READ_ERROR
    ((quarantined+=1))
  elif git -C "$STAGING" apply --check "$PATCH" >/dev/null 2>&1; then
    git -C "$STAGING" apply "$PATCH"
    result=APPLIED
    ((added+=1))
  elif git -C "$STAGING" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    result=REVERSE_PATCH_MATCH_CANDIDATE
    ((equiv+=1))
  else
    result=DEFERRED_NEEDS_PORT
    ((quarantined+=1))
    git -C "$ACK" diff-tree --no-commit-id --name-only -r "$sha" \
      > "$REPORT/deferred/$sha.paths"
    git -C "$STAGING" apply --check "$PATCH" \
      > "$REPORT/deferred/$sha.error" 2>&1 || true
  fi
  printf '%s\t%s\t%s\n' "$sha" "$result" "$subject" >> "$OUT"
  if ((processed % 150 == 0)); then
    printf 'PROGRESS=%s ADDED=%s DEFERRED=%s REVERSE_CANDIDATES=%s\n' \
      "$processed" "$added" "$quarantined" "$equiv"
  fi
done < "$COMMITS"
echo '==== EXPERIMENTAL 6.6.145 BACKPORT CLASSIFICATION ===='
printf 'EXISTING_APPLIED=11\nADDITIONAL_APPLIED=%s\nDEFERRED=%s\nREVERSE_MATCH=%s\nVERSION_PATCHES_DEFERRED=%s\n' \
  "$added" "$quarantined" "$equiv" "$version_skipped"
echo 'DEFERRED BY TOP-LEVEL PATH:'
awk '$2 ~ /^DEFERRED/' "$OUT" | cut -f1 | while read -r sha; do
  [[ -f "$REPORT/deferred/$sha.paths" ]] || continue
  cut -d/ -f1 "$REPORT/deferred/$sha.paths" | sort -u
done | sort | uniq -c | sort -nr | head -n 20 || true
echo "MAKEFILE_SUBLEVEL=$(sed -n 's/^SUBLEVEL = //p' "$STAGING/Makefile" | head -1)"
echo "REPORT=$OUT"
echo 'WARNING: INCOMPLETE BACKPORT SET; NOT LINUX 6.6.145; DO NOT BUILD/FLASH AS VERIFIED KERNEL.'

#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$HOME/annibale-kernel-port"
ACK="$ROOT/ack"
STAGING="$ROOT/staging-6.6.145"
REPORT="$ROOT/report-6.6.145"
COMMITS="$REPORT/commits.txt"
test -d "$ACK/.git" || { echo "STOP: ACK clone missing. Run preceding audit first."; exit 2; }
test -s "$COMMITS" || { echo "STOP: classification commit list missing."; exit 2; }
grep -qx 'KMI_GENERATION=8' "$ACK/build.config.common" || { echo "STOP: wrong ACK KMI."; exit 2; }
test "$(sed -n 's/^SUBLEVEL = //p' "$ACK/Makefile" | head -1)" = 144 || { echo "STOP: wrong ACK Linux sublevel."; exit 2; }
if [[ -e "$STAGING" ]]; then
  echo "STOP: staging worktree already exists at $STAGING. Do not overwrite an investigation."
  exit 2
fi
echo '[1/3] Create separate Linux patch integration worktree (original ACK unchanged)'
git -C "$ACK" worktree add --detach "$STAGING" HEAD
echo "ACK_BASE=$(git -C "$ACK" rev-parse HEAD)" > "$REPORT/sequential-baseline.txt"
printf 'sha\tresult\tsubject\n' > "$REPORT/sequential-progress.tsv"
PATCH="$(mktemp "$ROOT/patch.XXXXXXXX")"
trap 'rm -f "$PATCH"' EXIT
echo '[2/3] Apply stable 6.6.145 commits in historical order; stop at first unresolved conflict'
applied=0
already=0
while IFS= read -r sha; do
  test -n "$sha" || continue
  subject="$(git -C "$ACK" log -1 --format=%s "$sha" | tr '\t' ' ')"
  git -C "$ACK" show --format= --binary --no-ext-diff "$sha" > "$PATCH"
  if git -C "$STAGING" apply --check "$PATCH" >/dev/null 2>&1; then
    git -C "$STAGING" apply "$PATCH"
    printf '%s\tAPPLIED\t%s\n' "$sha" "$subject" >> "$REPORT/sequential-progress.tsv"
    ((applied+=1))
  elif git -C "$STAGING" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    printf '%s\tREVERSE_MATCH_CANDIDATE\t%s\n' "$sha" "$subject" >> "$REPORT/sequential-progress.tsv"
    ((already+=1))
  else
    printf '%s\tNEEDS_MANUAL_MERGE\t%s\n' "$sha" "$subject" >> "$REPORT/sequential-progress.tsv"
    cp "$PATCH" "$REPORT/first-sequential-conflict.patch"
    git -C "$STAGING" apply --check "$PATCH" > "$REPORT/first-sequential-error.txt" 2>&1 || true
    git -C "$ACK" diff-tree --no-commit-id --name-only -r "$sha" > "$REPORT/first-sequential-paths.txt"
    echo '[3/3] FIRST REAL SEQUENTIAL CONFLICT FOUND; staged files have not been overwritten'
    echo "COMMIT=$sha"
    echo "SUBJECT=$subject"
    echo "PREVIOUS_APPLIED=$applied"
    echo "REVERSE_MATCH_CANDIDATES=$already"
    echo 'CHANGED_PATHS:'
    head -n 15 "$REPORT/first-sequential-paths.txt"
    echo 'ERROR_EXCERPT:'
    head -n 16 "$REPORT/first-sequential-error.txt"
    echo "REPORT=$REPORT"
    echo "STAGING=$STAGING"
    exit 0
  fi
done < "$COMMITS"
echo '[3/3] All stable commits processed: manual verification still required'
echo "APPLIED=$applied"
echo "REVERSE_MATCH_CANDIDATES=$already"
echo "REPORT=$REPORT"
echo 'This worktree is experimental; do not compile/flash as a verified kernel without ABI review.'

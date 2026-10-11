#!/usr/bin/env bash
set -Eeuo pipefail
export GIT_TERMINAL_PROMPT=0
ROOT="$HOME/annibale-kernel-port"
ACK="$ROOT/ack"
REPORT="$ROOT/report-6.6.145"
mkdir -p "$ROOT" "$REPORT/rows"
printf '%s\n' '[1/4] Prepare official Google Android GKI 6.6 branch'
if [[ ! -d "$ACK/.git" ]]; then
  git clone --depth=1 --single-branch --branch android15-6.6-lts \
    https://android.googlesource.com/kernel/common.git "$ACK"
fi
if [[ $(sed -n 's/^SUBLEVEL = //p' "$ACK/Makefile" | head -1) != 144 ]] || \
   ! grep -qx 'KMI_GENERATION=8' "$ACK/build.config.common"; then
  echo 'STOP: unexpected ACK SUBLEVEL or KMI; no kernel was modified.' >&2
  exit 3
fi
if ! git -C "$ACK" remote get-url stable >/dev/null 2>&1; then
  git -C "$ACK" remote add stable https://github.com/gregkh/linux.git
fi
printf '%s\n' '[2/4] Fetch official Linux stable 6.6.144 and 6.6.145 with local blobs (avoids GitHub lazy-fetch-per-commit bottleneck)'
git -C "$ACK" -c protocol.version=2 fetch --depth=1500 --no-tags stable \
  refs/tags/v6.6.144:refs/tags/v6.6.144 \
  refs/tags/v6.6.145:refs/tags/v6.6.145
if ! git -C "$ACK" merge-base --is-ancestor 'v6.6.144^{commit}' 'v6.6.145^{commit}'; then
  echo 'STOP: stable tag ancestry missing, no modifications applied.' >&2
  exit 4
fi
printf '%s\n' '[3/4] Classify 6.6.145 commits independently (read-only ACK; 8 parallel workers)'
git -C "$ACK" rev-list --reverse --no-merges v6.6.144..v6.6.145 > "$REPORT/commits.txt"
export ACK REPORT
classify_commit() {
  local sha="$1" f="$REPORT/rows/$1" patch="$REPORT/rows/$1.patch" status subject
  subject="$(git -C "$ACK" log -1 --format=%s "$sha" | tr '\t' ' ')"
  if ! git -C "$ACK" show --format= --binary --no-ext-diff "$sha" > "$patch"; then
    status=ERROR_READ
  elif git -C "$ACK" apply --reverse --check "$patch" >/dev/null 2>&1; then
    status=PATCH_EQUIVALENT_CANDIDATE
  elif git -C "$ACK" apply --check "$patch" >/dev/null 2>&1; then
    status=APPLIES_IN_ISOLATION
  else
    status=NEEDS_ANDROID_TRIAGE
  fi
  printf '%s\t%s\t%s\n' "$sha" "$status" "$subject" > "$f"
  rm -f "$patch"
}
export -f classify_commit
xargs -r -P 8 -n 1 bash -c 'classify_commit "$1"' _ < "$REPORT/commits.txt"
cat "$REPORT"/rows/* > "$REPORT/classification.tsv"
wc -l "$REPORT/commits.txt" "$REPORT/classification.tsv"
printf '%s\n' '[4/4] Summary'
cut -f2 "$REPORT/classification.tsv" | sort | uniq -c
printf '%s\n' 'No upstream patch applied to ACK. No kernel image built. Inspect report before choosing backports.'
echo "REPORT=$REPORT"

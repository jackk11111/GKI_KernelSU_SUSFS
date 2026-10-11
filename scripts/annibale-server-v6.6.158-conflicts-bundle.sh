#!/usr/bin/env bash
# Read-only triage: 114 Linux 6.6.158 three-way conflicts.
set -Eeuo pipefail
R="$HOME/annibale-kernel-port"
S="$R/staging-6.6.145"
D="$R/report-6.6.158-direct"
M="$D/threeway-report.txt"
LIST="$D/conflict-files.txt"
BUNDLE="$HOME/ANNIBALE_6.6.158_CONFLICT_TRIAGE.tar.gz"
EXPECTED="831d9bce8"

echo "=== VERIFICA CHECKPOINT ==="
test "$(git -C "$S" rev-parse --short=9 HEAD)" = "$EXPECTED"
test -z "$(git -C "$S" status --porcelain)"
test -f "$M" && test -f "$LIST"
test "$(wc -l < "$LIST")" -eq 114
test "$(grep -c '^CONFLICT' "$M")" -eq 114
test ! -e "$BUNDLE" || { echo "STOP: archivio gia presente: $BUNDLE"; exit 2; }
for ref in v6.6.144 v6.6.158; do
  git -C "$S" rev-parse --verify "$ref^{commit}" >/dev/null
done
TREE="$(head -n 1 "$M" | tr -d '\r')"
test "$(git -C "$S" cat-file -t "$TREE")" = tree || {
  echo "STOP: albero virtuale non valido"
  exit 2
}

WORK="$(mktemp -d "$R/triage158.XXXXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK"/{android,linux144,linux158,merged,report}
cp "$M" "$WORK/report/threeway-report.txt"
cp "$LIST" "$WORK/report/conflict-files.txt"
cp "$D/overlap.txt" "$WORK/report/overlap.txt"
cp "$D/upstream-files.txt" "$WORK/report/upstream-files.txt"
cp "$D/android-port-files.txt" "$WORK/report/android-port-files.txt"
cat > "$WORK/report/README.txt" <<EOF
ANNIBALE LINUX 6.6.158 THREE-WAY TRIAGE
Android checkpoint: $EXPECTED (compiled)
Explicit base: Linux v6.6.144, not Git common ancestor
Incoming stable: Linux v6.6.158
Virtual tree: $TREE
Conflicting files: 114
android/: compiled Android GKI checkpoint
linux144/: Linux v6.6.144
linux158/: Linux v6.6.158
merged/: virtual result with possible conflict markers
*.ABSENT: missing file in corresponding version
NOT ABI verified. NOT flashable.
EOF

echo "=== RACCOLTA 114 FILE ==="
i=0
while IFS= read -r file || [[ -n "$file" ]]; do
  [[ -n "$file" ]] || continue
  case "$file" in
    /*|../*|*/../*|*/..) echo "STOP: percorso inatteso"; exit 3 ;;
  esac
  for spec in "HEAD:android" "v6.6.144:linux144" "v6.6.158:linux158" "$TREE:merged"; do
    ref="$(printf %s "$spec" | cut -d: -f1)"
    subdir="$(printf %s "$spec" | cut -d: -f2)"
    target="$WORK/$subdir/$file"
    mkdir -p "$(dirname "$target")"
    if git -C "$S" cat-file -e "$ref:$file" 2>/dev/null; then
      git -C "$S" show "$ref:$file" > "$target"
    else
      printf 'ABSENT in %s: %s\n' "$ref" "$file" > "$target.ABSENT"
    fi
  done
  ((i+=1))
  if ((i % 25 == 0)); then echo "FILE_RACCOLTI=$i"; fi
done < "$LIST"
test "$i" -eq 114

echo "=== ARCHIVIO ==="
tar -czf "$BUNDLE" -C "$WORK" .
test -s "$BUNDLE"
sha256sum "$BUNDLE"
ls -lh "$BUNDLE"
test "$(git -C "$S" rev-parse --short=9 HEAD)" = "$EXPECTED"
test -z "$(git -C "$S" status --porcelain)"
echo "KERNEL_COMPILATO_INALTERATO"
echo "TRIAGE_6.6.158_PRONTO"

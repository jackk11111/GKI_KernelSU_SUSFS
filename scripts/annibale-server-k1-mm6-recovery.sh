#!/usr/bin/env bash
# K1 6-file semantic batch: mm/internal.h + mm/migrate_device.c + 4 matched v6.6.158 MM selftests.
# Source preflight is atomic, compiled ACK checkpoint/Android ROM left untouched.
set -Eeuo pipefail
R="$HOME/annibale-kernel-port"
B="$R/staging-6.6.145"
W="$R/staging-6.6.158-virtual-review"
D="$R/report-6.6.158-direct"
START="4fb89f2e179f23b447b56878febfe15025ecb27d"
BASE="831d9bce8371e23466e06129d1fbfcb6eadc1979"
PREPORT="712c2cd5c"
fail() { printf 'STOP: %s\n' "$*" >&2; exit 2; }
echo "=== K1 MM6: exact checkpoint guards ==="
[ "$(git -C "$W" rev-parse HEAD)" = "$START" ] || fail "review HEAD changed or script already used"
[ "$(git -C "$B" rev-parse HEAD)" = "$BASE" ] || fail "compiled baseline HEAD changed"
[ -z "$(git -C "$W" status --porcelain)" ] || fail "review worktree dirty"
[ -z "$(git -C "$B" status --porcelain)" ] || fail "compiled baseline dirty"
[ "$(git -C "$W" branch --show-current)" = "annibale-6.6.158-virtual-review-20261011" ] || fail "unexpected branch"
[ "$(wc -l < "$D/conflict-files.txt")" -eq 114 ] || fail "missing original conflict list"
git -C "$B" cat-file -e "$PREPORT^{commit}" || fail "preport base missing"
git -C "$B" cat-file -e 'v6.6.158^{commit}' || fail "stable tag missing"
T="$(mktemp -d "$R/k1-mm6.XXXXXXXX")"
trap 'rm -rf "$T"' EXIT
cat > "$T/manifest.txt" <<'MANIFEST'
internal|mm/internal.h|80729c1365fc7ce08163b12623160b66a5bd9c3887204e496c02b92eed3ccbfd|a2e381fe6100216d9208a424dbf863bf304cd077feca61986e42e7e26e03b470|1
migrate|mm/migrate_device.c|6badfeb094683a336d6c6ebbcc45c86f18a24910b3a76a2d95ec05376dc3e4b7|89d2850d3ee68cf2621b119ebe5019ddf4bd4b6f2d4b6068151f17593b87cf86|2
stable|tools/testing/selftests/mm/cow.c|527edb0f9611ec09467ab61848c30fd8b56e0ca182d960fa11ecc681daa9930a|d27ede03d1934cb1b80a9cc0461b3c7e2ceddf2f86d2478e9bcb8a1089529132|4
stable|tools/testing/selftests/mm/khugepaged.c|4e0faa45fe1f301573e78f2e4d634fdc864dff188c9d5665307cfe9f6dfca2da|f30351322f32a4be2ed773b828d51852b298db6b22094f9ae7475aaaffd450ac|3
stable|tools/testing/selftests/mm/thp_settings.c|5378cb61828026903a63847fa9cec26b0f14af1efe41e1c0f89ad46d6f031b76|d76d23b5929719062598ad7d539091f255ac3555feba7f77e344e30ee4eab41f|8
stable|tools/testing/selftests/mm/thp_settings.h|ebb180b356434c6d637ea361400b640e8b0f7306b06f281ef4addd951ee7755b|256e20b6c2b26f225bae09f90885cdeb6a765de01498d06fd07095518863ca70|4
MANIFEST

python3 - "$W" "$B" "$T" <<'PY'
from pathlib import Path
import sys,re,hashlib,subprocess
w=Path(sys.argv[1]); b=Path(sys.argv[2]); temp=Path(sys.argv[3])
rows=[x.split("|") for x in (temp/"manifest.txt").read_text().splitlines() if x]
assert len(rows)==6 and len({r[1] for r in rows})==6, "bad manifest"
marker=re.compile(rb"(?ms)^<<<<<<< HEAD\n(.*?)^=======\n(.*?)^>>>>>>> v6\.6\.158\n")
for mode,path,before,after,n in rows:
    merged=(w/path).read_bytes()
    assert hashlib.sha256(merged).hexdigest()==before, "preimage mismatch "+path
    hunks=list(marker.finditer(merged))
    assert len(hunks)==int(n), "conflict structure mismatch "+path
    if mode=="stable":
        result=subprocess.check_output(["git","-C",str(b),"show",f"v6.6.158:{path}"])
        if path.endswith("thp_settings.h"):
            assert b"enum shmem_enabled" in result
        if path.endswith("thp_settings.c"):
            assert b"thp_shmem_supported_orders" in result
    elif mode=="internal":
        assert len(hunks)==1 and b"walk_page_range_debug" in hunks[0].group(2)
        result=merged[:hunks[0].start()]+hunks[0].group(1)+b"\n"+hunks[0].group(2)+merged[hunks[0].end():]
        assert b"#define SRC_PAGE_USAGE_MASK" in result
        assert result.count(b"int walk_page_range_debug(")==1
        assert result.count(b"static inline bool can_modify_vma(")==2
        assert result.count(b"#endif\t/* __MM_INTERNAL_H */")==1
    elif mode=="migrate":
        result=marker.sub(lambda m:m.group(1),merged)
        ack=subprocess.check_output(["git","-C",str(b),"show",f"HEAD:{path}"])
        assert result==ack, "the compiled ACK source changed "+path
        src=b'\t\t\tflush_cache_page(vma, addr, pte_pfn(pte));'
        dst=b'\t\t\tif (pte_present(pte))\n\t\t\t\tflush_cache_page(vma, addr, pte_pfn(pte));'
        assert result.count(src)==1
        result=result.replace(src,dst)
        src=b'\t\t\tif (pte_dirty(pte))\n\t\t\t\tfolio_mark_dirty(folio);'
        dst=b'\t\t\tif (pte_present(pte) && pte_dirty(pte))\n\t\t\t\tfolio_mark_dirty(folio);'
        assert result.count(src)==1
        result=result.replace(src,dst)
        assert result.count(b"if (pte_present(pte))\n\t\t\t\tflush_cache_page")==1
    else:
        raise AssertionError("unexpected mode "+mode)
    assert b"<<<<<<< HEAD" not in result and b">>>>>>> v6.6.158" not in result, "unresolved markers "+path
    assert hashlib.sha256(result).hexdigest()==after, "postimage mismatch "+path
    dest=temp/"prepared"/path
    dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_bytes(result)
print("K1_MM6_ALL_6_PRECHECK_OK")
PY

commit_files() {
  local msg="$1"; shift
  local paths=("$@")
  for f in "${paths[@]}"; do cp "$T/prepared/$f" "$W/$f"; done
  git -C "$W" add -- "${paths[@]}"
  [ "$(git -C "$W" diff --cached --name-only | wc -l)" -eq "${#paths[@]}" ] || fail "unexpected staged paths"
  git -C "$W" diff --cached --check || fail "staged whitespace error"
  git -C "$W" -c user.name="Annibale Kernel Port" -c user.email="kernel-port@localhost" commit -m "$msg"
}

echo "=== Memory core: keep ACK migration and add present-PTE guards ==="
commit_files "K1: merge safe migrate_device PTE guards and pagewalk declaration" \
  mm/internal.h mm/migrate_device.c

echo "=== Selftests: align four related files to upstream v6.6.158 ==="
commit_files "K1: align COW and THP memory selftests to genuine Linux v6.6.158" \
  tools/testing/selftests/mm/cow.c \
  tools/testing/selftests/mm/khugepaged.c \
  tools/testing/selftests/mm/thp_settings.c \
  tools/testing/selftests/mm/thp_settings.h

echo "=== Count original conflict paths and guard baseline ==="
count=0
while IFS= read -r f || [ -n "$f" ]; do
 [ -n "$f" ] || continue
 if grep -q '^<<<<<<< ' "$W/$f"; then count=$((count+1)); fi
done < "$D/conflict-files.txt"
[ "$count" -eq 33 ] || fail "expected 33 unresolved original conflicts, got $count"
[ "$(git -C "$B" rev-parse HEAD)" = "$BASE" ] || fail "compiled baseline changed"
[ -z "$(git -C "$B" status --porcelain)" ] || fail "compiled baseline dirty"
[ -z "$(git -C "$W" status --porcelain)" ] || fail "review tree dirty"
echo "K1_MM6_RESOLVED_REMAINING_33"
echo "K1_REVIEW_HEAD=$(git -C "$W" rev-parse HEAD)"
echo "K1_BASELINE_PRESERVED=$BASE"

echo '=== Portable recovery archive before server expiration ==='
SHORT="$(git -C "$W" rev-parse --short=9 HEAD)"
OUT="$HOME/ANNIBALE_KERNEL_K1_RECOVERY_20261012_${SHORT}.tar.gz"
[ ! -e "$OUT" ] || fail "archive already exists"
mkdir -p "$T/recovery"
git -C "$B" diff --binary "$PREPORT" "$BASE" | gzip -1 > "$T/recovery/01_preport_to_compiled.patch.gz"
git -C "$B" diff --binary "$BASE" "$(git -C "$W" rev-parse HEAD)" | gzip -1 > "$T/recovery/02_compiled_to_review.patch.gz"
[ -s "$T/recovery/01_preport_to_compiled.patch.gz" ] || fail "missing recovery delta 01"
[ -s "$T/recovery/02_compiled_to_review.patch.gz" ] || fail "missing recovery delta 02"
cp "$D/conflict-files.txt" "$D/threeway-report.txt" "$T/recovery/"
cp "$T/manifest.txt" "$T/recovery/mm6-manifest.txt"
cp "$R/out-checkpoint-ABCDE/arch/arm64/boot/Image" "$T/recovery/compiled-Image"
cp "$R/out-checkpoint-ABCDE/Module.symvers" "$T/recovery/compiled-Module.symvers"
cp "$R/out-checkpoint-ABCDE/.config" "$T/recovery/compiled-config"
cat > "$T/recovery/README.txt" <<EOF
ANNIBALE K1 experimental Linux 6.6.158 review; NOT BUILDABLE / NOT FLASHABLE.
Preport base SHA: $(git -C "$B" rev-parse "$PREPORT")
Compiled partial checkpoint SHA: $BASE
Review WIP SHA: $(git -C "$W" rev-parse HEAD)
To reconstruct start EXACTLY at preport and apply patch 01, then patch 02.
33 conflicts remain plus unchecked auto merges and OEM module ABI.
Included Image is older partial port and is NOT Linux 6.6.158.
EOF
(cd "$T/recovery" && sha256sum *.patch.gz compiled-* > SHA256SUMS)
tar -czf "$OUT.tmp" -C "$T/recovery" .
mv "$OUT.tmp" "$OUT"
sha256sum "$OUT"
ls -lh "$OUT"
echo "K1_RECOVERY_READY=$OUT"
echo "K1_33_REMAIN_NOT_BUILDABLE_NOT_FLASHABLE"
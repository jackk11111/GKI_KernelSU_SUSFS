#!/usr/bin/env bash
# K1 next 10 conflicts, two review commits, new portable source backup.
# ONLY isolated experimental tree; no kernel/ROM build or flashing.
set -Eeuo pipefail
R="$HOME/annibale-kernel-port"
B="$R/staging-6.6.145"
W="$R/staging-6.6.158-virtual-review"
D="$R/report-6.6.158-direct"
PREPORT="712c2cd5c"
EXPECTED_REVIEW="f264937a2dafbafab059168b22582541a58535bd"
EXPECTED_BASE="831d9bce8371e23466e06129d1fbfcb6eadc1979"
fail(){ echo "STOP: $*" >&2; exit 2; }
echo '=== K1 NEXT10: strict starting checkpoint ==='
[ "$(git -C "$B" rev-parse HEAD)" = "$EXPECTED_BASE" ] || fail "compiled baseline HEAD changed"
[ -z "$(git -C "$B" status --porcelain)" ] || fail "compiled baseline dirty"
[ "$(git -C "$W" rev-parse HEAD)" = "$EXPECTED_REVIEW" ] || fail "review HEAD differs (already run?)"
[ "$(git -C "$W" branch --show-current)" = "annibale-6.6.158-virtual-review-20261011" ] || fail "review branch mismatch"
[ -z "$(git -C "$W" status --porcelain)" ] || fail "review worktree dirty"
[ -s "$D/conflict-files.txt" ] || fail "missing conflict manifest"
git -C "$B" cat-file -e "$PREPORT^{commit}" || fail "preport base unavailable"
T="$(mktemp -d "$R/k1-next10.XXXXXXXX")"
trap 'rm -rf "$T"' EXIT
cat > "$T/manifest.txt" <<'MANIFEST'
upstream|drivers/hid/hid-magicmouse.c|144939ebf6635347bf8a109fee7adfadb336f67e211d15d6c071648e0fb5c95f|903f9bcba775086515ebd24f21b18be1110be3f2a133b5853c337a1ead076b92|2
upstream|drivers/staging/rtl8723bs/core/rtw_ieee80211.c|9a1d2e724c04f177937e07a4854e8aac62d8262aa90e57c792af7007192f48c2|7ee885d3aaad15a94a4da8d96658846d65febb58178b9da6d52a30d5e4d46db5|1
upstream|drivers/virtio/virtio_balloon.c|f02f56a278f4f857d4b1680dbbf9c5af3c4b850b4786a8c1f52928edc0b8a86c|6e7088d1ac15e54a531995f85b553251a4f3c94c918dd3bf9e6ad0ecc40481ac|1
upstream|kernel/stop_machine.c|41222e66ddf77ea9c973bf479ab5b825a807e24404d6a981387042fdcd08b0c3|1689b8266e06faeeb4512b2c0fc3f8da97ed8754ade7fe67dd21b1d6dd6dc3ac|1
upstream|fs/smb/server/vfs_cache.c|56ea99a2074c6b770bc4103928f7e958f79c4acc3d34997a565c367d9705c3cc|fb8606966c394c2a8de22d2df5c50d0451e766189cc15e5b1b5669dcc2554b06|1
upstream|drivers/platform/x86/amd/pmc/pmc.c|f6d21b16c6ad51d3b3382617d12434345a7d4733fc1e04c4146a6f7b68830f86|4cc16e818880a31f9087d3eae51f0cc7f7fd8dad0f770388f92ac832e8eccdcb|2
upstream|drivers/net/ethernet/marvell/octeontx2/nic/otx2_pf.c|4e5ce837f260e392ef9748e69352a3cced0f05a396614d9e991fb4ca1c816eff|4f0fe56595a8fb268107eb1ee569b4f1ac308852bac779e1a3d5ba0c02bd5d9d|1
android|drivers/clk/clk-scmi.c|cce65aacb17e12be1cb74345fe88b3f120c448afaec7ae27cb494b3cd0d6912a|8b141f5f7d8e409095fe467029905d2d0fcaae055bcbc0a49670f663af777ace|1
android|kernel/bpf/bpf_lsm.c|532d37638d9f2e8f586e1b21455237812a2101810318c101ec0f53b8de79eaf1|b02f62cff99ec0ce40d3984903ed8db106f5d9828a1732a21f56afa3125695ac|1
upstream|net/core/gro.c|dbe46d4f587d0849886373ca8bc220b48d2c5e7ae411c3bf3ba9071001e0054d|c0af50c0539f1f6fd01490dcd7eeb8f843c9e05c71136dbd28df2dd88fffb164|1
MANIFEST
python3 - "$W" "$T" <<'PY'
from pathlib import Path
import hashlib,re,sys
w=Path(sys.argv[1]); t=Path(sys.argv[2])
r=[line.split("|") for line in (t/"manifest.txt").read_text().splitlines() if line]
assert len(r)==10 and len({x[1] for x in r})==10
pat=re.compile(rb"(?ms)^<<<<<<< HEAD\n(.*?)^=======\n(.*?)^>>>>>>> v6\.6\.158\n")
for mode,path,sha_old,sha_new,count in r:
    source=(w/path).read_bytes()
    assert hashlib.sha256(source).hexdigest()==sha_old, "original differs: "+path
    matches=list(pat.finditer(source))
    assert len(matches)==int(count), "unexpected conflict count: "+path
    if mode=="android":
        assert all(not m.group(2) for m in matches), "upstream side not empty: "+path
    fixed=pat.sub(lambda m: m.group(2) if mode=="upstream" else m.group(1),source)
    assert b"<<<<<<< " not in fixed and b">>>>>>> " not in fixed, "markers remain: "+path
    assert hashlib.sha256(fixed).hexdigest()==sha_new, "unexpected resolved bytes: "+path
    dest=t/"prepared"/path
    dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_bytes(fixed)
# Specific semantic preflight for already present APIs used in the fixes.
hid=(t/"prepared/drivers/hid/hid-magicmouse.c").read_bytes()
assert hid.count(b"__magicmouse_raw_event(")>=3
clk=(t/"prepared/drivers/clk/clk-scmi.c").read_bytes()
assert b"#define NOT_ATOMIC" in clk and clk.count(b"NOT_ATOMIC")>=2
print("K1_NEXT10_PRECHECK_ALL_OK")
PY

echo '=== Apply eight upstream stable fixes ==='
mapfile -t UP < <(awk -F'|' '$1=="upstream"{print $2}' "$T/manifest.txt")
[ "${#UP[@]}" -eq 8 ] || fail "expected eight stable files"
for p in "${UP[@]}"; do cp "$T/prepared/$p" "$W/$p"; done
git -C "$W" add -- "${UP[@]}"
git -C "$W" diff --cached --check || fail "whitespace stable"
[ "$(git -C "$W" diff --cached --name-only | wc -l)" -eq 8 ] || fail "staged unexpected paths"
git -C "$W" -c user.name="Annibale Kernel Port" -c user.email="kernel-port@localhost" \
    commit -m "K1: integrate independent stable fixes HID GRO Virtio stop_machine SMB and drivers"

echo '=== Preserve two Android-specific cases ==='
mapfile -t AND < <(awk -F'|' '$1=="android"{print $2}' "$T/manifest.txt")
[ "${#AND[@]}" -eq 2 ] || fail "expected two Android files"
for p in "${AND[@]}"; do cp "$T/prepared/$p" "$W/$p"; done
git -C "$W" add -- "${AND[@]}"
git -C "$W" diff --cached --check || fail "whitespace Android"
[ "$(git -C "$W" diff --cached --name-only | wc -l)" -eq 2 ] || fail "unexpected Android staged paths"
git -C "$W" -c user.name="Annibale Kernel Port" -c user.email="kernel-port@localhost" \
    commit -m "K1: preserve ACK SCMI atomic flags and BPF LSM BTF selfattr"

n=0
while IFS= read -r path || [ -n "$path" ]; do
  [ -n "$path" ] || continue
  if grep -q '^<<<<<<< ' "$W/$path"; then n=$((n+1)); fi
done < "$D/conflict-files.txt"
[ "$n" -eq 90 ] || fail "unresolved count not 90: $n"
[ "$(git -C "$B" rev-parse HEAD)" = "$EXPECTED_BASE" ] || fail "baseline modified"
[ -z "$(git -C "$B" status --porcelain)" ] || fail "baseline dirty"
[ -z "$(git -C "$W" status --porcelain)" ] || fail "review dirty"
echo "K1_NEXT10_RESOLVED_REMAINING_90"
echo "K1_REVIEW_HEAD=$(git -C "$W" rev-parse HEAD)"

echo '=== Updated server-expiration recovery archive ==='
SHA="$(git -C "$W" rev-parse --short=9 HEAD)"
OUT="$HOME/ANNIBALE_KERNEL_K1_RECOVERY_20261011_${SHA}.tar.gz"
[ ! -e "$OUT" ] || fail "recovery already exists"
mkdir -p "$T/recovery"
git -C "$B" diff --binary "$PREPORT" "$EXPECTED_BASE" | gzip -1 > "$T/recovery/01_preport_to_compiled_checkpoint.patch.gz"
git -C "$B" diff --binary "$EXPECTED_BASE" "$(git -C "$W" rev-parse HEAD)" | gzip -1 > "$T/recovery/02_compiled_to_review_6.6.158.patch.gz"
test -s "$T/recovery/01_preport_to_compiled_checkpoint.patch.gz"
test -s "$T/recovery/02_compiled_to_review_6.6.158.patch.gz"
cp "$D/conflict-files.txt" "$D/threeway-report.txt" "$T/recovery/"
cp "$T/manifest.txt" "$T/recovery/next10-resolution-manifest.txt"
cp "$R/out-checkpoint-ABCDE/arch/arm64/boot/Image" "$T/recovery/compiled-checkpoint-Image"
cp "$R/out-checkpoint-ABCDE/Module.symvers" "$T/recovery/compiled-checkpoint-Module.symvers"
cp "$R/out-checkpoint-ABCDE/.config" "$T/recovery/compiled-checkpoint-config"
cat > "$T/recovery/README.txt" <<EOF
ANNIBALE port K1 experimental recovery, NEVER FLASH
Exact preport base: $(git -C "$B" rev-parse "$PREPORT")
Compiled baseline: $EXPECTED_BASE
K1 review WIP: $(git -C "$W" rev-parse HEAD)
Source recovery uses exact base, then patch 01, then 02.
This review snapshot STILL CONTAINS 90 unresolved conflicts and unverified auto-merges.
Compiled Image is the previous partial 6.6.145 port, NOT stable 6.6.158.
EOF
(cd "$T/recovery" && sha256sum *.patch.gz compiled-checkpoint-* > SHA256SUMS)
tar -czf "$OUT.tmp" -C "$T/recovery" .
mv "$OUT.tmp" "$OUT"
sha256sum "$OUT"
ls -lh "$OUT"
echo "K1_LATEST_RECOVERY_READY=$OUT"
echo "K1_BASELINE_PRESERVED=$EXPECTED_BASE"
echo 'K1_90_REMAIN_NOT_BUILDABLE_NOT_FLASHABLE'

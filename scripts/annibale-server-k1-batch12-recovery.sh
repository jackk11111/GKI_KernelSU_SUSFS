#!/usr/bin/env bash
# K1 batch 1 (12 independently audited conflicted files) + portable recovery.
# Current HEAD must be post Binder + RPMSG F2; baseline remains untouched.
set -Eeuo pipefail

R="$HOME/annibale-kernel-port"
B="$R/staging-6.6.145"
W="$R/staging-6.6.158-virtual-review"
D="$R/report-6.6.158-direct"
START="5c216ae964f76a5b65e9e65e7139defa56339562"
BASE="831d9bce8371e23466e06129d1fbfcb6eadc1979"
PREPORT="712c2cd5c"
fail() { echo "STOP: $*" >&2; exit 2; }

echo "=== K1 BATCH: baseline guards ==="
[ "$(git -C "$B" rev-parse HEAD)" = "$BASE" ] || fail "baseline changed"
[ -z "$(git -C "$B" status --porcelain)" ] || fail "baseline dirty"
[ "$(git -C "$W" rev-parse HEAD)" = "$START" ] || fail "review HEAD not expected (already run?)"
[ "$(git -C "$W" branch --show-current)" = "annibale-6.6.158-virtual-review-20261011" ] || fail "review branch mismatch"
[ -z "$(git -C "$W" status --porcelain)" ] || fail "review worktree dirty"
[ -s "$D/conflict-files.txt" ] || fail "missing conflict list"
git -C "$B" cat-file -e "$PREPORT^{commit}" || fail "pre-port baseline unavailable"

T="$(mktemp -d "$R/k1-batch12.XXXXXXXX")"
trap 'rm -rf "$T"' EXIT
cat >"$T/manifest.txt" <<'MANIFEST'
upstream|drivers/crypto/atmel-ecc.c|fb88ebfa6f75f1fbfe0971a7fdf510ff2f5a6e39ab3c442334f167a3375ae6e2|42cbf0a49657affa2f19c0d315c1a34344992633191491d9f07f577fdcf4eac1|1
upstream|drivers/dma-buf/udmabuf.c|849cae996dc629622a09bfc2d0c9e0005444c1782869a585ad1d7ed527ab24e7|d97caa601208c19fe82d8464c06b756a857c8e24f1d0d0c0def563f19cb35a41|1
upstream|drivers/spi/spi-dw.h|f544ea66e4cc19771ac0900ac2d1ea3b1d31ba7b59594d06f890612364f83b66|7c8639283659323028d35c3197755e886fa3da49fd801069248740a822a67470|1
upstream|drivers/gpu/host1x/bus.c|b0186ae0c872265e1830d53f863391c225b4d597b28277e88ae0aad88f7e46cc|b1f98dfbcaa626037b686e9194754a38689eeb712b56b1316b5041e68436ef66|1
upstream|drivers/hid/hid-logitech-dj.c|ef2194b35bcaef9160fa8c1327d5327c7623ed46e473ecd849b0594ba6fe1a72|7259c956a11db664a6638e34d88cdf33a28da6a3d61106cce2aea8c1def89635|1
upstream|fs/proc/namespaces.c|9086e088ea806907673c44ac632112c19f06286b2f48244b2aaff720c12691f5|2861742ada7fb7861b4973ba5c896d8113d300b0db291f59a69cb0ecd648ab49|2
upstream|net/ipv4/ip_gre.c|484e90878a7eda8de13111d786b0c36a0795d8719bc88be26cbd4d7f0895ad88|dada5b3acbda00b3d8d041f5696eb48bc4f81380f0bcd06f58733fd8148e055b|2
android|drivers/bus/imx-weim.c|a126b57e419a6d762275500fcb1d95df667772822bf8180622b6ad7087e132c1|c108162ce72cfc472c184d55dcef9c48c7554c25cfe1e45177c781b614444372|1
android|drivers/i2c/i2c-core-of.c|fe59f31746084b812b2cccce5eff19a1e4c053957ed4449fc0b50d7115e96baa|b5934c763b599fed8acc765e368b1e33c02b2979ad15a5d8e4bfd83603ffe5b0|1
android|drivers/of/dynamic.c|ab4b1aa21009495c78ba1500c8f2c569ddd3eb8f28b07d7d715e545800a76a29|3a94f13feb0cb9dc61e5d5c147296d28c4b5fda7c921b421a0f7dbeaa7af6efc|1
android|drivers/of/platform.c|e5f689e601cc93c739079ac02bc29be1dcd173b222ef86b5c8b6a5f8ef67a2f3|e3a3992c64286f094c1ec3a6c76bd6e74ee4b5ce493e7a523982ac34f97a7cd3|1
android|drivers/spi/spi.c|fb1200dc57d428702226d0bb7296918b75b19be65529776fb4fc4a0b5c5e75c3|539f5db871c0846b69187a6a3fd342b5a9f51c6fd4488a4fb2bd8551dc0b6cb0|1
MANIFEST

# Preflight all 12 files before changing any source. sha256s measured
# against original 114-file tar bundle, including expected outputs.
python3 - "$W" "$T" <<'PY'
import sys,re,hashlib,pathlib,os
w=pathlib.Path(sys.argv[1]); tmp=pathlib.Path(sys.argv[2])
pat=re.compile(rb"(?ms)^<<<<<<< HEAD\n(.*?)^=======\n(.*?)^>>>>>>> v6\.6\.158\n")
rows=[x.split("|") for x in (tmp/"manifest.txt").read_text().splitlines() if x.strip()]
assert len(rows)==12 and len({r[1] for r in rows})==12, "manifest count/duplicates"
for mode,path,old_sha,new_sha,count in rows:
    original=(w/path).read_bytes()
    assert hashlib.sha256(original).hexdigest()==old_sha, "preimage mismatch: "+path
    matches=list(pat.finditer(original))
    assert len(matches)==int(count), "unexpected conflict pattern: "+path
    if mode=="android":
        assert all(m.group(2)==b"" for m in matches), "incoming nonempty: "+path
    if mode=="upstream" and path not in ("drivers/hid/hid-logitech-dj.c","drivers/gpu/host1x/bus.c"):
        assert all(m.group(1)==b"" for m in matches), "conflicting Android content: "+path
    target=pat.sub(lambda m: m.group(2) if mode=="upstream" else m.group(1),original)
    assert b"<<<<<<< " not in target and b">>>>>>> " not in target, "remaining markers: "+path
    assert hashlib.sha256(target).hexdigest()==new_sha, "postimage mismatch: "+path
    dst=tmp/"prepared"/path; dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(target)
print("K1_BATCH_PRECHECK_ALL_12_OK")
PY

echo '=== Commit independent upstream stable fixes (7 files) ==='
mapfile -t UP < <(awk -F'|' '$1=="upstream"{print $2}' "$T/manifest.txt")
for p in "${UP[@]}"; do cp "$T/prepared/$p" "$W/$p"; done
git -C "$W" add -- "${UP[@]}"
git -C "$W" diff --cached --check || fail "upstream batch whitespace errors"
[ "$(git -C "$W" diff --cached --name-only | wc -l)" -eq 7 ] || fail "unexpected upstream staged files"
git -C "$W" -c user.name="Annibale Kernel Port" -c user.email="kernel-port@localhost" commit -m "K1: batch stable fixes (HID DMA SPI proc GRE host1x Atmel)"

echo '=== Commit FWNODE dynamic device coherence (5 files) ==='
mapfile -t AND < <(awk -F'|' '$1=="android"{print $2}' "$T/manifest.txt")
for p in "${AND[@]}"; do cp "$T/prepared/$p" "$W/$p"; done
git -C "$W" add -- "${AND[@]}"
git -C "$W" diff --cached --check || fail "fwnode batch whitespace errors"
[ "$(git -C "$W" diff --cached --name-only | wc -l)" -eq 5 ] || fail "unexpected FWNODE staged files"
git -C "$W" -c user.name="Annibale Kernel Port" -c user.email="kernel-port@localhost" commit -m "K1: preserve Android dynamic FWNODE flags across five consumers"

echo '=== Verify conflict progress ==='
N=0
while IFS= read -r p || [ -n "$p" ]; do
    [ -n "$p" ] || continue
    if grep -q '^<<<<<<< ' "$W/$p"; then N=$((N+1)); fi
done < "$D/conflict-files.txt"
[ "$N" -eq 100 ] || fail "unexpected remaining conflicts: $N"
[ "$(git -C "$B" rev-parse HEAD)" = "$BASE" ] || fail "baseline unexpectedly changed"
[ -z "$(git -C "$B" status --porcelain)" ] || fail "baseline dirty"
[ -z "$(git -C "$W" status --porcelain)" ] || fail "review worktree dirty"
echo "K1_BATCH_RESOLVED_12_REMAINING_100"
echo "K1_REVIEW_HEAD=$(git -C "$W" rev-parse HEAD)"
echo "K1_BASELINE_PRESERVED=$BASE"

# Archive portable source deltas and compiled checkpoint before ServerHive expires.
# These binary-safe diffs require the exact original ACK baseline SHA to restore.
echo '=== Create server-expiration recovery archive ==='
OUT="$HOME/ANNIBALE_KERNEL_K1_RECOVERY_20261011_$(git -C "$W" rev-parse --short=9 HEAD).tar.gz"
[ ! -e "$OUT" ] || fail "recovery archive already exists"
mkdir -p "$T/recovery"
git -C "$B" diff --binary "$PREPORT" "$BASE" | gzip -1 > "$T/recovery/01_preport_to_compiled_checkpoint.patch.gz"
git -C "$B" diff --binary "$BASE" "$(git -C "$W" rev-parse HEAD)" | gzip -1 > "$T/recovery/02_compiled_to_review_6.6.158.patch.gz"
[ -s "$T/recovery/01_preport_to_compiled_checkpoint.patch.gz" ] || fail "missing baseline source patch"
[ -s "$T/recovery/02_compiled_to_review_6.6.158.patch.gz" ] || fail "missing review source patch"
cp "$D/conflict-files.txt" "$T/recovery/"
cp "$D/threeway-report.txt" "$T/recovery/"
cp "$T/manifest.txt" "$T/recovery/12-file-resolution-manifest.txt"
cp "$R/out-checkpoint-ABCDE/arch/arm64/boot/Image" "$T/recovery/compiled-checkpoint-Image"
cp "$R/out-checkpoint-ABCDE/Module.symvers" "$T/recovery/compiled-checkpoint-Module.symvers"
cp "$R/out-checkpoint-ABCDE/.config" "$T/recovery/compiled-checkpoint-config"
cat > "$T/recovery/README.txt" <<EOF
EVOX ANNIBALE KERNEL SOURCE RECOVERY / NOT FLASHABLE
Base ACK/android15-6.6-lts preport SHA: $(git -C "$B" rev-parse "$PREPORT")
Compiled Android checkpoint SHA: $BASE
Review WIP SHA: $(git -C "$W" rev-parse HEAD)
Source recovery requires exact base commit, then patch 01 and patch 02 IN ORDER.
Patch 02 contains 100 UNRESOLVED conflict files and auto-merged code NOT ABI validated.
Included Image/modules from preport partial compile, NOT kernel Linux 6.6.158.
Do not flash.
EOF
(cd "$T/recovery" && sha256sum *.patch.gz compiled-checkpoint-* > SHA256SUMS)
tar -czf "$OUT.tmp" -C "$T/recovery" .
mv "$OUT.tmp" "$OUT"
sha256sum "$OUT"
ls -lh "$OUT"
echo "K1_RECOVERY_READY=$OUT"
echo "K1_PROGRESS_100_CONFLICTS_LEFT_NOT_BUILDABLE_NOT_FLASHABLE"

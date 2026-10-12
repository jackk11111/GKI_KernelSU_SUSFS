#!/usr/bin/env bash
# K1 batch 7: independent reviewed kernel stable/ACK integrations.
# Preflight atomic: no source modifications unless all 7 SHA-pinned outputs match.
# Does not touch compiled GKI source, EvoX ROM sources, partitions or device.
set -Eeuo pipefail
R="$HOME/annibale-kernel-port"
B="$R/staging-6.6.145"
W="$R/staging-6.6.158-virtual-review"
D="$R/report-6.6.158-direct"
EXPECTED_W="75632be0e0f1647a58aad5def7e15c930d7210b6"
EXPECTED_B="831d9bce8371e23466e06129d1fbfcb6eadc1979"
PREPORT="712c2cd5c"
fail(){ printf 'STOP: %s\n' "$*" >&2; exit 2; }
echo "=== K1: guard checkpoint 75632be0e ==="
[ "$(git -C "$W" rev-parse HEAD)" = "$EXPECTED_W" ] || fail "review SHA changed / script already run"
[ "$(git -C "$B" rev-parse HEAD)" = "$EXPECTED_B" ] || fail "baseline SHA changed"
[ -z "$(git -C "$W" status --porcelain)" ] || fail "review tree dirty"
[ -z "$(git -C "$B" status --porcelain)" ] || fail "baseline dirty"
[ "$(git -C "$W" branch --show-current)" = "annibale-6.6.158-virtual-review-20261011" ] || fail "review branch mismatch"
[ -s "$D/conflict-files.txt" ] || fail "missing conflict list"
git -C "$B" cat-file -e "$PREPORT^{commit}" || fail "preport baseline unavailable"
TMP="$(mktemp -d "$R/k1-cohort7.XXXXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/manifest.txt" <<'MANIFEST'
fwnode|include/linux/fwnode.h|7f7bcc082aef05ce1307f2df54849a92c9a49cc01eed3f8506e83581c31df634|03b248c2c433440a0ef86a19a158c5d20e028fe2fb9622068c8c80f63d334b80|1
stable|include/linux/seqlock.h|d73fd6af5c30031e2f572bfae7db6fe77277f1f574e0bd1408fffb26aeaa9c68|76ada28aa69907270937818bcab679d9f8752d3187c6100517d12772fa776863|4
tracefs|fs/tracefs/event_inode.c|924d02579280a5c00b7716af741f2ff9d07ee33466588167f9381887081f3f77|978a2365f936b8f6b3e6bc53038230888735907668e0241c7b6c9a4d93bb3744|2
stable|fs/smb/common/cifsglob.h|41ed78ffa49d3cec93af365bf4d30c021ef235e20e0d4028dff0f1c147eed05a|2dd8133052d6cbb282404feb65963a4de436b978f8c22d3495c181feca9ae886|1
nullmain|drivers/block/null_blk/main.c|4c6c69778f463056e405a9ad8d18f93e7c81da0dff86affff3db10f73f3bbacd|fc8598d655a5136453cf65a6d6f30d0fc33d4095e631656660661e836dbb6e72|1
nullzoned|drivers/block/null_blk/zoned.c|e8f6e3c4d3cc5101ef7c053d3d23c1d68ba56fa91ae1a2eec851510ba101fc46|074567c82b175e3011dccecb1539dc5208b36c19f9261aa38f661a85e70ffb5d|3
hci|include/net/bluetooth/hci_core.h|d4757648c2ff55dbd25f77919527e462b33f0bd738faa6d8ed762150964082fa|6c6eceefaacf5f3dc33ce408ba393b5546186d1dcde1343c63060a1822174aa1|1
MANIFEST
python3 - "$W" "$TMP" <<'PY'
from pathlib import Path
import hashlib,re,sys
w=Path(sys.argv[1]);t=Path(sys.argv[2])
rows=[line.split("|") for line in (t/"manifest.txt").read_text().splitlines() if line.strip()]
assert len(rows)==7 and len({r[1] for r in rows})==7, "manifest invalid"
pat=re.compile(rb"(?ms)^<<<<<<< HEAD\n(.*?)^=======\n(.*?)^>>>>>>> v6\.6\.158\n")
for mode,path,sha0,sha1,num in rows:
    src=(w/path).read_bytes()
    assert hashlib.sha256(src).hexdigest()==sha0, "preimage mismatch "+path
    hits=list(pat.finditer(src))
    assert len(hits)==int(num), "unexpected conflict count "+path
    if mode=="fwnode":
        assert hits[0].group(1)==b""
        out=pat.sub(lambda m:m.group(1),src)
        assert b"\tu8 flags;" in out and b"ANDROID_KABI_RESERVE(1)" in out
        assert b"static inline void fwnode_set_flag" not in out
        assert out.count(b"fw_devlink_refresh_fwnode(struct fwnode_handle *fwnode);")==1
    elif mode=="stable":
        out=pat.sub(lambda m:m.group(2),src)
        if path=="include/linux/seqlock.h":
            assert b"defined(CONFIG_KASAN) || defined(CONFIG_UBSAN_ALIGNMENT)" in out
            assert b"static __always_inline void __scoped_seqlock_cleanup" in out
        if path=="fs/smb/common/cifsglob.h":
            assert out.count(b"struct smb_version_values {")==1
    elif mode=="tracefs":
        assert hits[0].group(1)==b""
        out=pat.sub(lambda m:m.group(1) if m.start()==hits[0].start() else m.group(1)+m.group(2),src)
        assert b"init_ei(" not in out and b"INIT_LIST_HEAD(&ei->children);" in out
        assert b"ei->attr.mode |= EVENTFS_SAVE_UID | EVENTFS_SAVE_GID;" in out
    elif mode=="nullmain":
        assert len(hits)==1
        ack=hits[0].group(1);stable=hits[0].group(2)
        assert b"max_segment_size" in ack and b"shared_tags" in stable
        assert b"shared_tags" not in ack
        combined=ack.replace(b"shared_tag_bitmap,size,",b"shared_tag_bitmap,shared_tags,size,")
        assert combined!=ack
        out=pat.sub(lambda m:combined,src)
        assert out.count(b"shared_tag_bitmap,shared_tags,size,")==1
    elif mode=="nullzoned":
        out=pat.sub(lambda m:m.group(1),src)
        assert b"div64_u64(sect, dev->zone_size_sects)" in out
        old=b'\tif (dev->zone_size > dev->size) {\n'
        add=b'\tif (!dev->zone_size) {\n\t\tpr_err("zone_size must be non-zero\\n");\n\t\treturn -EINVAL;\n\t}\n\n'
        assert out.count(old)==1
        out=out.replace(old,add+old)
        old=b'\tdev->zone_size_sects = mb_to_sects(dev->zone_size);\n'
        add=b'\tif (!dev->zone_size_sects) {\n\t\tpr_err("zone_size results in zero sectors\\n");\n\t\treturn -EINVAL;\n\t}\n'
        assert out.count(old)==1
        out=out.replace(old,old+add)
        assert out.count(b"dev->nr_zones =")==1
    elif mode=="hci":
        assert hits[0].group(1)==b""
        out=pat.sub(lambda m:m.group(1),src)
        assert b"spin_lock(&hdev->discovery.lock);" not in out
    else:
        raise AssertionError("unknown mode "+mode)
    assert b"<<<<<<< " not in out and b">>>>>>> " not in out, "markers remain "+path
    assert hashlib.sha256(out).hexdigest()==sha1, "postimage mismatch "+path
    prepared=t/"prepared"/path
    prepared.parent.mkdir(parents=True,exist_ok=True)
    prepared.write_bytes(out)
print("K1_BATCH7_PRECHECK_ALL_OK")
PY
commit_group() {
  local msg="$1"; shift
  local files=( "$@" )
  for f in "${files[@]}"; do cp "$TMP/prepared/$f" "$W/$f"; done
  git -C "$W" add -- "${files[@]}"
  [ "$(git -C "$W" diff --cached --name-only | wc -l)" -eq "${#files[@]}" ] || fail 'wrong staged count'
  git -C "$W" diff --cached --check || fail 'bad whitespace'
  git -C "$W" -c user.name="Annibale Kernel Port" -c user.email="kernel-port@localhost" commit -m "$msg"
}
echo "=== KMI-safe fwnode, stable seqlock and tracefs (3) ==="
commit_group "K1: preserve fwnode u8 KMI, update scoped seqlock and tracefs ownership" \
  include/linux/fwnode.h include/linux/seqlock.h fs/tracefs/event_inode.c
echo "=== null_blk zone validation and configfs features (2) ==="
commit_group "K1: reconcile null_blk zone divisor guards and configfs features" \
  drivers/block/null_blk/main.c drivers/block/null_blk/zoned.c
echo "=== SMB common type and Bluetooth lock regression guard (2) ==="
commit_group "K1: align SMB common declarations and avoid unmatched BT discovery lock" \
  fs/smb/common/cifsglob.h include/net/bluetooth/hci_core.h

n=0
while IFS= read -r file || [ -n "$file" ]; do
  [ -n "$file" ] || continue
  if grep -q '^<<<<<<< ' "$W/$file"; then n=$((n+1)); fi
done < "$D/conflict-files.txt"
[ "$n" -eq 59 ] || fail "unexpected conflict count $n"
[ "$(git -C "$B" rev-parse HEAD)" = "$EXPECTED_B" ] || fail "baseline changed"
[ -z "$(git -C "$B" status --porcelain)" ] || fail 'baseline dirty'
[ -z "$(git -C "$W" status --porcelain)" ] || fail 'review tree dirty'
echo "K1_BATCH7_RESOLVED_REMAINING_59"
echo "K1_REVIEW_HEAD=$(git -C "$W" rev-parse HEAD)"
echo "K1_BASELINE_PRESERVED=$EXPECTED_B"

echo '=== Backup source deltas before server expires ==='
SHORT="$(git -C "$W" rev-parse --short=9 HEAD)"
OUT="$HOME/ANNIBALE_KERNEL_K1_RECOVERY_20261012_${SHORT}.tar.gz"
[ ! -e "$OUT" ] || fail 'archive already exists'
mkdir -p "$TMP/recovery"
git -C "$B" diff --binary "$PREPORT" "$EXPECTED_B" | gzip -1 > "$TMP/recovery/01_preport_to_compiled.patch.gz"
git -C "$B" diff --binary "$EXPECTED_B" "$(git -C "$W" rev-parse HEAD)" | gzip -1 > "$TMP/recovery/02_compiled_to_review.patch.gz"
[ -s "$TMP/recovery/01_preport_to_compiled.patch.gz" ] || fail 'patch 01 missing'
[ -s "$TMP/recovery/02_compiled_to_review.patch.gz" ] || fail 'patch 02 missing'
cp "$D/conflict-files.txt" "$D/threeway-report.txt" "$TMP/recovery/"
cp "$TMP/manifest.txt" "$TMP/recovery/batch7-manifest.txt"
cp "$R/out-checkpoint-ABCDE/arch/arm64/boot/Image" "$TMP/recovery/compiled-Image"
cp "$R/out-checkpoint-ABCDE/Module.symvers" "$TMP/recovery/compiled-Module.symvers"
cp "$R/out-checkpoint-ABCDE/.config" "$TMP/recovery/compiled-config"
cat > "$TMP/recovery/README.txt" <<EOF
ANNIBALE K1 WIP. NOT BUILDABLE / NOT FLASHABLE.
Preport source SHA: $(git -C "$B" rev-parse "$PREPORT")
Compiled partial baseline SHA: $EXPECTED_B
Current 6.6.158 review SHA: $(git -C "$W" rev-parse HEAD)
Recover from EXACT preport SHA by applying patches 01 and 02 sequentially.
59 conflict files remain; automatic merges and OEM ABI are unvalidated.
The included Image is from 6.6.145 PARTIAL, NOT Linux 6.6.158.
EOF
(cd "$TMP/recovery" && sha256sum *.patch.gz compiled-* > SHA256SUMS)
tar -czf "$OUT.tmp" -C "$TMP/recovery" .
mv "$OUT.tmp" "$OUT"
sha256sum "$OUT"
ls -lh "$OUT"
echo "K1_RECOVERY_READY=$OUT"
echo "K1_59_REMAIN_NOT_BUILDABLE_NOT_FLASHABLE"
#!/usr/bin/env bash
# K1 review: 14 file-level resolutions audited against 114-file conflict bundle.
# Requires post-next10 worktree, preserves compiled baseline and creates portable backup.
# Still 76 unresolved conflicts after this step: NOT BUILDABLE / NOT FLASHABLE.
set -Eeuo pipefail
R="$HOME/annibale-kernel-port"
BASE="$R/staging-6.6.145"
W="$R/staging-6.6.158-virtual-review"
D="$R/report-6.6.158-direct"
EXPECTED="1a2fd8c70f34412f940a0ab76bac0569a0afd550"
COMPILED="831d9bce8371e23466e06129d1fbfcb6eadc1979"
PREPORT="712c2cd5c"
fail(){ printf 'STOP: %s\n' "$*" >&2; exit 2; }
echo '=== K1 14: preflight repository checkpoints ==='
[ "$(git -C "$BASE" rev-parse HEAD)" = "$COMPILED" ] || fail "compiled baseline changed"
[ -z "$(git -C "$BASE" status --porcelain)" ] || fail "compiled baseline dirty"
[ "$(git -C "$W" rev-parse HEAD)" = "$EXPECTED" ] || fail "review HEAD changed / script already run"
[ "$(git -C "$W" branch --show-current)" = "annibale-6.6.158-virtual-review-20261011" ] || fail "unexpected review branch"
[ -z "$(git -C "$W" status --porcelain)" ] || fail "review worktree dirty"
[ "$(wc -l < "$D/conflict-files.txt")" -eq 114 ] || fail "missing conflict list"
git -C "$BASE" cat-file -e "$PREPORT^{commit}" || fail "preport base unavailable"
TMP="$(mktemp -d "$R/k1-batch14.XXXXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/manifest.txt" <<'MANIFEST'
upstream|drivers/nvme/target/fabrics-cmd-auth.c|85587d6a9629d98089a879d779c72379564265e3c9eed1e75fd62609939afe30|add6e6f677ce0ab4b1ff4d529aae4fad56f675631a37de344d9e17f8f9a60159|2
upstream|fs/smb/client/misc.c|076c56bea361cd07f4992ea62cfcf3ae11434657c86eb31fb170c7781723f7a8|0d0ae30649f5127174d73426a576085853b8c7ba832f312bfad68029c8305fde|2
upstream|net/sunrpc/xdr.c|5142c90f2fc3965ab106ed6865743de16eac1f2e02e6c8795f422ecea78745d1|95636bf6a2ae7e02a9ebee4c12da19fd23ffbda452e1988a7068030dc03d2e9a|1
upstream|net/sched/sch_drr.c|7223d91cd4b7d5cc5f372ee5f472d37050c89bc3c2ed93bf220c2f6aa3639801|530f399fabd0b39132085878dd58ee6133be9c678d1f3fa165e856effa83954d|2
upstream|fs/fs-writeback.c|75212232c9b22852360beba660233d3e2a486294280d02257a2fdee75b11dc65|5f9a07ac242daecf523e2ffd86e9e5e25ccf17d4b570b0a53997587e25a67143|1
upstream|net/can/bcm.c|7f622bdcf176ab35c7c4cfa09ed162263a496a08e295d5b5c28b6cb36227fd35|1aad130f7b1c890a92a409d0a0c649c41177fdd5408c6f40fc747ab006af8b48|1
android|kernel/trace/trace_events_hist.c|bd2829ac5304b871fec8814060d3374f6d72d6f3e23ee23331b63d38c3bbcd67|b51b004b40ed69c522ebc18bcfe84144b3edb529889c323e390895cd21bd52da|2
android|fs/f2fs/data.c|0535c2f63636ecb5c1377c40b7efaeb76249d0f013f31c44ff4c93e960a728c7|e9792d4fe9bfaf6497a1294eaf8b44fa282c3d05bc6ec3e747a6cae9877f95ed|1
android|mm/vmscan.c|bd0cc9c0c0139019efcd82eeb955f9b93c78435f697ba9d29c036ef7762b88f7|326522a0f1e23c1a551c96e7c96f0f90d57cdfcbefcd26cd80f679bbb38ea68f|1
android|kernel/fork.c|e6a079fcf5b5a6db4296b841ee7becdadf6c3efd7eb732e808eb039a7f7b3563|060b35c69ebf5c5037e9b84c0aaf5247f05e82ddac170b6bdb6a3c6d7dc6d192|2
android|fs/smb/client/cifsglob.h|52edc607a6f56f1c295b29cffeac4a34ebaa882f240cb8bf910f498f1f5030ca|f9cfa64595e39cc0b138fb41c135cbb012e225f52368498bd4fc8d2a43742388|1
android|mm/damon/paddr.c|cbf32358333173832212560a0f5c87f3a64b6f96b2096c78b6f249886304b9ce|83704e37787f44918dcbc1f245097d78639629e2f4439d38a04716f0f362f351|1
android|mm/damon/vaddr.c|bbf89405eddc10b5321b76362d4a8dd3893ba1eccdee9fefb0043c72897ba104|327b839f3db9922a0ce6ca919b5d2ac510e816a020052f1bafdd30a5120f7be7|3
android|net/can/isotp.c|ed19ac87841c1523e5964a53d6fbbf993027d75b66da3b864c60b8d8abdfcda2|8fc36cf5802a29743bd057d9fd04b5a79fac4c75d4551677e41702f689eca555|1
MANIFEST
python3 - "$W" "$TMP" <<'PY'
from pathlib import Path
import sys, re, hashlib
w=Path(sys.argv[1]); t=Path(sys.argv[2])
rows=[line.split("|") for line in (t/"manifest.txt").read_text().splitlines() if line.strip()]
assert len(rows)==14 and len({r[1] for r in rows})==14, "manifest invalid"
p=re.compile(rb"(?ms)^<<<<<<< HEAD\n(.*?)^=======\n(.*?)^>>>>>>> v6\.6\.158\n")
for mode,path,sha_before,sha_after,n in rows:
    f=w/path
    source=f.read_bytes()
    assert hashlib.sha256(source).hexdigest()==sha_before, "preimage mismatch "+path
    hits=list(p.finditer(source))
    assert len(hits)==int(n), "unexpected conflicts "+path
    out=p.sub(lambda m: m.group(2) if mode=="upstream" else m.group(1),source)
    assert hashlib.sha256(out).hexdigest()==sha_after, "postimage mismatch "+path
    assert b"<<<<<<< " not in out and b">>>>>>> " not in out, "markers remain "+path
    dst=t/"prepared"/path
    dst.parent.mkdir(parents=True,exist_ok=True)
    dst.write_bytes(out)
def buf(path):
    return (t/"prepared"/path).read_bytes()
assert b"nvmet_auth_negotiate(struct nvmet_req *req, void *d, u32 tl)" in buf("drivers/nvme/target/fabrics-cmd-auth.c")
assert b"nvmet_auth_negotiate(req, d, tl)" in buf("drivers/nvme/target/fabrics-cmd-auth.c")
assert b"seq_buf_str(&s)" not in buf("kernel/trace/trace_events_hist.c")
assert buf("kernel/trace/trace_events_hist.c").count(b"seq_buf_terminate(&s);")>=2
assert b"trace_android_vh_folio_trylock_clear(folio)" in buf("mm/vmscan.c")
assert b"trace_android_vh_dup_task_struct(tsk, orig)" in buf("kernel/fork.c")
assert b"synchronize_rcu();" in buf("net/can/isotp.c")
assert b"damon_update_region_access_rate" in buf("mm/damon/paddr.c")
assert b"damon_update_region_access_rate" in buf("mm/damon/vaddr.c")
print("K1_14_PRECHECK_ALL_FILES_OK")
PY
echo '=== K1: 6 independent upstream safety/correctness fixes ==='
mapfile -t UP < <(awk -F'|' '$1=="upstream"{print $2}' "$TMP/manifest.txt")
[ "${#UP[@]}" -eq 6 ] || fail "upstream file count"
for p in "${UP[@]}"; do cp "$TMP/prepared/$p" "$W/$p"; done
git -C "$W" add -- "${UP[@]}"
git -C "$W" diff --cached --check || fail "whitespace upstream"
[ "$(git -C "$W" diff --cached --name-only | wc -l)" -eq 6 ] || fail "unexpected staged upstream paths"
git -C "$W" -c user.name="Annibale Kernel Port" -c user.email="kernel-port@localhost" commit -m "K1: integrate independent NVMe SMB RPC DRR writeback CAN stable changes"
echo '=== K1: preserve 8 Android ACK behavior and pre-existing fixes ==='
mapfile -t AND < <(awk -F'|' '$1=="android"{print $2}' "$TMP/manifest.txt")
[ "${#AND[@]}" -eq 8 ] || fail "Android file count"
for p in "${AND[@]}"; do cp "$TMP/prepared/$p" "$W/$p"; done
git -C "$W" add -- "${AND[@]}"
git -C "$W" diff --cached --check || fail "whitespace Android"
[ "$(git -C "$W" diff --cached --name-only | wc -l)" -eq 8 ] || fail "unexpected staged Android paths"
git -C "$W" -c user.name="Annibale Kernel Port" -c user.email="kernel-port@localhost" commit -m "K1: preserve Android trace hooks F2FS fork DAMON SMB and CAN RCU fixes"

echo '=== Verify before recovery ==='
n=0
while IFS= read -r f || [ -n "$f" ]; do
  [ -n "$f" ] || continue
  if grep -q '^<<<<<<< ' "$W/$f"; then n=$((n+1)); fi
done < "$D/conflict-files.txt"
[ "$n" -eq 76 ] || fail "unresolved count unexpected: $n"
[ "$(git -C "$BASE" rev-parse HEAD)" = "$COMPILED" ] || fail "baseline HEAD changed"
[ -z "$(git -C "$BASE" status --porcelain)" ] || fail "baseline dirty"
[ -z "$(git -C "$W" status --porcelain)" ] || fail "review worktree dirty"
echo "K1_14_RESOLVED_REMAINING_76"
echo "K1_REVIEW_HEAD=$(git -C "$W" rev-parse HEAD)"

echo '=== Save recoverable source snapshots ==='
REV="$(git -C "$W" rev-parse --short=9 HEAD)"
OUT="$HOME/ANNIBALE_KERNEL_K1_RECOVERY_20261012_${REV}.tar.gz"
[ ! -e "$OUT" ] || fail "archive exists"
mkdir -p "$TMP/recovery"
git -C "$BASE" diff --binary "$PREPORT" "$COMPILED" | gzip -1 > "$TMP/recovery/01_preport_to_compiled.patch.gz"
git -C "$BASE" diff --binary "$COMPILED" "$(git -C "$W" rev-parse HEAD)" | gzip -1 > "$TMP/recovery/02_compiled_to_review.patch.gz"
test -s "$TMP/recovery/01_preport_to_compiled.patch.gz"
test -s "$TMP/recovery/02_compiled_to_review.patch.gz"
cp "$D/conflict-files.txt" "$D/threeway-report.txt" "$TMP/recovery/"
cp "$TMP/manifest.txt" "$TMP/recovery/batch14-manifest.txt"
cp "$R/out-checkpoint-ABCDE/arch/arm64/boot/Image" "$TMP/recovery/compiled-Image"
cp "$R/out-checkpoint-ABCDE/Module.symvers" "$TMP/recovery/compiled-Module.symvers"
cp "$R/out-checkpoint-ABCDE/.config" "$TMP/recovery/compiled-config"
cat > "$TMP/recovery/README.txt" <<EOF
ANNIBALE EXPERIMENTAL K1 RECOVERY - NOT BUILDABLE, NOT FLASHABLE
Preport base: $(git -C "$BASE" rev-parse "$PREPORT")
Compiled baseline: $COMPILED
Review HEAD: $(git -C "$W" rev-parse HEAD)
To recover source, start from EXACT preport SHA and apply patch 01 then 02.
Review tree still has 76 unresolved text conflicts AND unvalidated automatic merges.
Compiled Image is from earlier partial kernel port, NOT a Linux 6.6.158 image.
Do not use this archive for flashing.
EOF
(cd "$TMP/recovery" && sha256sum *.patch.gz compiled-* > SHA256SUMS)
tar -czf "$OUT.tmp" -C "$TMP/recovery" .
mv "$OUT.tmp" "$OUT"
sha256sum "$OUT"
ls -lh "$OUT"
echo "K1_RECOVERY_READY=$OUT"
echo "K1_BASELINE_PRESERVED=$COMPILED"
echo 'K1_76_REMAIN_NOT_BUILDABLE_NOT_FLASHABLE'

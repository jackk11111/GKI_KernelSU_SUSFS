#!/usr/bin/env bash
# K1: 10 audited source conflict resolutions in six cohesive subsystems.
# Special FUSE handling retains Android FUSE-BPF and adapts upstream 7-arg API.
# Guards exact 40cc34835 snapshot and leaves compiled 831d9bce8 intact.
set -Eeuo pipefail
R="$HOME/annibale-kernel-port"
B="$R/staging-6.6.145"
W="$R/staging-6.6.158-virtual-review"
D="$R/report-6.6.158-direct"
EXPECT_W="40cc34835a3592ee58b96e9d3c15d47840c7f19e"
EXPECT_B="831d9bce8371e23466e06129d1fbfcb6eadc1979"
PREPORT="712c2cd5c"
fail(){ echo "STOP: $*" >&2; exit 2; }
echo '=== K1: verify 40cc34835 and known-good compiled checkpoint ==='
[ "$(git -C "$W" rev-parse HEAD)" = "$EXPECT_W" ] || fail 'review HEAD changed or already run'
[ "$(git -C "$B" rev-parse HEAD)" = "$EXPECT_B" ] || fail 'compiled baseline changed'
[ -z "$(git -C "$W" status --porcelain)" ] || fail 'review dirty'
[ -z "$(git -C "$B" status --porcelain)" ] || fail 'baseline dirty'
[ "$(git -C "$W" branch --show-current)" = "annibale-6.6.158-virtual-review-20261011" ] || fail 'review branch mismatch'
[ -s "$D/conflict-files.txt" ] || fail 'missing original conflict manifest'
git -C "$B" cat-file -e "$PREPORT^{commit}" || fail 'preport not present'
T="$(mktemp -d "$R/k1-ten-cohesive.XXXXXXXX")"
trap 'rm -rf "$T"' EXIT
cat > "$T/manifest.txt" <<'MANIFEST'
fuse_dir|fs/fuse/dir.c|f0bb00e029b0ba7fae76bf2cb0d0bf13f447d5f2c307f5a27c74f4687909b0e5|393f4af7a936de7b0943a6abd83ab6f87d7974994993c55da40b28dae0d2223c|1
fuse_inode|fs/fuse/inode.c|b5bf94fc2b9684ff66524a8acb61f0332ec93170448e1c46cca10ca2d161604e|38f52111459c609d8b272b5f76497a895b8c40251861cc3ff02ec13dda923441|2
upstream|fs/smb/server/connection.c|87be9ee2cd92389a8b63721e287b2e09649bd9db6facc9e59c300ec45b3794db|07acf1017dee8383e31646a4817842a1e131c0de56b1e86d106ac06110bc3b18|1
upstream|fs/smb/server/connection.h|d0d07a956d6349abb7002d424a4d1b822cb44bad18004b63cce5b715792018cd|0be578e4d13962f685753b67ee28ea54d623b59c8d007a87aeed02c2592b8b49|1
upstream|fs/smb/server/smb_common.h|6c47fdb1ea99c368298bbcc9e1d61c7efb735adca5cc1b6b6c1fc4e151665de9|49af1cb5daca427e8d2bfbcca953c8e14ede111f826c36670666ca943d30f125|1
upstream|drivers/nvme/target/fabrics-cmd.c|dd13b724c9fdaf0f2678357f59a689f2655e0abb65d316cb01e95cd29d2b902e|af183e843039addb24f6fcb013281c8e41f6060ad7dc1bc31a65f0d8e3b9e966|1
upstream|drivers/nvme/target/rdma.c|75815aa2e8fd9e944eb513505826dcea9379b538fd80196c99fb1efce915949b|aaa079a531a6a4c34b2ae09331d72e77a8d0d3f511c00725c255357ccab2f483|1
upstream|kernel/events/core.c|d591b3a7d149b6af9bfdc43b9afea1dd1c43fcd5b8fbb425ac14cf62309e719d|1a29ef2c04a5cc49a916e9bc8763ca70d109c71434aafe527f6c79f6bcf8a672|1
upstream|net/sunrpc/xprtrdma/rpc_rdma.c|0afc43edeb8be4ae898d749988d1015fa7f6d9c9c8179007192588337101885c|a7c297520d77f8bfc0ca33822eda688b6e8347468dd8f1b075c5207b46013297|2
upstream|net/mac80211/tx.c|534befae8a60aab46a517d96fa5043d853d9b2bf733b82fff979178e21a0a19b|2ce4ac6734016876a27000e6a611bf9b51d743e757436d407541481ac221d814|1
MANIFEST
python3 - "$W" "$T" <<'PY'
from pathlib import Path
import re,hashlib,sys
w=Path(sys.argv[1]);t=Path(sys.argv[2])
rows=[x.split("|") for x in (t/"manifest.txt").read_text().splitlines() if x]
assert len(rows)==10 and len({r[1] for r in rows})==10, "manifest invalid"
pat=re.compile(rb"(?ms)^<<<<<<< HEAD\n(.*?)^=======\n(.*?)^>>>>>>> v6\.6\.158\n")
for mode,path,old,new,n in rows:
    src=(w/path).read_bytes()
    assert hashlib.sha256(src).hexdigest()==old, "source mismatch: "+path
    hits=list(pat.finditer(src))
    assert len(hits)==int(n), "conflict hunk mismatch: "+path
    if mode=="fuse_dir":
        assert not hits[0].group(1)
        fixed=pat.sub(lambda m:m.group(1),src)
        a=b"\t\t\t\tattr_version);"
        assert fixed.count(a)==1, "FUSE dir call location changed"
        fixed=fixed.replace(a,b"\t\t\t\tattr_version, evict_ctr);")
        assert fixed.count(b"*inode = fuse_iget(sb, outarg->nodeid")==1, "duplicate fuse_iget"
    elif mode=="fuse_inode":
        assert not hits[1].group(1)
        fixed=pat.sub(lambda m:m.group(1),src)
        a=b"inode = fuse_iget(sb, 1, 0, &attr, 0, 0);"
        assert fixed.count(a)==1, "FUSE root call changed"
        fixed=fixed.replace(a,b"inode = fuse_iget(sb, FUSE_ROOT_ID, 0, &attr, 0, 0, 0);")
        assert fixed.count(b"static void fuse_fill_attr_from_inode(")==1, "duplicate attr helper"
        assert b"get_fuse_inode(inode)->bpf = root_bpf" in fixed, "Android BPF root lost"
    else:
        fixed=pat.sub(lambda m:m.group(2),src)
    assert b"<<<<<<< " not in fixed and b">>>>>>> " not in fixed, "unresolved markers: "+path
    assert hashlib.sha256(fixed).hexdigest()==new, "postimage mismatch: "+path
    out=t/"prepared"/path;out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(fixed)
def data(f):return (t/"prepared"/f).read_bytes()
assert b"void ksmbd_conn_abort(struct ksmbd_conn *conn)" in data("fs/smb/server/connection.c")
assert b"ksmbd_preauth_session_destroy(conn);" in data("fs/smb/server/connection.c")
assert b"void ksmbd_conn_abort(struct ksmbd_conn *conn);" in data("fs/smb/server/connection.h")
assert b"__SMB_COMMON_H__" not in data("fs/smb/server/smb_common.h")
assert b"NVME_SC_DNR" not in data("drivers/nvme/target/fabrics-cmd.c")
assert b"nvmet_rdma_free_rsp_resources(rsp);" in data("drivers/nvme/target/rdma.c")
perf=data("kernel/events/core.c")
assert b"__event_disable(event, ctx, state);" in perf
assert b"event_sched_out(event, ctx);" in perf
rpc=data("net/sunrpc/xprtrdma/rpc_rdma.c")
assert rpc.count(b"req->rl_sendctx = NULL;") >= 2
wifi=data("net/mac80211/tx.c")
assert b"free_txskb:" in wifi and b"goto free_txskb;" in wifi
print("K1_TEN_COHESIVE_PRECHECK_OK")
PY

# Commit logically related changes independently to keep regressions bisectable.
commit_files(){
  local msg="$1";shift
  local files=( "$@" )
  for f in "${files[@]}"; do cp "$T/prepared/$f" "$W/$f"; done
  git -C "$W" add -- "${files[@]}"
  [ "$(git -C "$W" diff --cached --name-only | wc -l)" -eq "${#files[@]}" ] || fail "unexpected staged files"
  git -C "$W" diff --cached --check || fail "whitespace check failed"
  git -C "$W" -c user.name="Annibale Kernel Port" -c user.email="kernel-port@localhost" commit -m "$msg"
}
echo '=== FUSE: retain Android BPF while adapting 7-arg fuse_iget ==='
commit_files "K1: reconcile FUSE evict counter with Android FUSE-BPF" fs/fuse/dir.c fs/fuse/inode.c
echo '=== SMB: connection cleanup and coherent common header ==='
commit_files "K1: integrate stable SMB server teardown and include guards" fs/smb/server/connection.c fs/smb/server/connection.h fs/smb/server/smb_common.h
echo '=== NVMe: status flag and response resource helpers ==='
commit_files "K1: align stable NVMe target status and RDMA resource helpers" drivers/nvme/target/fabrics-cmd.c drivers/nvme/target/rdma.c
echo '=== perf: avoid duplicate event_sched_out ==='
commit_files "K1: avoid redundant perf event schedule out" kernel/events/core.c
echo '=== RPC RDMA: clear back-pointer in completion/cancel ==='
commit_files "K1: clear RPC RDMA sendctx back-pointers" net/sunrpc/xprtrdma/rpc_rdma.c
echo '=== mac80211: align frame-free error path ==='
commit_files "K1: use stable mac80211 free_txskb unwind" net/mac80211/tx.c

echo '=== Count original conflict paths ==='
n=0
while IFS= read -r f || [ -n "$f" ]; do
  [ -n "$f" ] || continue
  if grep -q '^<<<<<<< ' "$W/$f"; then n=$((n+1)); fi
done < "$D/conflict-files.txt"
[ "$n" -eq 66 ] || fail "expected 66 unresolved source paths, got $n"
[ "$(git -C "$B" rev-parse HEAD)" = "$EXPECT_B" ] || fail 'baseline changed'
[ -z "$(git -C "$B" status --porcelain)" ] || fail 'baseline dirty'
[ -z "$(git -C "$W" status --porcelain)" ] || fail 'review dirty'
echo "K1_TEN_COHESIVE_RESOLVED_REMAINING_66"
echo "K1_REVIEW_HEAD=$(git -C "$W" rev-parse HEAD)"
echo "K1_BASELINE_PRESERVED=$EXPECT_B"

echo '=== Update recoverable source backup ==='
REV="$(git -C "$W" rev-parse --short=9 HEAD)"
OUT="$HOME/ANNIBALE_KERNEL_K1_RECOVERY_20261012_${REV}.tar.gz"
[ ! -e "$OUT" ] || fail "backup exists already"
mkdir -p "$T/recovery"
git -C "$B" diff --binary "$PREPORT" "$EXPECT_B" | gzip -1 > "$T/recovery/01_preport_to_compiled.patch.gz"
git -C "$B" diff --binary "$EXPECT_B" "$(git -C "$W" rev-parse HEAD)" | gzip -1 > "$T/recovery/02_compiled_to_review.patch.gz"
[ -s "$T/recovery/01_preport_to_compiled.patch.gz" ] || fail 'missing source delta 01'
[ -s "$T/recovery/02_compiled_to_review.patch.gz" ] || fail 'missing source delta 02'
cp "$D/conflict-files.txt" "$D/threeway-report.txt" "$T/recovery/"
cp "$T/manifest.txt" "$T/recovery/batch10-semantic-manifest.txt"
cp "$R/out-checkpoint-ABCDE/arch/arm64/boot/Image" "$T/recovery/compiled-Image"
cp "$R/out-checkpoint-ABCDE/Module.symvers" "$T/recovery/compiled-Module.symvers"
cp "$R/out-checkpoint-ABCDE/.config" "$T/recovery/compiled-config"
cat > "$T/recovery/README.txt" <<EOF
ANNIBALE K1 kernel port WIP. NOT BUILDABLE / NOT FLASHABLE.
Base ACK commit: $(git -C "$B" rev-parse "$PREPORT")
Compiled partial checkpoint SHA: $EXPECT_B
6.6.158 review WIP SHA: $(git -C "$W" rev-parse HEAD)
Apply source delta 01 and then 02 ONLY to the exact preport base.
There remain 66 conflicted files plus unverified auto merges and OEM module ABI.
The included Image is the OLD compiled partial port, not Linux 6.6.158.
EOF
(cd "$T/recovery" && sha256sum *.patch.gz compiled-* > SHA256SUMS)
tar -czf "$OUT.tmp" -C "$T/recovery" .
mv "$OUT.tmp" "$OUT"
sha256sum "$OUT"
ls -lh "$OUT"
echo "K1_RECOVERY_READY=$OUT"
echo 'K1_66_REMAIN_NOT_BUILDABLE_NOT_FLASHABLE'

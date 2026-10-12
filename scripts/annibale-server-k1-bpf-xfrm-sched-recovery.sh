#!/usr/bin/env bash
# K1: BPF map owner layout, XFRM Android GKI compat, hybrid scheduler SMT misfit.
# Start at bd10f64d1: no Android ROM builds, root integration or flash.
set -Eeuo pipefail
R="$HOME/annibale-kernel-port"
B="$R/staging-6.6.145"
W="$R/staging-6.6.158-virtual-review"
D="$R/report-6.6.158-direct"
EXPECT_W="bd10f64d1717819afa91a1ab3845cd6010d49295"
EXPECT_B="831d9bce8371e23466e06129d1fbfcb6eadc1979"
PREPORT="712c2cd5c"
fail(){ printf 'STOP: %s\n' "$*" >&2; exit 2; }
echo '=== K1: strict checkpoint preconditions ==='
[ "$(git -C "$W" rev-parse HEAD)" = "$EXPECT_W" ] || fail 'review head changed or already patched'
[ "$(git -C "$B" rev-parse HEAD)" = "$EXPECT_B" ] || fail 'compile baseline changed'
[ -z "$(git -C "$W" status --porcelain)" ] || fail 'review worktree dirty'
[ -z "$(git -C "$B" status --porcelain)" ] || fail 'baseline worktree dirty'
[ "$(git -C "$W" branch --show-current)" = "annibale-6.6.158-virtual-review-20261011" ] || fail 'wrong branch'
[ -s "$D/conflict-files.txt" ] || fail 'no conflict manifest'
git -C "$B" cat-file -e "$PREPORT^{commit}" || fail 'preport missing'
TMP="$(mktemp -d "$R/k1-bpf-xfrm-sched.XXXXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/manifest.txt" <<'MANIFEST'
ack|kernel/bpf/core.c|d08901e9608708999a5aa8575d2748c24f9cad1d7834ab69dbaaffcb51cc26a9|2dfca5a03538cca3049d95ad00d926d3298b67b12cfbb7fe40ebec6c112557a0|1
xfrm|net/xfrm/xfrm_user.c|2c0ad07663b5a9ca42f5f6a5689b686bbcdefc17de924f075712468aba282be7|648c33574271cfd9b35dbee27315be79a7df0d28e0f481b4f979d9d627f75a7e|1
sched|kernel/sched/fair.c|1a6bc1c851812c8d04b1b84eaa22df03c4765d7dc9b059b93c43f7a1ec75b722|25dec2f5db51e946b457d241c8de8c3969b2786591c2911acd49cabcd3d8930f|1
MANIFEST
python3 - "$W" "$B" "$TMP" <<'PY'
from pathlib import Path
import re,hashlib,sys
w=Path(sys.argv[1]); b=Path(sys.argv[2]); t=Path(sys.argv[3])
rows=[r.split("|") for r in (t/"manifest.txt").read_text().splitlines() if r.strip()]
assert len(rows)==3 and len({x[1] for x in rows})==3
p=re.compile(rb"(?ms)^<<<<<<< HEAD\n(.*?)^=======\n(.*?)^>>>>>>> v6\.6\.158\n")
for mode,path,expected_src,expected_out,count in rows:
    src=(w/path).read_bytes()
    assert hashlib.sha256(src).hexdigest()==expected_src, "preimage changed "+path
    matches=list(p.finditer(src))
    assert len(matches)==int(count), "conflict count changed "+path
    if mode=='sched':
        m=matches[0]
        ack=m.group(1)
        assert b"(sgs->group_misfit_reason == MISFIT_PERF) &&" in ack
        assert ack.count(b"\t    (!capacity_greater")==1
        combined=ack.replace(b"\t    (!capacity_greater",b"\t    (!env->dst_core_idle ||\n\t     !capacity_greater")
        out=src[:m.start()]+combined+src[m.end():]
        assert out.count(b"env->dst_core_idle = !sched_smt_active() || is_core_idle(env->dst_cpu);")==1
        assert b"\tbool\t\t\tdst_core_idle;" in out
    else:
        out=p.sub(lambda m:m.group(1),src)
    assert hashlib.sha256(out).hexdigest()==expected_out,"output unexpected "+path
    assert b"<<<<<<< " not in out and b">>>>>>> " not in out,"conflicts remain "+path
    if mode=='ack':
        assert out==(b/path).read_bytes(),"BPF result must match compiled ACK source"
        assert b"map->owner->" not in out and b"spin_lock(&map->owner.lock);" in out
    if mode=='xfrm':
        assert out.count(b"CONFIG_GKI_NET_XFRM_HACKS")==1
        assert b"static struct sock *xfrm_net_nlsk" in out
        assert b"netlink_dump_start(xfrm_net_nlsk(net, skb)" in out
        assert b"IS_ENABLED(CONFIG_XFRM_USER_COMPAT)" in out
    if mode=='sched':
        assert b"(sgs->group_misfit_reason == MISFIT_PERF) &&" in out
        assert b"(!env->dst_core_idle ||" in out
    target=t/"prepared"/path
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_bytes(out)
print("K1_BPF_XFRM_SCHED_PRECHECK_OK")
PY

commit_one(){
  local msg="$1" file="$2"
  cp "$TMP/prepared/$file" "$W/$file"
  git -C "$W" add -- "$file"
  [ "$(git -C "$W" diff --cached --name-only)" = "$file" ] || fail "unexpected staged changes"
  git -C "$W" diff --cached --check || fail "whitespace error"
  git -C "$W" -c user.name="Annibale Kernel Port" -c user.email="kernel-port@localhost" commit -m "$msg"
}
echo '=== Preserve ACK BPF map owner layout ==='
commit_one "K1: retain compiled ACK embedded BPF map owner layout" kernel/bpf/core.c
echo '=== Preserve Android XFRM compatibility with stable netlink fixes ==='
commit_one "K1: reconcile Android GKI XFRM compat with stable netlink helper" net/xfrm/xfrm_user.c
echo '=== Combine Android MISFIT_PERF with upstream SMT idle gate ==='
commit_one "K1: combine Android misfit reason with stable SMT core-idle check" kernel/sched/fair.c

N=0
while IFS= read -r file || [ -n "$file" ]; do
  [ -n "$file" ] || continue
  if grep -q '^<<<<<<< ' "$W/$file"; then N=$((N+1)); fi
done < "$D/conflict-files.txt"
[ "$N" -eq 49 ] || fail "expected 49 unresolved original paths, got $N"
[ "$(git -C "$B" rev-parse HEAD)" = "$EXPECT_B" ] || fail "compiled baseline changed"
[ -z "$(git -C "$B" status --porcelain)" ] || fail "baseline dirty"
[ -z "$(git -C "$W" status --porcelain)" ] || fail "review dirty"
echo "K1_BPF_XFRM_SCHED_RESOLVED_REMAINING_49"
echo "K1_REVIEW_HEAD=$(git -C "$W" rev-parse HEAD)"
echo "K1_BASELINE_PRESERVED=$EXPECT_B"

echo '=== Updated portable recovery archive ==='
SHORT="$(git -C "$W" rev-parse --short=9 HEAD)"
OUT="$HOME/ANNIBALE_KERNEL_K1_RECOVERY_20261012_${SHORT}.tar.gz"
[ ! -e "$OUT" ] || fail "archive already exists"
mkdir -p "$TMP/recovery"
git -C "$B" diff --binary "$PREPORT" "$EXPECT_B" | gzip -1 > "$TMP/recovery/01_preport_to_compiled.patch.gz"
git -C "$B" diff --binary "$EXPECT_B" "$(git -C "$W" rev-parse HEAD)" | gzip -1 > "$TMP/recovery/02_compiled_to_review.patch.gz"
[ -s "$TMP/recovery/01_preport_to_compiled.patch.gz" ] || fail "patch 01 missing"
[ -s "$TMP/recovery/02_compiled_to_review.patch.gz" ] || fail "patch 02 missing"
cp "$D/conflict-files.txt" "$D/threeway-report.txt" "$TMP/recovery/"
cp "$TMP/manifest.txt" "$TMP/recovery/bpf-xfrm-sched-manifest.txt"
cp "$R/out-checkpoint-ABCDE/arch/arm64/boot/Image" "$TMP/recovery/compiled-Image"
cp "$R/out-checkpoint-ABCDE/Module.symvers" "$TMP/recovery/compiled-Module.symvers"
cp "$R/out-checkpoint-ABCDE/.config" "$TMP/recovery/compiled-config"
cat > "$TMP/recovery/README.txt" <<EOF
ANNIBALE K1 recovery WIP. NOT BUILDABLE / NOT FLASHABLE.
Exact ACK preport SHA: $(git -C "$B" rev-parse "$PREPORT")
Compiled partial baseline SHA: $EXPECT_B
Review HEAD: $(git -C "$W" rev-parse HEAD)
From EXACT preport SHA, apply 01 and then 02.
49 original conflict paths remain; unverified autoconflicts and ABI.
The Image is from old partial checkpoint, NOT Linux 6.6.158.
EOF
(cd "$TMP/recovery" && sha256sum *.patch.gz compiled-* > SHA256SUMS)
tar -czf "$OUT.tmp" -C "$TMP/recovery" .
mv "$OUT.tmp" "$OUT"
sha256sum "$OUT"
ls -lh "$OUT"
echo "K1_RECOVERY_READY=$OUT"
echo 'K1_49_REMAIN_NOT_BUILDABLE_NOT_FLASHABLE'

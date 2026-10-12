#!/usr/bin/env bash
# K1 cohort: eight arm64 PTE API ACK aliases + two coordinated stable dst files.
# Strictly exact-source verified. NOT a compile / ABI / boot validation.
set -Eeuo pipefail
R="$HOME/annibale-kernel-port"
B="$R/staging-6.6.145"
W="$R/staging-6.6.158-virtual-review"
D="$R/report-6.6.158-direct"
START="777a50fcb36c7b4dd0476dacc9f591b72ada23c4"
BASE="831d9bce8371e23466e06129d1fbfcb6eadc1979"
PREPORT="712c2cd5c"
die() { echo "STOP: $*" >&2; exit 2; }

echo '=== K1 ARM64-PTE + DST: strict preconditions ==='
[ "$(git -C "$B" rev-parse HEAD)" = "$BASE" ] || die "baseline SHA changed"
[ -z "$(git -C "$B" status --porcelain)" ] || die "baseline dirty"
[ "$(git -C "$W" rev-parse HEAD)" = "$START" ] || die "review SHA differs or already applied"
[ -z "$(git -C "$W" status --porcelain)" ] || die "review dirty"
[ "$(git -C "$W" branch --show-current)" = "annibale-6.6.158-virtual-review-20261011" ] || die "unexpected review branch"
[ "$(wc -l < "$D/conflict-files.txt")" -eq 114 ] || die "original conflict list missing"
git -C "$B" cat-file -e "$PREPORT^{commit}" || die "ACK original preport missing"
git -C "$B" cat-file -e 'v6.6.158^{commit}' || die "Linux 6.6.158 tag absent"
T="$(mktemp -d "$R/k1-pte-dst.XXXXXXXX")"
trap 'rm -rf "$T"' EXIT
cat > "$T/manifest.txt" <<'MANIFEST'
ack|arch/arm64/include/asm/pgtable.h|b80b60f443f2e9e21daec43ac11897f2f5a56ca48133d71bc892cfb3537f902c|f8666e14df29b7f1d06e3cf276d338d5e67af289ac76f8888c7fb1e866d4a299|5
ack|arch/arm64/kernel/efi.c|4e52de9f65c810529e56884b220f2623c7d1b05de1d1f795a4c5f2ecd7e966b3|6f4a34bfd035270609a566bbe5bd92f1d045499bd952ef9f9068c7dd7c739023|1
ack|arch/arm64/kernel/mte.c|0aba1f4a991e522172e30725125eef364d70b95a8e853ff097f0fa53a7495eda|ae32f3161f1a8dbf9f17a06479c10413c867d9ca907634b4e17912fa283ed60b|1
ack|arch/arm64/kvm/guest.c|3687831da5b2945b0c38adf4deaf40b5eb9e73268082ae98450d9f34765f4367|efaa86fa003547cd55add9d7ac7212e25c5fb2c8fe1256aee5984bba55515622|1
ack|arch/arm64/mm/hugetlbpage.c|596a26213710748b02f02bcce0a746604e1419b6828d43198fc3b9000000535b|68e28cdc847c0edfb72c93e4b049731240645d4c6934a4932dfe102845fb90bf|9
ack|arch/arm64/mm/kasan_init.c|68f8c9c1b9433b57309e82e620bfbce92669bcdd75ecc697f96283b317aee7fd|08dfbfa4a7b2b708d8598a648d1b4a1efa6f44f5bddca2e02e935c696a696d1b|1
ack|arch/arm64/mm/pageattr.c|3fe7d0bdc60a99ad58a81682dc28080f98022c26e42cfcd18eddb4a5ce76308c|b651c2bab2348b74548759cbd33bb612fe6ba0f29faa47b259fc01bcac65422b|2
ack|arch/arm64/mm/trans_pgd.c|670060b6bccd36989f88573809e64d30972195dded8d8e5ad7864d0cf9e62c97|a964a75160feabb576d0a361544de0daca3bf8e7f04aea4c4970507db17af55e|1
stable|include/net/dst.h|c037ed32ee4facbe96b76e49103b6c1122055862d0618a02ae2f772e61503eba|ab21f62cdbed83455b8a991f966fd5b29d6bc2dcc84d48fdaa08a4f76ddfbeff|1
stable|net/core/dst.c|cb7e7af121fb23416c876c9faa6cb25d3e074bd50002db91ace45b8a921e56c0|70f093482ca92f9f9decddd088c1c56137ae4bc41f913efa79cc224caca5a34c|1
MANIFEST
python3 - "$W" "$B" "$T" <<'PY'
from pathlib import Path
import hashlib,re,subprocess,sys
w=Path(sys.argv[1]); b=Path(sys.argv[2]);t=Path(sys.argv[3])
rows=[r.split("|") for r in (t/"manifest.txt").read_text().splitlines() if r.strip()]
assert len(rows)==10 and len({r[1] for r in rows})==10,"manifest invalid"
p=re.compile(rb"(?ms)^<<<<<<< HEAD\n(.*?)^=======\n(.*?)^>>>>>>> v6\.6\.158\n")
fn=b"static inline struct net_device *skb_dst_dev(const struct sk_buff *skb)\n{\n\treturn dst_dev(skb_dst(skb));\n}\n\n"
for mode,path,old_sha,new_sha,count in rows:
    original=(w/path).read_bytes()
    assert hashlib.sha256(original).hexdigest()==old_sha,"input differs: "+path
    hits=list(p.finditer(original))
    assert len(hits)==int(count),"unexpected hunk count: "+path
    result=p.sub(lambda m: m.group(1 if mode=="ack" else 2),original)
    if path=="include/net/dst.h":
        assert result.count(fn)==2,"expected duplicate skb_dst_dev definition absent"
        result=result.replace(fn+fn,fn)
        assert result.count(fn)==1,"duplicate skb_dst_dev not removed"
        assert b"struct net_device __rcu *dev_rcu;" in result
        assert b"return dev_net_rcu(skb_dst_dev_rcu(skb));" in result
    if path=="net/core/dst.c":
        assert b"rcu_assign_pointer(dst->dev_rcu, blackhole_netdev);" in result
    assert b"<<<<<<< " not in result and b">>>>>>> " not in result,"unresolved markers: "+path
    assert hashlib.sha256(result).hexdigest()==new_sha,"postimage mismatch: "+path
    ref="HEAD" if mode=="ack" else "v6.6.158"
    control=subprocess.check_output(["git","-C",str(b),"show",f"{ref}:{path}"])
    assert result==control, f"resolved {path} does not match {ref} source"
    dst=t/"prepared"/path
    dst.parent.mkdir(parents=True,exist_ok=True)
    dst.write_bytes(result)
print("K1_ARM64_PTE_DST_PRECHECK_ALL_10_OK")
PY
commit_group() {
  local msg="$1"; shift
  local paths=( "$@" )
  for p in "${paths[@]}"; do cp "$T/prepared/$p" "$W/$p"; done
  git -C "$W" add -- "${paths[@]}"
  [ "$(git -C "$W" diff --cached --name-only | wc -l)" -eq "${#paths[@]}" ] || die "unexpected staged files"
  git -C "$W" diff --cached --check || die "staged whitespace error"
  git -C "$W" -c user.name="Annibale Kernel Port" -c user.email="kernel-port@localhost" commit -m "$msg"
}

echo '=== Preserve 8 compiled ACK arm64 PTE API files exactly ==='
commit_group "K1: retain compiled ACK arm64 PTE API across eight conflict files" \
  arch/arm64/include/asm/pgtable.h \
  arch/arm64/kernel/efi.c \
  arch/arm64/kernel/mte.c \
  arch/arm64/kvm/guest.c \
  arch/arm64/mm/hugetlbpage.c \
  arch/arm64/mm/kasan_init.c \
  arch/arm64/mm/pageattr.c \
  arch/arm64/mm/trans_pgd.c
echo '=== Integrate 6.6.158 DST RCU pair, remove duplicated auto-merge helper ==='
commit_group "K1: import coherent Linux 6.6.158 dst RCU files without duplicate helper" \
  include/net/dst.h net/core/dst.c

left=0
while IFS= read -r f || [ -n "$f" ]; do
  [ -n "$f" ] || continue
  if grep -q '^<<<<<<< ' "$W/$f"; then left=$((left+1)); fi
done < "$D/conflict-files.txt"
[ "$left" -eq 39 ] || die "unexpected conflict count: $left"
[ "$(git -C "$B" rev-parse HEAD)" = "$BASE" ] || die "original baseline changed"
[ -z "$(git -C "$B" status --porcelain)" ] || die "original baseline dirty"
[ -z "$(git -C "$W" status --porcelain)" ] || die "review dirty after commits"
echo 'K1_ARM64_PTE_DST_10_RESOLVED_REMAINING_39'
echo "K1_REVIEW_HEAD=$(git -C "$W" rev-parse HEAD)"
echo "K1_BASELINE_PRESERVED=$BASE"

echo '=== Archive exact source deltas for server-expiration recovery ==='
SHORT="$(git -C "$W" rev-parse --short=9 HEAD)"
OUT="$HOME/ANNIBALE_KERNEL_K1_RECOVERY_20261012_${SHORT}.tar.gz"
[ ! -e "$OUT" ] || die "recovery already exists"
mkdir -p "$T/recovery"
git -C "$B" diff --binary "$PREPORT" "$BASE" | gzip -1 > "$T/recovery/01_preport_to_compiled.patch.gz"
git -C "$B" diff --binary "$BASE" "$(git -C "$W" rev-parse HEAD)" | gzip -1 > "$T/recovery/02_compiled_to_review.patch.gz"
[ -s "$T/recovery/01_preport_to_compiled.patch.gz" ] || die "source patch 01 empty"
[ -s "$T/recovery/02_compiled_to_review.patch.gz" ] || die "source patch 02 empty"
cp "$D/conflict-files.txt" "$D/threeway-report.txt" "$T/recovery/"
cp "$T/manifest.txt" "$T/recovery/pte-dst-10-manifest.txt"
cp "$R/out-checkpoint-ABCDE/arch/arm64/boot/Image" "$T/recovery/compiled-Image"
cp "$R/out-checkpoint-ABCDE/Module.symvers" "$T/recovery/compiled-Module.symvers"
cp "$R/out-checkpoint-ABCDE/.config" "$T/recovery/compiled-config"
cat > "$T/recovery/README.txt" <<EOF
ANNIBALE K1 SOURCE RECOVERY. NOT BUILDABLE OR FLASHABLE.
Original ACK preport: $(git -C "$B" rev-parse "$PREPORT")
Compiled partial checkpoint: $BASE
Virtual Linux 6.6.158 review: $(git -C "$W" rev-parse HEAD)
Source reconstruction from EXACT preport using patch 01 and 02 in order.
39 unresolved conflicted paths plus unchecked auto-merged changes.
8 ARM64 conflict files are exactly unchanged from compiled ACK.
2 DST source files now match upstream stable v6.6.158; OEM ABI still unverified.
Included Image is from older partial port, NOT Linux 6.6.158.
EOF
(cd "$T/recovery" && sha256sum *.patch.gz compiled-* > SHA256SUMS)
tar -czf "$OUT.tmp" -C "$T/recovery" .
mv "$OUT.tmp" "$OUT"
sha256sum "$OUT"
ls -lh "$OUT"
echo "K1_RECOVERY_READY=$OUT"
echo 'K1_39_REMAIN_NOT_BUILDABLE_NOT_FLASHABLE'

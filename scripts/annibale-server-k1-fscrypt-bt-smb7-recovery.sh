#!/usr/bin/env bash
# K1: resolve seven audited files coherently: fscrypt ACK KMI, BT lifecycle, SMB2.
# Start post-batch7 review commit 7437daa5c; baseline remains 831d9bce8.
set -Eeuo pipefail
R="$HOME/annibale-kernel-port"
B="$R/staging-6.6.145"
W="$R/staging-6.6.158-virtual-review"
D="$R/report-6.6.158-direct"
BASE="831d9bce8371e23466e06129d1fbfcb6eadc1979"
START="7437daa5c5e4fdeb4a6809a1bed210bc52ffc182"
PREPORT="712c2cd5c"
die(){ printf 'STOP: %s\n' "$*" >&2; exit 2; }
echo '=== K1 fscrypt/BT/SMB7 preconditions ==='
[ "$(git -C "$B" rev-parse HEAD)" = "$BASE" ] || die 'compiled baseline HEAD changed'
[ "$(git -C "$W" rev-parse HEAD)" = "$START" ] || die 'review HEAD changed or batch already applied'
[ "$(git -C "$W" branch --show-current)" = "annibale-6.6.158-virtual-review-20261011" ] || die 'wrong review branch'
[ -z "$(git -C "$B" status --porcelain)" ] || die 'compiled baseline dirty'
[ -z "$(git -C "$W" status --porcelain)" ] || die 'review tree dirty'
[ -s "$D/conflict-files.txt" ] || die 'missing conflict list'
git -C "$B" cat-file -e "$PREPORT^{commit}" || die 'missing original pre-port commit'
TMP="$(mktemp -d "$R/k1-crypto-bt-smb.XXXXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/manifest.txt" <<'MANIFEST'
ack|fs/crypto/fscrypt_private.h|eaee67f1b494b636015fc025d36e68826ef6398729b98b79ae3694d2432bf399|0941b56a8e62758a5c9cb31d3e8f75442600ffb066ce17d455c0eaa1eb95e3f8|1
ack|fs/crypto/inline_crypt.c|8d3dcffb08456d8b8e61e7089a392cf773e8dc3e35bac160915c05b183e1b0a8|60385d30d28e8006275f7fcff84687578567afaf4158dfeabf4e28993a62305f|1
ack|include/linux/fscrypt.h|d091af9d00ec5c233401234ff015915bfcf6412c947dc6704cdb20a1da38ab7f|17aa93b195c8a00d39cb3cd5a13dbaab2fd7b5ee493ef47e3c46fac00ae57213|2
upstream|net/bluetooth/l2cap_sock.c|8fda16209314236bcb8d9413c18b6b8545aaadf02db31d188dbd63f43c78e0e9|125f99f2bf336628885a24520dca228cdad2a9921849a33c080af720808e9fda|1
upstream|net/bluetooth/mgmt.c|95f17574f43ca3a2ce242b58fcc171096996a8d9eab55738c32ee133d1d42f0d|c75ce92310edba4374dbba5fecca11c42ab75cdab1bacc39da84721591d0e9e7|2
upstream|net/bluetooth/hci_sync.c|5e21d729158fa40d231b9deed4aeeec0af43444cf7af2b9152a82968602308c7|32f476e3f57f7ccc529b56c84406d56862130e5ce385260c78ac35b538bcf82c|1
upstream|fs/smb/client/smb2ops.c|0655330529d1cca6e6f6d3ab79bd28ce9db4d59f571bc78cd37c7ff659cfaf9f|d46321566cf5e70dd6d3dbe871773ca53274785eeb1c1f5a16d7f6946e149e1e|2
MANIFEST

python3 - "$W" "$TMP" <<'PY'
from pathlib import Path
import sys,re,hashlib
w=Path(sys.argv[1]); t=Path(sys.argv[2])
rows=[r.split("|") for r in (t/"manifest.txt").read_text().splitlines() if r.strip()]
assert len(rows)==7 and len({r[1] for r in rows})==7,"bad manifest"
pattern=re.compile(rb"(?ms)^<<<<<<< HEAD\n(.*?)^=======\n(.*?)^>>>>>>> v6\.6\.158\n")
for mode,path,sha_old,sha_new,n in rows:
    source=(w/path).read_bytes()
    assert hashlib.sha256(source).hexdigest()==sha_old,"preimage changed "+path
    hits=list(pattern.finditer(source))
    assert len(hits)==int(n),"unexpected conflict count "+path
    fixed=pattern.sub(lambda m:m.group(1 if mode=="ack" else 2),source)
    assert b"<<<<<<< " not in fixed and b">>>>>>> " not in fixed,"markers remain "+path
    assert hashlib.sha256(fixed).hexdigest()==sha_new,"postimage changed "+path
    f=t/"prepared"/path
    f.parent.mkdir(parents=True,exist_ok=True)
    f.write_bytes(fixed)
def source(p): return (t/"prepared"/p).read_bytes()
private=source("fs/crypto/fscrypt_private.h")
assert b"#ifdef __GENKSYMS__\n\tstruct key\t\t*mk_users;\n#else\n\tstruct list_head\tmk_users;\n#endif" in private
crypt=source("fs/crypto/inline_crypt.c")
assert b"get_devices_new(sb, devs)" in crypt
assert b"return sb->s_cop->get_devices(sb, devs);" not in crypt
header=source("include/linux/fscrypt.h")
assert b"ANDROID_KABI_USE(1, unsigned int (*get_devices_new)" in header
assert b"ANDROID_KABI_RESERVE(2)" in header and b"ANDROID_OEM_DATA_ARRAY(1, 4)" in header
assert b"#ifdef CONFIG_FS_ENCRYPTION\n\n#ifdef CONFIG_FS_ENCRYPTION" not in header
l2=source("net/bluetooth/l2cap_sock.c")
assert b"lock_sock(sk);\n\tl2cap_sock_put_chan(sk);\n\trelease_sock(sk);" in l2
mgmt=source("net/bluetooth/mgmt.c")
assert mgmt.count(b"if (conn)\n\t\thci_conn_put(conn);")>=2
assert b"mgmt_cmd_complete(cmd->sk, cmd->hdev->id" in mgmt
sync=source("net/bluetooth/hci_sync.c")
assert b"hci_abort_conn_sync(hdev, conn," in sync
smb=source("fs/smb/client/smb2ops.c")
assert b"buf = kvzalloc(min_t(loff_t, len, SMB2_MAX_BUFFER_SIZE), GFP_KERNEL);" in smb
assert b"server->total_read = next_cmd ? next_cmd : pdu_length;" in smb
print("K1_FSCRYPT_BT_SMB7_PRECHECK_OK")
PY

commit_group(){
 local title="$1"; shift
 local files=( "$@" )
 for file in "${files[@]}"; do cp "$TMP/prepared/$file" "$W/$file"; done
 git -C "$W" add -- "${files[@]}"
 git -C "$W" diff --cached --check || die 'staged diff whitespace'
 [ "$(git -C "$W" diff --cached --name-only | wc -l)" -eq "${#files[@]}" ] || die 'unexpected staged paths'
 git -C "$W" -c user.name="Annibale Kernel Port" -c user.email="kernel-port@localhost" commit -m "$title"
}
echo '=== Preserve Android GKI fscrypt callbacks / ABI (3 files) ==='
commit_group "K1: retain Android KMI-safe fscrypt callbacks and GENKSYMS layout" \
 fs/crypto/fscrypt_private.h fs/crypto/inline_crypt.c include/linux/fscrypt.h
echo '=== Port upstream Bluetooth refcount, locking, abort paths (3 files) ==='
commit_group "K1: integrate stable Bluetooth L2CAP and HCI management lifecycle fixes" \
 net/bluetooth/l2cap_sock.c net/bluetooth/mgmt.c net/bluetooth/hci_sync.c
echo '=== Port independent SMB2 bounds / total-read updates (1 file) ==='
commit_group "K1: integrate stable SMB2 server response bounds and total-read" \
 fs/smb/client/smb2ops.c

count=0
while IFS= read -r p || [ -n "$p" ]; do
 [ -n "$p" ] || continue
 if grep -q '^<<<<<<< ' "$W/$p"; then count=$((count+1)); fi
done < "$D/conflict-files.txt"
[ "$count" -eq 52 ] || die "expected 52 remaining, found $count"
[ "$(git -C "$B" rev-parse HEAD)" = "$BASE" ] || die 'baseline changed'
[ -z "$(git -C "$B" status --porcelain)" ] || die 'baseline dirty'
[ -z "$(git -C "$W" status --porcelain)" ] || die 'review dirty'
echo "K1_FSCRYPT_BT_SMB7_RESOLVED_REMAINING_52"
echo "K1_REVIEW_HEAD=$(git -C "$W" rev-parse HEAD)"
echo "K1_BASELINE_PRESERVED=$BASE"

echo '=== Preserve WIP source and old compiled Image for server expiration ==='
SHORT="$(git -C "$W" rev-parse --short=9 HEAD)"
OUT="$HOME/ANNIBALE_KERNEL_K1_RECOVERY_20261012_${SHORT}.tar.gz"
[ ! -e "$OUT" ] || die 'recovery archive already exists'
mkdir -p "$TMP/recovery"
git -C "$B" diff --binary "$PREPORT" "$BASE" | gzip -1 > "$TMP/recovery/01_preport_to_compiled.patch.gz"
git -C "$B" diff --binary "$BASE" "$(git -C "$W" rev-parse HEAD)" | gzip -1 > "$TMP/recovery/02_compiled_to_review.patch.gz"
[ -s "$TMP/recovery/01_preport_to_compiled.patch.gz" ] || die 'patch 01 absent'
[ -s "$TMP/recovery/02_compiled_to_review.patch.gz" ] || die 'patch 02 absent'
cp "$D/conflict-files.txt" "$D/threeway-report.txt" "$TMP/recovery/"
cp "$TMP/manifest.txt" "$TMP/recovery/batch7-manifest.txt"
cp "$R/out-checkpoint-ABCDE/arch/arm64/boot/Image" "$TMP/recovery/compiled-Image"
cp "$R/out-checkpoint-ABCDE/Module.symvers" "$TMP/recovery/compiled-Module.symvers"
cp "$R/out-checkpoint-ABCDE/.config" "$TMP/recovery/compiled-config"
cat > "$TMP/recovery/README.txt" <<EOF
ANNIBALE K1 SOURCE RECOVERY (NOT BUILDABLE, NOT FLASHABLE).
Exact pre-port base: $(git -C "$B" rev-parse "$PREPORT")
Compiled partial checkpoint: $BASE
Experimental review WIP: $(git -C "$W" rev-parse HEAD)
From the exact pre-port SHA apply patch 01 and 02 in that order.
There are 52 unresolved conflict paths, with unverified auto-merges and OEM ABI.
The saved Image is NOT Linux 6.6.158.
EOF
(cd "$TMP/recovery" && sha256sum *.patch.gz compiled-* > SHA256SUMS)
tar -czf "$OUT.tmp" -C "$TMP/recovery" .
mv "$OUT.tmp" "$OUT"
sha256sum "$OUT"
ls -lh "$OUT"
echo "K1_RECOVERY_READY=$OUT"
echo "K1_52_REMAIN_NOT_BUILDABLE_NOT_FLASHABLE"

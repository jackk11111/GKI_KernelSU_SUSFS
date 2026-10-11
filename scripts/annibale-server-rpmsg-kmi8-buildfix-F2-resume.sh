#!/usr/bin/env bash
# Recovery after F2 r1: its upstream reverse patch was already applied
# but the script stopped before the read-only sysfs mitigation.
# This script must NOT reverse the upstream patch a second time.
set -Eeuo pipefail
R="$HOME/annibale-kernel-port"
S="$R/staging-6.6.145"
O="$R/out-checkpoint-ABCDE"
P="$R/rpmsg-upstream-964a44a.patch"
C="$S/drivers/rpmsg/rpmsg_core.c"
L="$R/checkpoint-F2-resume-build.log"
EXPECTED="c0368d069"
echo "=== CHECKPOINT AND PARTIAL F2 STATE ==="
test "$(git -C "$S" rev-parse --short=9 HEAD)" = "$EXPECTED"
test -s "$P"
test -f "$C"
expected="$(printf '%s\n' \
  drivers/rpmsg/qcom_glink_native.c \
  drivers/rpmsg/rpmsg_core.c \
  drivers/rpmsg/virtio_rpmsg_bus.c \
  include/linux/rpmsg.h | sort)"
actual="$(git -C "$S" diff --name-only | sort)"
if [[ "$actual" != "$expected" ]]; then
  echo "STOP: working files differ from the interrupted F2 stage"
  git -C "$S" status --short
  exit 2
fi
test -z "$(git -C "$S" diff --cached --name-only)"
git -C "$S" apply --check "$P" || {
  echo "STOP: upstream RPMSG patch was not completely reversed"
  exit 2
}
echo "F2_REVERSED_UPSTREAM_STATE_CONFIRMED"
echo "=== MAKE RPMSG DRIVER OVERRIDE READ-ONLY ==="
python3 - "$C" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
start_text = "static ssize_t driver_override_store("
end_text = "static ssize_t driver_override_show("
attr_rw = "static DEVICE_ATTR_RW(driver_override);"
assert s.count(start_text) == 1, "Expected one explicit RPMSG override store handler"
assert s.count(end_text) == 1, "Expected one RPMSG override show handler"
assert s.count(attr_rw) == 1, "Expected one read-write driver_override sysfs attribute"
start = s.index(start_text)
end = s.index(end_text, start)
store = s[start:end]
assert "driver_set_override(" in store, "Unexpected sysfs store implementation"
assert "return count;" in store, "Unexpected sysfs store return"
assert store.count("{") == store.count("}"), "Unbalanced store function"
assert "if (rpdev->driver_override)" in s, "Android legacy match path not restored"
assert "device_match_driver_override" not in s, "Upstream generic driver override remains"
assert "device_set_driver_override" not in s, "Upstream generic override setter remains"
s = s[:start] + s[end:]
s = s.replace(attr_rw, "static DEVICE_ATTR_RO(driver_override);")
assert "static ssize_t driver_override_store(" not in s
assert "static DEVICE_ATTR_RW(driver_override);" not in s
p.write_text(s)
print("F2_RO_OVERRIDE_OK")
PY
grep -Fq 'const char *driver_override;' "$S/include/linux/rpmsg.h"
! grep -Fq '.driver_override = true' "$C"
git -C "$S" diff --check
echo "=== COMMIT AND CUMULATIVE BACKUP ==="
git -C "$S" add -- \
    drivers/rpmsg/qcom_glink_native.c \
    drivers/rpmsg/rpmsg_core.c \
    drivers/rpmsg/virtio_rpmsg_bus.c \
    include/linux/rpmsg.h
git -C "$S" diff --cached --check
git -C "$S" -c user.name="Annibale Port" \
    -c user.email="annibale@localhost" \
    commit -m "WIP: RPMSG KMI8 compatible override mitigation F2"
test -z "$(git -C "$S" status --porcelain)"
git -C "$S" diff --binary HEAD~8 HEAD | gzip -1 \
    > "$HOME/ANNIBALE_6.6.145_PARTIAL_F2.patch.gz"
git -C "$S" log -2 --oneline
ls -lh "$HOME/ANNIBALE_6.6.145_PARTIAL_F2.patch.gz"

echo "=== INCREMENTAL BUILD IMAGE + MODULES (NO FLASH) ==="
if make -C "$S" O="$O" ARCH=arm64 LLVM=1 LLVM_IAS=1 \
    HOSTCC=/usr/bin/gcc HOSTLD=/usr/bin/ld HOSTAR=/usr/bin/ar \
    KCFLAGS=-D__ANDROID_COMMON_KERNEL__ -j6 Image modules 2>&1 |
    tee "$L" |
    awk '/error:|fatal error:|Error [0-9]+|undefined reference|No rule to make target/ {
           print; fflush()
         }
         NR % 400 == 0 {
           print "BUILD_PROGRESS_LINES=" NR; fflush()
         }'; then
  echo "=== IMAGE ==="
  ls -lh "$O/arch/arm64/boot/Image" "$O/Module.symvers" 2>/dev/null || true
  echo "KERNEL_COMPILE_OK_F2"
else
  echo "=== BUILD ERRORS ==="
  grep -nE 'error:|fatal error:|Error [0-9]+|undefined reference|No rule to make target' \
      "$L" | tail -n 30 || true
  tail -n 55 "$L"
  echo "KERNEL_COMPILE_FAILED_F2"
fi
echo "F2_SAVED_NOT_FLASHABLE"

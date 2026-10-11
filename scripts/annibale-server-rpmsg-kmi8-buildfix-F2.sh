#!/usr/bin/env bash
# Staging-only, KMI8-preserving RPMSG compatibility backport.
# Linux stable 964a44a expects generic driver_override fields in
# struct device/bus_type which are not present in this Android ACK.
# Reverse that non-portable commit and disable concurrent userspace
# writes to rpmsg_device.driver_override (read-only sysfs).
# This is a mitigation, NOT a substitute for full upstream functionality.
set -Eeuo pipefail
R="$HOME/annibale-kernel-port"
S="$R/staging-6.6.145"
ACK="$R/ack"
O="$R/out-checkpoint-ABCDE"
P="$R/rpmsg-upstream-964a44a.patch"
LOG="$R/checkpoint-F2-build.log"
SHA="964a44a990d617ca41f23fff8e9569c694572b72"
EXPECTED="c0368d069"
echo "=== F2: VERIFY CHECKPOINT ==="
test "$(git -C "$S" rev-parse --short=9 HEAD)" = "$EXPECTED"
test -z "$(git -C "$S" status --porcelain)"
test "$(git -C "$ACK" rev-parse "$SHA")" = "$SHA"
git -C "$ACK" show --format= --binary --no-ext-diff "$SHA" > "$P"
echo "=== REVERSE NON-PORTABLE RPMSG COMMIT ==="
git -C "$S" apply -R --check "$P"
git -C "$S" apply -R "$P"

echo "=== PREVENT RPMSG DRIVER_OVERRIDE SYSFS UAF ==="
python3 - "$S/drivers/rpmsg/rpmsg_core.c" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = "rpmsg_string_attr(driver_override, driver_override);"
assert text.count(old) == 1, f"Unexpected RPMSG override declarations: {text.count(old)}"
new = """/*
 * Android KMI8 retains rpmsg_device.driver_override, so it cannot
 * use the newer driver-core override representation. Keep this
 * attribute read-only: changing it during driver matching would
 * permit a use-after-free (upstream stable 964a44a).
 * Registration-time override is still supported before device_add().
 */
static ssize_t driver_override_show(struct device *dev,
                                    struct device_attribute *attr, char *buf)
{
    struct rpmsg_device *rpdev = to_rpmsg_device(dev);
    const char *name = READ_ONCE(rpdev->driver_override);

    return sysfs_emit(buf, "%s\\n", name ? name : "");
}
static DEVICE_ATTR_RO(driver_override);"""
path.write_text(text.replace(old, new))
PY
test "$(grep -c 'static DEVICE_ATTR_RO(driver_override)' "$S/drivers/rpmsg/rpmsg_core.c")" = 1
! grep -q 'device_match_driver_override' "$S/drivers/rpmsg/rpmsg_core.c"
! grep -q 'device_set_driver_override' "$S/drivers/rpmsg/rpmsg_core.c"
grep -q 'const char \*driver_override;' "$S/include/linux/rpmsg.h"
git -C "$S" diff --check
echo "=== SAVE F2 CHECKPOINT ==="
git -C "$S" add drivers/rpmsg/qcom_glink_native.c drivers/rpmsg/rpmsg_core.c drivers/rpmsg/virtio_rpmsg_bus.c include/linux/rpmsg.h
git -C "$S" -c user.name="Annibale Port" -c user.email="annibale@localhost" commit \
  -m "WIP: KMI8-safe RPMSG driver override mitigation (F2)"
git -C "$S" diff --binary HEAD~8 HEAD | gzip -1 \
  > "$HOME/ANNIBALE_6.6.145_PARTIAL_F2.patch.gz"
git -C "$S" log -2 --oneline

echo "=== INCREMENTAL COMPILATION IMAGE + MODULES ==="
if make -C "$S" O="$O" ARCH=arm64 LLVM=1 LLVM_IAS=1 \
      HOSTCC=/usr/bin/gcc HOSTLD=/usr/bin/ld HOSTAR=/usr/bin/ar \
      KCFLAGS=-D__ANDROID_COMMON_KERNEL__ -j6 Image modules 2>&1 |
    tee "$LOG" |
    awk '/error:|fatal error:|Error [0-9]+|undefined reference|No rule to make target/ {
             print; fflush()
         }
         NR % 400 == 0 {
             print "BUILD_PROGRESS_LINES=" NR; fflush()
         }'; then
  echo "=== COMPILE SUCCEEDED ==="
  ls -lh "$O/arch/arm64/boot/Image" "$O/Module.symvers" 2>/dev/null || true
  echo "KERNEL_COMPILE_OK_F2"
else
  echo "=== COMPILE FAILED ==="
  grep -n -E 'error:|fatal error:|Error [0-9]+|undefined reference|No rule to make target' \
    "$LOG" | tail -n 30 || true
  tail -n 60 "$LOG"
  echo "KERNEL_COMPILE_FAILED_F2"
fi
echo "=== BACKUP ==="
ls -lh "$HOME/ANNIBALE_6.6.145_PARTIAL_F2.patch.gz"
echo "F2_DONE_NOT_FLASHABLE"

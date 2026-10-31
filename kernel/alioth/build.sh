#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
WORK="${RUNNER_TEMP:-/tmp}/alioth-kernel-build"
KERNEL_DIR="$WORK/kernel"
OUT="$WORK/out"
ART="$ROOT/alioth-artifacts"
ANDROID_COMMON_REF="${ANDROID_COMMON_REF:-android16-6.12-2026-09}"
SUSFS_BRANCH="gki-android16-6.12"
PMA_COMMIT="fef537b30e81c05cd226ca6b13ca3c888c361240"
PMA_BASE="https://raw.githubusercontent.com/nasaarmas/pmaports-alioth/$PMA_COMMIT/linux-postmarketos-qcom-sm8250-alioth"
DEVICE_PATCH="0001-Added-POCO-F3-dts-panel-and-touchscreen-drivers.patch"
DEVICE_PATCH_SHA512="3155103c7c498ae0d3e00117cefd7364e8b8100aa9cad2967086904d77e2aab16063b60a2d4603b29190c2aa96ac7dc81e9ceda01dadada1f109573897d74ac4"
PMOS_CONFIG="config-postmarketos-qcom-sm8250-alioth.aarch64"
PMOS_CONFIG_SHA512="a1a7290178c83125b7bb6ffe70bd447f44002565d59a5ca38bd82ec9f15f2c62ec2a1f44f08ac85c296eedf4f102199c6550a2d8c414a4238d07bdca99da1b96"
KSU_TAG="v3.4.2"
KSU_COMMIT="4c706b5938665866ebe16944a481a7b91e3396af"
AK3_COMMIT="41f04bdb4ee30a44e429c2c1131d5e8bb32b15f1"
MANAGER_URL="https://github.com/KernelSU-Next/KernelSU-Next/releases/download/v3.4.2/KernelSU_Next_v3.4.2_33355-release.apk"
MANAGER_SHA256="774a5511f7034a4930e881114e202319cbdc34c5aaaa5c7c6b6d2902364e4c58"

mkdir -p "$WORK" "$ART"
rm -rf "$KERNEL_DIR" "$OUT" "$WORK/KernelSU-Next" "$WORK/susfs4ksu" "$WORK/AnyKernel3" "$WORK/modules"
rm -f "$ART"/*

retry() {
  local n=0
  until "$@"; do
    n=$((n + 1))
    if [ "$n" -ge 5 ]; then
      echo "ERROR: command failed after 5 attempts: $*" >&2
      return 1
    fi
    sleep $((n * 4))
  done
}

echo "== Source: Android Common Kernel $ANDROID_COMMON_REF =="
retry git clone --depth=1 --single-branch --branch "$ANDROID_COMMON_REF" \
  https://android.googlesource.com/kernel/common "$KERNEL_DIR"
ANDROID_COMMON_COMMIT="$(git -C "$KERNEL_DIR" rev-parse HEAD)"
ANDROID_COMMON_DATE="$(git -C "$KERNEL_DIR" show -s --format=%cI HEAD)"
KERNEL_VERSION="$(make -s -C "$KERNEL_DIR" ARCH=arm64 kernelversion)"
KERNEL_SUBLEVEL="${KERNEL_VERSION##*.}"
echo "ANDROID_COMMON_COMMIT=$ANDROID_COMMON_COMMIT"
echo "ANDROID_COMMON_DATE=$ANDROID_COMMON_DATE"
echo "KERNEL_VERSION=$KERNEL_VERSION"
echo "KERNEL_SUBLEVEL=$KERNEL_SUBLEVEL"

echo "== Fetch and verify the alioth mainline device patch =="
retry curl -fL --retry 4 --retry-delay 3 \
  "$PMA_BASE/$DEVICE_PATCH" -o "$WORK/$DEVICE_PATCH"
echo "$DEVICE_PATCH_SHA512  $WORK/$DEVICE_PATCH" | sha512sum -c -
# The pinned mainline patch has two one-line Makefile hunks whose surrounding
# lists were reordered in Android Common 6.18. Apply every other hunk verbatim,
# then add those two entries idempotently instead of changing source code.
git -C "$KERNEL_DIR" apply --check --verbose \
  --exclude=arch/arm64/boot/dts/qcom/Makefile \
  --exclude=drivers/gpu/drm/panel/Makefile "$WORK/$DEVICE_PATCH"
git -C "$KERNEL_DIR" apply \
  --exclude=arch/arm64/boot/dts/qcom/Makefile \
  --exclude=drivers/gpu/drm/panel/Makefile "$WORK/$DEVICE_PATCH"
python3 - "$KERNEL_DIR" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
entries = {
    "arch/arm64/boot/dts/qcom/Makefile":
        "dtb-$(CONFIG_ARCH_QCOM) += sm8250-xiaomi-alioth.dtb",
    "drivers/gpu/drm/panel/Makefile":
        "obj-$(CONFIG_DRM_PANEL_SAMSUNG_AMS667XX01) += panel-samsung-ams667xx01.o",
}
for relative, entry in entries.items():
    path = root / relative
    content = path.read_text()
    if entry not in content.splitlines():
        with path.open("a") as stream:
            if content and not content.endswith("\n"):
                stream.write("\n")
            stream.write(entry + "\n")
    if entry not in path.read_text().splitlines():
        raise SystemExit(f"Failed to register alioth build entry in {relative}")
    print(f"MAKEFILE_ENTRY=PASS {relative}: {entry}")
PY

echo "== Fetch and verify the known alioth mainline config =="
retry curl -fL --retry 4 --retry-delay 3 \
  "$PMA_BASE/$PMOS_CONFIG" -o "$WORK/$PMOS_CONFIG"
echo "$PMOS_CONFIG_SHA512  $WORK/$PMOS_CONFIG" | sha512sum -c -

echo "== Integrate official KernelSU Next $KSU_TAG =="
retry git clone --depth=1 --branch "$KSU_TAG" \
  https://github.com/KernelSU-Next/KernelSU-Next.git "$WORK/KernelSU-Next"
ACTUAL_KSU_COMMIT="$(git -C "$WORK/KernelSU-Next" rev-parse HEAD)"
test "$ACTUAL_KSU_COMMIT" = "$KSU_COMMIT"
git -C "$WORK/KernelSU-Next" fetch --unshallow --tags origin
ln -s "$WORK/KernelSU-Next/kernel" "$KERNEL_DIR/drivers/kernelsu"
grep -qF 'obj-$(CONFIG_KSU) += kernelsu/' "$KERNEL_DIR/drivers/Makefile" || \
  printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$KERNEL_DIR/drivers/Makefile"
grep -qF 'source "drivers/kernelsu/Kconfig"' "$KERNEL_DIR/drivers/Kconfig" || \
  sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$KERNEL_DIR/drivers/Kconfig"

echo "== Integrate SUSFS for Android16-6.12 (Evolution X Android17 userspace) =="
retry git clone --depth=1 --single-branch --branch "$SUSFS_BRANCH" \
  https://gitlab.com/simonpunk/susfs4ksu.git "$WORK/susfs4ksu"
SUSFS_COMMIT="$(git -C "$WORK/susfs4ksu" rev-parse HEAD)"
SUSFS_DESCRIBE="$(git -C "$WORK/susfs4ksu" describe --tags --always 2>/dev/null || git -C "$WORK/susfs4ksu" rev-parse --short HEAD)"
SUSFS_PATCH="$WORK/susfs4ksu/kernel_patches/50_add_susfs_in_gki-android16-6.12.patch"
test -s "$SUSFS_PATCH"
test -d "$WORK/susfs4ksu/kernel_patches/fs"
test -d "$WORK/susfs4ksu/kernel_patches/include/linux"
cp -av "$WORK/susfs4ksu/kernel_patches/fs/"* "$KERNEL_DIR/fs/"
cp -av "$WORK/susfs4ksu/kernel_patches/include/linux/"* "$KERNEL_DIR/include/linux/"
# Android 16 / 6.12 SUSFS compatibility transforms. These mirror the
# maintained 6.12 path in this repository's SUSFS actions. Temporary edits
# only reshape source context so the upstream patch can apply.
DMA_INCLUDE_STATE="$WORK/exec_dma_include.json"
VMA_RENAME_STATE="$WORK/vma_data_pages.count"

if [ "$KERNEL_SUBLEVEL" -ge 58 ]; then
  python3 - "$KERNEL_DIR/fs/exec.c" "$DMA_INCLUDE_STATE" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
state_path = pathlib.Path(sys.argv[2])
lines = path.read_text().splitlines(keepends=True)
needle = "#include <linux/dma-buf.h>"
matches = [i for i, line in enumerate(lines) if line.strip() == needle]
if len(matches) > 1:
    raise SystemExit(f"expected at most one {needle}, found {len(matches)}")
state = {"removed": False}
if matches:
    index = matches[0]
    state = {
        "removed": True,
        "before": lines[index - 1].rstrip("\n") if index > 0 else None,
        "after": lines[index + 1].rstrip("\n") if index + 1 < len(lines) else None,
    }
    del lines[index]
    path.write_text("".join(lines))
state_path.write_text(json.dumps(state))
print(f"SUSFS_FAKE_EXEC_DMA_INCLUDE_REMOVED={state['removed']}")
PY
fi

if [ "$KERNEL_SUBLEVEL" -ge 69 ]; then
  python3 - "$KERNEL_DIR/fs/proc/task_mmu.c" "$VMA_RENAME_STATE" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
count = text.count("vma_data_pages")
if count:
    path.write_text(text.replace("vma_data_pages", "vma_pages"))
pathlib.Path(sys.argv[2]).write_text(str(count))
print(f"SUSFS_FAKE_VMA_DATA_PAGES_RENAMES={count}")
PY
fi

if [ "$KERNEL_SUBLEVEL" -ge 92 ]; then
  python3 "$ROOT/.github/scripts/susfs_fake_612.py" \
    "$KERNEL_DIR/fs/proc/task_mmu.c" apply
fi

patch --batch --forward -p1 -d "$KERNEL_DIR" < "$SUSFS_PATCH"


# Restore the temporary 6.12 patch-context transforms before compiling.
if [ "$KERNEL_SUBLEVEL" -ge 92 ]; then
  python3 "$ROOT/.github/scripts/susfs_fake_612.py" \
    "$KERNEL_DIR/fs/proc/task_mmu.c" revert
fi

if [ "$KERNEL_SUBLEVEL" -ge 69 ]; then
  python3 - "$KERNEL_DIR/fs/proc/task_mmu.c" "$VMA_RENAME_STATE" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
count = int(pathlib.Path(sys.argv[2]).read_text().strip() or "0")
text = path.read_text()
if count:
    if text.count("vma_pages") < count:
        raise SystemExit("cannot restore the original vma_data_pages tokens")
    text = text.replace("vma_pages", "vma_data_pages", count)
    path.write_text(text)
print(f"SUSFS_FAKE_VMA_DATA_PAGES_RESTORED={count}")
PY
fi

if [ "$KERNEL_SUBLEVEL" -ge 58 ] && [ -s "$DMA_INCLUDE_STATE" ]; then
  python3 - "$KERNEL_DIR/fs/exec.c" "$DMA_INCLUDE_STATE" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
state = json.loads(pathlib.Path(sys.argv[2]).read_text())
needle = "#include <linux/dma-buf.h>"
if state.get("removed"):
    lines = path.read_text().splitlines(keepends=True)
    count = sum(line.strip() == needle for line in lines)
    if count == 0:
        before = state.get("before")
        after = state.get("after")
        before_hits = [i for i, line in enumerate(lines) if line.rstrip("\n") == before] if before else []
        after_hits = [i for i, line in enumerate(lines) if line.rstrip("\n") == after] if after else []
        if len(before_hits) == 1:
            insert_at = before_hits[0] + 1
        elif len(after_hits) == 1:
            insert_at = after_hits[0]
        else:
            raise SystemExit("cannot restore linux/dma-buf.h at its original include position")
        lines.insert(insert_at, needle + "\n")
        path.write_text("".join(lines))
    elif count != 1:
        raise SystemExit(f"expected one restored {needle}, found {count}")
print(f"SUSFS_FAKE_EXEC_DMA_INCLUDE_RESTORED={state.get('removed', False)}")
PY
fi

TASK_MMU="$KERNEL_DIR/fs/proc/task_mmu.c"
if grep -q 'VMA_PAD_START(' "$TASK_MMU" && \
   ! grep -qE '#include <linux/pgsize_migration(_inline)?\.h>|define VMA_PAD_START' "$TASK_MMU"; then
  sed -i '1a #ifndef VMA_PAD_START\n#define VMA_PAD_START(vma) ((vma)->vm_end)\n#endif' "$TASK_MMU"
  echo "SUSFS_VMA_PAD_START_FALLBACK=ADDED"
fi


echo "== Configure Android + alioth + KSU/SUSFS =="
mkdir -p "$OUT"
cp "$WORK/$PMOS_CONFIG" "$OUT/.config"
make -C "$KERNEL_DIR" O="$OUT" ARCH=arm64 LLVM=-21 LLVM_IAS=1 \
  CC=clang-21 HOSTCC=clang-21 olddefconfig

"$KERNEL_DIR/scripts/kconfig/merge_config.sh" -m -O "$OUT" \
  "$OUT/.config" "$ROOT/kernel/alioth/alioth.config"
make -C "$KERNEL_DIR" O="$OUT" ARCH=arm64 LLVM=-21 LLVM_IAS=1 \
  CC=clang-21 HOSTCC=clang-21 olddefconfig

require_y() {
  local symbol="$1"
  if ! grep -qx "CONFIG_${symbol}=y" "$OUT/.config"; then
    echo "ERROR: required CONFIG_${symbol}=y was not selected by Kconfig" >&2
    grep -E "^(# )?CONFIG_${symbol}(=| )" "$OUT/.config" || true
    exit 1
  fi
}
for symbol in \
  KSU KSU_SUSFS KSU_SUSFS_SUS_PATH KSU_SUSFS_SUS_MOUNT \
  KSU_SUSFS_SUS_KSTAT KSU_SUSFS_SPOOF_UNAME \
  KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
  KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG KSU_SUSFS_SUS_MAP \
  KSU_SUSFS_OPEN_REDIRECT ANDROID_BINDER_IPC ANDROID_BINDERFS \
  DRM_MSM DRM_PANEL_SAMSUNG_AMS667XX01 TOUCHSCREEN_FT8756 \
  SCSI_UFSHCD SCSI_UFS_QCOM F2FS_FS EROFS_FS \
  CFG80211 MAC80211 ATH11K ATH11K_PCI MHI_BUS MHI_BUS_PCI_GENERIC \
  BT_QCA BT_HCIUART RPMSG_QCOM_GLINK RPMSG_QCOM_GLINK_RPM \
  RPMSG_QCOM_GLINK_SMEM USB_DWC3_QCOM SERIAL_QCOM_GENI \
  I2C_QCOM_GENI SPI_QCOM_GENI QCOM_GPI_DMA QCOM_GENI_SE \
  TYPEC_QCOM_PMIC SND_SOC_QDSP6; do
  require_y "$symbol"
done

KERNEL_RELEASE="$(make -s -C "$KERNEL_DIR" O="$OUT" ARCH=arm64 LLVM=-21 \
  CC=clang-21 HOSTCC=clang-21 LOCALVERSION=-alioth-a17 kernelrelease)"
echo "KERNEL_RELEASE=$KERNEL_RELEASE"

echo "== Build Image, DTBs and modules =="
make -C "$KERNEL_DIR" O="$OUT" ARCH=arm64 LLVM=-21 LLVM_IAS=1 \
  CC=clang-21 HOSTCC=clang-21 \
  KBUILD_BUILD_USER=alioth KBUILD_BUILD_HOST=github-actions \
  KBUILD_BUILD_VERSION=1 LOCALVERSION=-alioth-a17 \
  -j"$(nproc)" Image dtbs modules

IMAGE="$OUT/arch/arm64/boot/Image"
DTB="$OUT/arch/arm64/boot/dts/qcom/sm8250-xiaomi-alioth.dtb"
test -s "$IMAGE"
test -s "$DTB"
cat "$IMAGE" "$DTB" > "$ART/Image-dtb"
cp "$IMAGE" "$ART/Image"
cp "$DTB" "$ART/sm8250-xiaomi-alioth.dtb"
cp "$OUT/.config" "$ART/kernel.config"

echo "== Install modules for audit (not flashed by the first test package) =="
make -C "$KERNEL_DIR" O="$OUT" ARCH=arm64 LLVM=-21 LLVM_IAS=1 \
  CC=clang-21 HOSTCC=clang-21 \
  LOCALVERSION=-alioth-a17 INSTALL_MOD_PATH="$WORK/modules" INSTALL_MOD_STRIP=1 modules_install
tar --zstd -cf "$ART/modules-$KERNEL_RELEASE.tar.zst" -C "$WORK/modules" .

echo "== Package AnyKernel3 test ZIP =="
retry git clone --depth=1 https://github.com/osm0sis/AnyKernel3.git "$WORK/AnyKernel3"
git -C "$WORK/AnyKernel3" fetch --depth=1 origin "$AK3_COMMIT"
git -C "$WORK/AnyKernel3" checkout --detach "$AK3_COMMIT"
rm -rf "$WORK/AnyKernel3/.git"
cp "$ART/Image-dtb" "$WORK/AnyKernel3/Image-dtb"

cat > "$WORK/AnyKernel3/anykernel.sh" <<'AK3'
### POCO F3 (alioth) EvoX Android 17 userspace / Android16-6.12 kernel
properties() { '
kernel.string=Alioth EvoX A17 | android16-6.12 | KernelSU Next v3.4.2 | SUSFS 2.3.0
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=alioth
'; }

BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

dump_boot;

# Mainline alioth instructions require the active DTBO slot to be erased.
# Validate the target and size before writing boot, then erase after repacking.
DTBO_PART="/dev/block/bootdevice/by-name/dtbo${SLOT:-}";
[ -e "$DTBO_PART" ] || DTBO_PART="/dev/block/bootdevice/by-name/dtbo";
DTBO_BLOCKS=0;
if [ -e "$DTBO_PART" ]; then
  if ! command -v blockdev >/dev/null 2>&1 || ! command -v dd >/dev/null 2>&1; then
    abort "blockdev/dd unavailable; refusing to flash with the old DTBO active."
  fi
  DTBO_BYTES="$(blockdev --getsize64 "$DTBO_PART")";
  DTBO_BLOCKS=$((DTBO_BYTES / 4096));
  if [ "$DTBO_BLOCKS" -le 0 ]; then
    abort "Could not determine the DTBO partition size."
  fi
fi

write_boot;

if [ "$DTBO_BLOCKS" -gt 0 ]; then
  ui_print "Erasing active DTBO partition ($DTBO_BYTES bytes)...";
  dd if=/dev/zero of="$DTBO_PART" bs=4096 count="$DTBO_BLOCKS" conv=fsync || abort "DTBO erase failed.";
  sync;
else
  ui_print "No active DTBO partition found; skipped DTBO erase.";
fi
AK3

(
  cd "$WORK/AnyKernel3"
  zip -qr "$ART/Alioth-EvoX-Android17-android16-6.12-KSU-Next-v3.4.2-SUSFS-2.3.0.zip" .
)

echo "== Fetch matching KernelSU Next manager =="
retry curl -fL --retry 4 --retry-delay 3 "$MANAGER_URL" -o "$ART/KernelSU_Next_v3.4.2_33355-release.apk"
echo "$MANAGER_SHA256  $ART/KernelSU_Next_v3.4.2_33355-release.apk" | sha256sum -c -

cat > "$ART/BuildInfo.txt" <<INFO
DEVICE=POCO F3 (alioth)
ROM_TARGET=Evolution X Android 17 userspace
KERNEL_BASE=Android Common android16-6.12
KERNEL_COMMON_KMI=android16-6.12
ANDROID_COMMON_REF=$ANDROID_COMMON_REF
ANDROID_COMMON_COMMIT=$ANDROID_COMMON_COMMIT
ANDROID_COMMON_COMMIT_DATE=$ANDROID_COMMON_DATE
KERNEL_VERSION=$KERNEL_VERSION
KERNEL_RELEASE=$KERNEL_RELEASE
DEVICE_PATCH_REPO=nasaarmas/pmaports-alioth
DEVICE_PATCH_COMMIT=$PMA_COMMIT
DEVICE_PATCH_SHA512=$DEVICE_PATCH_SHA512
DEVICE_PATCH_MAKEFILE_ADAPTATION=two idempotent append-only entries; remaining patch hunks applied verbatim
PMOS_CONFIG_SHA512=$PMOS_CONFIG_SHA512
KERNELSU_NEXT_TAG=$KSU_TAG
KERNELSU_NEXT_COMMIT=$ACTUAL_KSU_COMMIT
SUSFS_BRANCH=$SUSFS_BRANCH
SUSFS_COMMIT=$SUSFS_COMMIT
SUSFS_DESCRIBE=$SUSFS_DESCRIBE
ANYKERNEL3_COMMIT=$AK3_COMMIT
MANAGER_SHA256=$MANAGER_SHA256
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_ANDROID_BINDERFS=y
DTB=sm8250-xiaomi-alioth.dtb
DTBO_POLICY=erase active slot (mainline alioth port requirement)
NOTE=Experimental kernel build only; Android runtime/vendor ABI compatibility is not yet validated.
INFO

(
  cd "$ART"
  sha256sum Image Image-dtb sm8250-xiaomi-alioth.dtb kernel.config \
    "Alioth-Android17-6.18-KSU-Next-v3.4.2-SUSFS-2.3.0.zip" \
    "KernelSU_Next_v3.4.2_33355-release.apk" > SHA256SUMS
)

echo "BUILD_RESULT=PASS"
echo "KERNEL_RELEASE=$KERNEL_RELEASE"
echo "KSU_NEXT=$ACTUAL_KSU_COMMIT"
echo "SUSFS=$SUSFS_COMMIT"
echo "ARTIFACTS=$ART"

#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
WORK="${RUNNER_TEMP:-/tmp}/alioth-kernel-build"
KERNEL_DIR="$WORK/kernel"
OUT="$WORK/out"
ART="$ROOT/alioth-artifacts"
ANDROID_COMMON_REF="${ANDROID_COMMON_REF:-android17-6.18}"
SUSFS_BRANCH="gki-android17-6.18"
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
echo "ANDROID_COMMON_COMMIT=$ANDROID_COMMON_COMMIT"
echo "ANDROID_COMMON_DATE=$ANDROID_COMMON_DATE"
echo "KERNEL_VERSION=$KERNEL_VERSION"

echo "== Fetch and verify the alioth mainline device patch =="
retry curl -fL --retry 4 --retry-delay 3 \
  "$PMA_BASE/$DEVICE_PATCH" -o "$WORK/$DEVICE_PATCH"
echo "$DEVICE_PATCH_SHA512  $WORK/$DEVICE_PATCH" | sha512sum -c -
git -C "$KERNEL_DIR" apply --check --verbose "$WORK/$DEVICE_PATCH"
git -C "$KERNEL_DIR" apply "$WORK/$DEVICE_PATCH"

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

echo "== Integrate SUSFS 2.3.0 for Android 17 / 6.18 =="
retry git clone --depth=1 --single-branch --branch "$SUSFS_BRANCH" \
  https://gitlab.com/simonpunk/susfs4ksu.git "$WORK/susfs4ksu"
SUSFS_COMMIT="$(git -C "$WORK/susfs4ksu" rev-parse HEAD)"
SUSFS_PATCH="$WORK/susfs4ksu/kernel_patches/50_add_susfs_in_gki-android17-6.18.patch"
test -s "$SUSFS_PATCH"
test -d "$WORK/susfs4ksu/kernel_patches/fs"
test -d "$WORK/susfs4ksu/kernel_patches/include/linux"
cp -av "$WORK/susfs4ksu/kernel_patches/fs/"* "$KERNEL_DIR/fs/"
cp -av "$WORK/susfs4ksu/kernel_patches/include/linux/"* "$KERNEL_DIR/include/linux/"
patch --batch --forward -p1 -d "$KERNEL_DIR" < "$SUSFS_PATCH"

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
### POCO F3 (alioth) experimental Android 17 / Linux 6.18 kernel
properties() { '
kernel.string=Alioth Android17 Linux 6.18 | KernelSU Next v3.4.2 | SUSFS 2.3.0
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
  zip -qr "$ART/Alioth-Android17-6.18-KSU-Next-v3.4.2-SUSFS-2.3.0.zip" .
)

echo "== Fetch matching KernelSU Next manager =="
retry curl -fL --retry 4 --retry-delay 3 "$MANAGER_URL" -o "$ART/KernelSU_Next_v3.4.2_33355-release.apk"
echo "$MANAGER_SHA256  $ART/KernelSU_Next_v3.4.2_33355-release.apk" | sha256sum -c -

cat > "$ART/BuildInfo.txt" <<INFO
DEVICE=POCO F3 (alioth)
ANDROID_COMMON_REF=$ANDROID_COMMON_REF
ANDROID_COMMON_COMMIT=$ANDROID_COMMON_COMMIT
ANDROID_COMMON_COMMIT_DATE=$ANDROID_COMMON_DATE
KERNEL_VERSION=$KERNEL_VERSION
KERNEL_RELEASE=$KERNEL_RELEASE
DEVICE_PATCH_REPO=nasaarmas/pmaports-alioth
DEVICE_PATCH_COMMIT=$PMA_COMMIT
DEVICE_PATCH_SHA512=$DEVICE_PATCH_SHA512
PMOS_CONFIG_SHA512=$PMOS_CONFIG_SHA512
KERNELSU_NEXT_TAG=$KSU_TAG
KERNELSU_NEXT_COMMIT=$ACTUAL_KSU_COMMIT
SUSFS_BRANCH=$SUSFS_BRANCH
SUSFS_COMMIT=$SUSFS_COMMIT
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

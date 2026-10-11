#!/usr/bin/env bash
# Compile-only gate for the exact Android GKI KMI8 Group ABCDE checkpoint.
# No kernel install, no packaging, no edit to EvoX ROM or source worktree.
set -Eeuo pipefail
ROOT="$HOME/annibale-kernel-port"
SOURCE="$ROOT/staging-6.6.145"
OUTPUT="$ROOT/out-checkpoint-ABCDE"
ROM="$HOME/evox-annibale-a17"
EXPECTED="3a24d5461"
LOG="$ROOT/checkpoint-ABCDE-build.log"
CFGLOG="$ROOT/checkpoint-ABCDE-config.log"
STATUS="$ROOT/checkpoint-ABCDE-status.txt"

echo "[1/4] Verify checkpoint; preserve EvoX ROM and original GKI source"
test -f "$SOURCE/Makefile" || { echo "MISSING_SOURCE=$SOURCE"; exit 2; }
test -f "$ROM/build/envsetup.sh" || { echo "MISSING_ROM_WORKSPACE=$ROM"; exit 2; }
actual="$(git -C "$SOURCE" rev-parse --short=9 HEAD)"
test "$actual" = "$EXPECTED" || {
  echo "CHECKPOINT_MISMATCH=$actual EXPECTED=$EXPECTED"; exit 2;
}
test -z "$(git -C "$SOURCE" status --porcelain)" || {
  echo "STOP: source has uncommitted changes"; exit 2;
}
printf 'CHECKPOINT=%s\nSOURCE=%s\n' "$actual" "$SOURCE" > "$STATUS"

echo "[2/4] Select LLVM toolchain from the Evolution X workspace"
CLANG_DIR=""
PREBUILTS="$ROM/prebuilts/clang/host/linux-x86"
if [[ -d "$PREBUILTS" ]]; then
  while IFS= read -r candidate; do
    if [[ -x "$candidate" ]]; then
      CLANG_DIR="$(dirname "$candidate")"
    fi
  done < <(find "$PREBUILTS" -mindepth 3 -maxdepth 3 -name clang -print | sort -V)
fi
if [[ -n "$CLANG_DIR" ]]; then
  export PATH="$CLANG_DIR:$PATH"
else
  echo "NOTICE: no EvoX prebuilt clang found; checking system clang"
fi
for binary in clang ld.lld llvm-ar llvm-nm make; do
  if ! command -v "$binary" >/dev/null 2>&1; then
    echo "MISSING_BUILD_TOOL=$binary"
    echo "STOP: no automatic apt installation or toolchain substitutions"
    exit 3
  fi
done
echo "CLANG=$(command -v clang)"
clang --version | head -n 1
echo "LLD=$(command -v ld.lld)"
echo "PAHOLE=$(command -v pahole || echo unavailable)"
mkdir -p "$OUTPUT"

echo "[3/4] Configure official 4K GKI with KMI8 and symbol versioning"
if ! make -C "$SOURCE" O="$OUTPUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 KCFLAGS=-D__ANDROID_COMMON_KERNEL__ gki_defconfig >"$CFGLOG" 2>&1; then
  echo "CONFIGURATION_FAILED"
  tail -n 85 "$CFGLOG"
  echo "CONFIG_FAILED" >> "$STATUS"
  exit 4
fi
for setting in CONFIG_MODVERSIONS=y 'CONFIG_LOCALVERSION="-4k"' CONFIG_EXFAT_FS=y CONFIG_F2FS_FS=y; do
  if ! grep -Fqx "$setting" "$OUTPUT/.config"; then
    echo "EXPECTED_CONFIG_MISSING=$setting"
    echo "CONFIG_MISMATCH=$setting" >> "$STATUS"
    exit 4
  fi
done
grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL) = ' "$SOURCE/Makefile" | head -n 3
echo "CONFIG_OK" >> "$STATUS"

echo "[4/4] Compile Image then modules, 6 jobs; no flash or ROM repack"
for target in Image modules; do
  echo "BUILD_TARGET=$target"
  echo "==== BUILD $target at $(date -Is) ====" >> "$LOG"
  if make -C "$SOURCE" O="$OUTPUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 KCFLAGS=-D__ANDROID_COMMON_KERNEL__ -j6 "$target" 2>&1 |
      tee -a "$LOG" |
      awk '/error:|fatal error:|Error [0-9]+|undefined reference|No rule to make target|FAILED/ {
             print; fflush()
           }
           NR % 300 == 0 {
             print "BUILD_PROGRESS_LINES=" NR; fflush()
           }'; then
    echo "BUILD_OK=$target" >> "$STATUS"
  else
    rc=$?
    echo "BUILD_FAILED_TARGET=$target EXIT=$rc"
    echo "BUILD_FAILED=$target EXIT=$rc" >> "$STATUS"
    echo "==== LAST 100 BUILD LOG LINES ===="
    tail -n 100 "$LOG"
    echo "LOG=$LOG"
    echo "STATUS=$STATUS"
    exit "$rc"
  fi
done
echo "==== FINAL IMAGE ===="
IMAGE="$OUTPUT/arch/arm64/boot/Image"
test -s "$IMAGE" || { echo "IMAGE_MISSING"; exit 6; }
ls -lh "$IMAGE" "$OUTPUT/Module.symvers" 2>/dev/null || true
sha256sum "$IMAGE"
echo "CHECKPOINT_COMPILES_NO_FLASH"
echo "LOG=$LOG"
echo "STATUS=$STATUS"
echo "WARNING: incomplete 6.6.145 port; Xiaomi ABI and boot compatibility unverified"

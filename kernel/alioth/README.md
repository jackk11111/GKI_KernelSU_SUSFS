# POCO F3 (alioth) Android 17 / Linux 6.18 kernel lab

This branch contains an isolated experimental build path. It does not change the repository's existing GKI workflows or the default branch.

## Pinned inputs

- Android Common Kernel: `android17-6.18` (branch tip recorded in BuildInfo).
- Alioth mainline device support: `nasaarmas/pmaports-alioth`, commit `fef537b30e81c05cd226ca6b13ca3c888c361240`.
- Device patch: `0001-Added-POCO-F3-dts-panel-and-touchscreen-drivers.patch`, SHA-512 checked by the build.
- Mainline alioth defconfig: postmarketOS config from the same pinned pmaports commit, SHA-512 checked by the build.
- KernelSU Next: official tag `v3.4.2`.
- SUSFS: `simonpunk/susfs4ksu` branch `gki-android17-6.18`; exact commit recorded in BuildInfo.
- AnyKernel3: pinned commit `41f04bdb4ee30a44e429c2c1131d5e8bb32b15f1`.

## Why 6.18

Android 17 has an official Android Common Kernel 6.18 branch. KernelSU Next v3.4.2 publishes an arm64 Android 17 / 6.18 build. Linux 6.19.6 is available in the postmarketOS alioth port, but it is outside the v3.4.2 Android 17 / 6.18 integration target; this first Android test therefore uses 6.18.

## Important scope

This is a kernel port experiment, not a finished Android kernel. The alioth device tree, panel and FT8756 touchscreen patch comes from a mainline/postmarketOS port. It does not make the existing 4.19 vendor kernel modules ABI-compatible with 6.18. The first build is intended to establish that the Android Common 6.18 tree plus alioth mainline device support and KSU/SUSFS compile cleanly. Runtime hardware and Android HAL compatibility must be tested on the POCO F3.

The battery node in the imported mainline DTS initially retains its upstream 4520 mAh declaration. BM53 / original-battery autodetection is deliberately deferred to a later, evidence-based change.

## Build outputs

- `Alioth-Android17-6.18-KSU-Next-v3.4.2-SUSFS-2.3.0.zip` (AnyKernel3 package)
- `BuildInfo.txt` (source commits, config, hashes)
- `Image-dtb`, DTB, kernel config and built modules archive for diagnosis

The AnyKernel3 installer targets the active `boot` slot and clears the active `dtbo` slot, matching the mainline alioth port's documented boot procedure. It does not install old 4.19 modules into the 6.18 kernel.

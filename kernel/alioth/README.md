# POCO F3 (alioth) — Evolution X Android 17 userspace / Android Common 6.12 kernel lab

This is an isolated kernel-port experiment. It does not modify the repository's generic GKI workflows or the separate `alioth/android17-6.18-lab` branch.

## Exact target

- Device: POCO F3, codename `alioth`, Qualcomm SM8250.
- ROM target: Evolution X Android 17 userspace (ROM build is a later phase).
- Kernel source: Android Common release branch `android16-6.12-2026-09`, pinned to commit `5eaaf89e924b6948fd1f7fe847f774499d37a2e9`; expected kernel `6.12.92`.
- Kernel KMI family: `android16-6.12`. This is **not** an Android 17 / `android17-6.18` KMI. The selected 6.12 kernel must be validated against Android 17 userspace on the device; a successful compile does not prove that compatibility.
- Alioth device support: pinned mainline/postmarketOS DTS, panel and touchscreen patch from `nasaarmas/pmaports-alioth`, commit `fef537b30e81c05cd226ca6b13ca3c888c361240`. The postmarketOS config is not used as the Android kernel baseline.
- Root: official KernelSU Next `v3.4.2`, commit `4c706b5938665866ebe16944a481a7b91e3396af`, integrated built-in.
- Hiding: KernelSU Next's own SUSFS guard LKM, version `2.3.0-gki`, built from the same `v3.4.2` source tree against this exact kernel output. This deliberately uses the LKM architecture shipped by KernelSU Next v3.4.2, not the older Simonpunk inline-patch integration and not nonexistent `CONFIG_KSU_SUSFS` options.
- Packaging: pinned AnyKernel3 commit `41f04bdb4ee30a44e429c2c1131d5e8bb32b15f1`.

## Why Android Common 6.12

Android Common publishes Android 16 / 6.12, while Android 17's corresponding common-kernel line is 6.18. The selected 6.12 target is kept explicitly labelled as Android16-6.12 KMI; it must not be represented as an Android17 GKI kernel.

The source is Android Common 6.12, configured from that branch's `arch/arm64/configs/gki_defconfig`, then overlaid with the alioth-specific mainline driver configuration and DTS/panel/touchscreen support. This preserves Android's base facilities, including SELinux and Binder; the postmarketOS defconfig is deliberately not used as an Android baseline. The result is a custom kernel, not a certified prebuilt GKI image. The old Redline 4.19.325 kernel and the currently installed ROM are not modified by the build workflow.

## KernelSU Next and SUSFS

- `CONFIG_KSU=y`: KernelSU Next v3.4.2 is built into the kernel.
- `kernel/susfs`: the matching SUSFS 2.3.0 guard is built as an external `susfs_guard_lkm.ko` against the generated kernel build tree.
- The build checks the LKM version, ABI version and `vermagic` against the exact kernel release.
- A separate KernelSU module ZIP installs the custom LKM and loads it during `post-fs-data` using `/data/adb/ksud insmod`. Do not load a second SUSFS implementation at the same time.

No obsolete `CONFIG_KSU_SUSFS` built-in flags or Simonpunk inline SUSFS patches are used.

## Build outputs

- `Alioth-EvoX-Android17-android16-6.12-KSU-Next-v3.4.2-SUSFS-2.3.0.zip` — AnyKernel3 kernel test package.
- `Alioth-SUSFS-2.3.0-KSU-Next-3.4.2-LKM.zip` — separate KernelSU module for the custom LKM.
- `susfs_guard_lkm.ko`, `susfs_guard_lkm.modinfo.txt`, `Image`, `Image-dtb`, alioth DTB and kernel config.
- Source-built kernel modules archive.
- `BuildInfo.txt` and `SHA256SUMS` with source commits and artifact hashes.
- Official KernelSU Next v3.4.2 manager APK.

## Runtime limitations

A successful compile or ZIP assembly does not prove that the kernel boots or that Android vendor HALs work. The existing 4.19 vendor modules are not copied into this kernel: their ABI cannot be assumed compatible with 6.12. Storage, display, touch, Wi-Fi/BT, audio, camera, modem, sensors, suspend and Android userspace must be validated on the POCO F3.

The AnyKernel3 test installer writes the active `boot` slot and erases the active `dtbo` slot, following the pinned alioth mainline port's documented boot procedure. Treat this as a test package, not a routine update. No device flash or runtime success is claimed by the CI build.

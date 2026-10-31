# POCO F3 (alioth) — Evolution X Android 17 userspace / Android Common 6.12 kernel lab

This is an isolated kernel-port experiment. It does not modify the repository's generic GKI workflows or the separate `alioth/android17-6.18-lab` branch.

## Exact target

- Device: POCO F3, codename `alioth`, Qualcomm SM8250.
- Installed ROM target: Evolution X, Android 17 userspace.
- Kernel source: Android Common release branch `android16-6.12-2026-09`; expected kernel `6.12.92`.
- Kernel KMI family: `android16-6.12`. This is **not** an Android 17 / `android17-6.18` KMI. The user selected 6.12; Android 17 userspace compatibility must therefore be established on the device and is not implied by a successful build.
- Alioth support: pinned mainline/postmarketOS device patch and config from `nasaarmas/pmaports-alioth`, commit `fef537b30e81c05cd226ca6b13ca3c888c361240`.
- Root: official KernelSU Next tag `v3.4.2`, commit `4c706b5938665866ebe16944a481a7b91e3396af`.
- Hiding: SUSFS branch `gki-android16-6.12`; the exact resolved commit and describe string are recorded in `BuildInfo.txt`. The target is SUSFS 2.3.0.
- Packaging: pinned AnyKernel3 commit `41f04bdb4ee30a44e429c2c1131d5e8bb32b15f1`.

## Why this is a separate 6.12 path

Android Common publishes an Android 16 / 6.12 line, while the Android 17 Common line is 6.18. The 6.12 build deliberately retains the user's selected kernel version and labels its KMI honestly; it must not be described as an Android 17 GKI kernel.

The source is Android Common 6.12 plus alioth-specific mainline device support. It is not a generic prebuilt GKI image. The old Redline 4.19.325 kernel and the working Evolution X installation are left untouched by this workflow.

## SUSFS 6.12 compatibility

The build reuses this repository's maintained Android 16 / 6.12 SUSFS compatibility path:
- sublevel 58+: temporarily remove the conflicting `linux/dma-buf.h` include from `fs/exec.c`, then restore it at its original include position;
- sublevel 69+: temporarily rename `vma_data_pages` to `vma_pages`, then restore it;
- sublevel 92+: run `.github/scripts/susfs_fake_612.py apply` before the upstream SUSFS patch and `revert` immediately afterwards;
- add the `VMA_PAD_START` fallback only if the patched source references it without providing the definition.

These are patch-context transforms only. The final source is restored to the actual 6.12.92 layout before compilation.

## Build outputs

- `Alioth-EvoX-Android17-android16-6.12-KSU-Next-v3.4.2-SUSFS-2.3.0.zip` — AnyKernel3 test package.
- `Image`, `Image-dtb`, `sm8250-xiaomi-alioth.dtb`, `kernel.config`.
- Matching source-built modules archive.
- `BuildInfo.txt` and `SHA256SUMS` with immutable source commits and artifact hashes.
- Official KernelSU Next v3.4.2 manager APK.

## Runtime limitations and flash behavior

A successful compile or ZIP assembly does not prove that the kernel boots or that Android vendor HALs work. The existing 4.19 vendor modules are not copied into this kernel: their ABI cannot be assumed compatible with 6.12. Storage, display, touch, Wi-Fi/BT, audio, camera, modem, sensors, suspend and Android userspace must be validated on the POCO F3.

The AnyKernel3 test installer writes the active `boot` slot and erases the active `dtbo` slot, following the pinned alioth mainline port's boot procedure. Do not treat the package as a routine update. Keep a working fastboot/recovery path available before testing. No device flash or runtime success is claimed by the build workflow.

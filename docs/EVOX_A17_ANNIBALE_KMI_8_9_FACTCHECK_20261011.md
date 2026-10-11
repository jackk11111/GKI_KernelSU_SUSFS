# annibale EvoX A17 — KMI 8 vs KMI 9 source audit (2026-10-11)

## Verified source-of-truth

GitHub Actions run [38144788345](https://github.com/jackk11111/GKI_KernelSU_SUSFS/actions/runs/38144788345) retrieved `build.config.common` live from Android kernel common (Google Gitiles), and found:

| Source | KMI_GENERATION |
|:--|--:|
| Google ACK `android15-6.6` | 8 |
| Google ACK `android15-6.6-2026-01` | 8 |
| Google ACK `android15-6.6-2026-07` | 8 |
| Google ACK `android15-6.6-2026-10` | 8 |
| MiCode `annibale-w-oss` source `build.config.common` | 8 |
| LineageOS `android_kernel_qcom_sm8750` `lineage-22.2` source `build.config.common` | 8 |
| Actual EvoX A17 prebuilt Linux 6.6.118 and Xiaomi/Qualcomm `.ko` images | 8 |

In EvoX A17 the OEM `vendor_dlkm` and `vendor_boot` samples were built as `6.6.57-android15-8`, whereas `system_dlkm` sample is `6.6.118-android15-8`. Both use `modversions`.

## Lunaris screenshot

Screenshot reportedly shows `Linux 6.6.77-android15-9`, KernelSU Next Spoofed + SUSFS, on a POCO F8 Pro. **This does NOT prove actual vendor module KMI 9**, since upstream GKI 6.6 sources declare generation 8 and SUSFS can spoof `uname` kernel release. Custom KMI9 is possible but needs independently inspected binaries or sources.

## Required evidence for a genuine move to KMI9

1. Original non-root-patched `boot.img` of the official LunarisOS annibale build, or equivalent authentic kernel `Image`.
2. Matching `vendor_boot.img`, `vendor_dlkm`, `system_dlkm` partition modules, or the complete OTA to extract them. Read `modinfo -F vermagic` over a representative cross-section (Wi-Fi, GPU, camera, input, regulator, pinctrl, storage, system modules).
3. Inspect the real kernel and associated `Module.symvers` / KMI ABI symbol CRCs, not just `uname -r`. Compare with the actual modules in our EvoX.
4. If ABI differs, recompile/rebuild ALL affected device OEM modules from matching Xiaomi Qualcomm sources, then package kernel and updated module images **in lockstep**, and test on device. Do not use `--force-vermagic`, `allow_version_mismatch`, or a relabeled `android15-9` string.
5. Determine whether the claimed KMI9 is merely string spoofing. If so, retain authentic KMI8 instead of changing it to chase an apparent number.

The official LunarisOS 3.12 GMS OTA 2026093005 is hosted at SourceForge; automatic GitHub runner download returned HTTP 403 twice. No `boot.img` from that archive has yet been inspected.

## Working target pending KMI proof

Keep our already built EvoX A17 OTA and original images untouched. Our experimental Linux 6.6.144 KMI8 KernelSU Next dev-susfs / SUSFS 2.3.0 AnyKernel3 compiled successfully in run 38141706061, **not boot verified**. The Linux 6.6.158 stable upstream release is newer but cannot be treated as drop-in Android GKI until ported and KMI ABI-checked. A KMI8 build with proper KMI and updated LTS is more correct than a fake KMI9; legitimate KMI9 must include matching vendor modules.

**No flash, no repartitioning, no new OTA installation is authorized by this audit.**

## Verified binary from suggested WildKernels r21 release — direct inspection

Source release asset:
`https://github.com/WildKernels/GKI_KernelSU_SUSFS/releases/download/r21/6.6.77-android15-2025-03-KernelSU-Next-AnyKernel3.zip`

The asset SHA256 from the upstream GitHub release, independently checked by GitHub Actions:
`fd02b62bd3c4860a73366db37dc17ae16e589a01084dcd2f719d59583b3c5758`.

Read-only inspection run [38145903704](https://github.com/jackk11111/GKI_KernelSU_SUSFS/actions/runs/38145903704) inspected actual `Image` binary, not its filename, and printed:

```text
Linux version 6.6.77-android15-Wild (kleaf@build-host) ... 
6.6.77-android15-Wild SMP preempt mod_unload modversions aarch64
```

The ZIP's `anykernel.sh` has `do.devicecheck=0`, empty `device.name1..5`, `block=boot`, and `is_slot_device=auto`. It is GENERIC, NOT specifically validated for annibale. The embedded kernel identity **does not match** the screenshot's `6.6.77-android15-9-g47903367` string. It might nevertheless be the underlying base with custom kernel release spoofing; exact binary identity of Lunaris is still UNKNOWN without its actual boot image or full unspoofed kernel evidence. Do **not** mistake this archive for a verified KMI9 kernel or flash it as such.

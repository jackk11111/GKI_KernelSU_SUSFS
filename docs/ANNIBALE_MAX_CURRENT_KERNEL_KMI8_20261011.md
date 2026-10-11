# EvoX A17 annibale — maximum CURRENT Linux 6.6 / KMI8 candidate

Updated: 2026-10-11. KMI9 investigation deferred at the device owner's request.

## Target versions

- **Kernel**: Linux 6.6.158 LTS, the latest published 6.6.y stable tag on 2026-10-11; based on Google Android common kernel `android15-6.6-lts`, not upstream Linux alone.
- **KMI**: authentic `android15-8` (Google Android 15 6.6 branch `KMI_GENERATION=8`). The GKI KMI generation must not be changed just to improve its apparent number.
- **Page size**: 4 KiB, aarch64, compatible with existing EvoX device modules where possible.
- **Root**: KernelSU Next dev-susfs fork `pershoot/KernelSU-Next` commit `956ea0f526fd4e216f8d67844cb61b34a4c49bfe`, currently 12 commits ahead and none behind official v3.4.1.
- **Manager**: the independent official Spoofed APK `KernelSU_Next_v3.4.1-spoofed_33333-release.apk`, from `KernelSU-Next/KernelSU-Next` release v3.4.1.
- **SUSFS**: v2.3.0 or later if supported by audited official `gki-android15-6.6` branch, without upstream patch conflict markers; validated existing working commit `a0f9c59e2243f8a5db955f4ad1686d5e0ad26e1a`.
- **Output**: recovery-flashable (OrangeFox) AnyKernel3 with explicit `annibale` device guard, correct boot slot handling, release metadata, and backup/rollback procedure. No ZIP is flash-approved until all ABI/device gates pass.

## Source and evidence

- Previous working GitHub build: https://github.com/jackk11111/GKI_KernelSU_SUSFS/actions/runs/38141706061 ; output compiled Linux 6.6.144 KMI8 with KernelSU Next + SUSFS 2.3.0. Boot NOT verified.
- Target official stable Linux release announcement: https://lists.openwall.net/linux-kernel/2026/10/03/581 .
- Linux stable tags (gregkh/linux): `v6.6.144` and `v6.6.158`.
- GitHub upstream port feasibility run: https://github.com/jackk11111/GKI_KernelSU_SUSFS/actions/runs/38148805470 .
- Official Android GKI rules: https://source.android.com/docs/core/architecture/kernel/android-common .

## Mandatory engineering gates

1. Start with real Android `android15-6.6` ACK code; do not replace the entire kernel with vanilla upstream Linux 6.6.158.
2. Test upstream stable 6.6.144 -> 6.6.158 patch applicability. Review merge conflicts and preserve Android/Qualcomm patches; no blind `git apply --reject` or renaming a 6.6.144 kernel to 6.6.158.
3. Verify actual built `Image` Linux version, `KMI_GENERATION=8`, SUSFS and root commits. Full compile and checks must succeed.
4. Compare actual exported symbol versions / ABI and OEM modules from the EvoX images. Neither `allow_version_mismatch` nor disabled `CONFIG_MODVERSIONS` makes a mismatched kernel safe.
5. Restrict AnyKernel3 target to `annibale` and confirm image formats and slot-specific boot partition handling. Ensure tested recovery backup and rollback.
6. Only then seek explicit user authorization for first flash test. ROM `EvolutionX-17.0-20261011-annibale-12.3-Unofficial.zip` and its original boot image remain unchanged.

## Scope note

'Newest kernel' in this project means **newest real patchlevel supportable in the existing Linux 6.6 / Android 15 KMI8 device driver family**. Newer Linux major versions (6.12, 6.18, 7.x) are not automatically bootable drop-ins for existing Xiaomi proprietary vendor modules. Nothing here claims that source patching, compilation or boot has succeeded before evidenced by reports.

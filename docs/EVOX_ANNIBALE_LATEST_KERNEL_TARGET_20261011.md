# POCO F8 Pro (annibale) — Evolution X A17 kernel research, 2026-10-11

## Unaltered baseline
- EvoX A17 12.3 Unofficial Android 17 OTA already built and backed up.
- Its boot.bin's kernel is 6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k.
- Existing vendor_dlkm and vendor_boot sample modinfo show
  `6.6.57-android15-8-gf70357c3da13-4k`;
  system_dlkm sample `6.6.118-android15-8-...`.
- Do NOT replace the ROM or flash experimental kernels prior to audited boot compatibility.

## Completed GKI experiment
- Run https://github.com/jackk11111/GKI_KernelSU_SUSFS/actions/runs/38141706061 green.
- Built 6.6.144-android15-8 with KernelSU Next (pershoot dev-susfs
  956ea0f526fd4e216f8d67844cb61b34a4c49bfe, descendant of upstream 3.4.1)
  and SUSFS v2.3.0 (simonpunk commit a0f9c59e2243f8a5db955f4ad1686d5e0ad26e1a).
- AnyKernel3 built but not demonstrated safe or bootable on annibale. DO NOT FLASH.
- The 6.6.144 kernel is not newest 6.6 LTS as of 2026-10-11.

## Higher version investigation
- Latest official Linux 6.6.y longterm known 2026-10-11: **6.6.158** (released 2026-10-03).
  https://www.kernel.org/
- Google android15-6.6-2026-10 branch has documented 6.6.143; merging upstream 6.6.158
  into Android GKI + SUSFS needs code integration and ABI checks, cannot be done by
  changing kernel release string.
- A LunarisOS Official POCO F8 Pro screenshot shows 6.6.77-android15-9
  with KernelSU Next Spoofed 3.4.0 and SUSFS 2.3.0; we do NOT yet know if this is
  the ROM's ORIGINAL kernel or an aftermarket flashed kernel.
- KMI 9 is not inherently better than KMI 8; it is a DIFFERENT module ABI generation.
  Changing branding is not the same as implementing an ABI. Vendor module CRC/symbol
  compatibility requires comparison.
- Other Linux families 6.12/6.18 are not a drop-in replacement for 6.6 on annibale.

## Lunaris official source of truth
- OTA metadata:
  https://github.com/Lunaris-AOSP/OTA/blob/16.2/builds/annibale.json
- Official GMS 2026093005 ZIP:
  https://sourceforge.net/projects/ghosuto/files/annibale/Lunaris-AOSP-annibale-OFFICIAL-3.12-GMS-2026093005.zip/download
- SHA256 `4e7f5530ec22b0f461d045f269df58d810cbec333481d80efc3619852b94789c`.
- A read-only workflow in this branch is attempting to download the 5.17GB official
  OTA and extract only boot.img automatically. Check latest run under Actions.
- No standalone matching boot.img was found published; a 2026-09-03 recovery.img
  is listed but NOT equivalent to the 2026-09-30 boot.img.

## Gate before another kernel build
1. Validate Lunaris official boot and kernel version vs screenshot.
2. Determine real KMI for original kernel and its vendor modules; if screenshot shows
   aftermarket kernel, ask origin/patched boot file and matching modules.
3. Choose most recent verifiably compatible android15-6.6 base (6.6.158 upstream
   may require nontrivial GKI adaptation), preserving symbol ABI and module compatibility.
4. Integrate latest compatible KernelSU Next Spoofed manager (official latest stable
   as of 2026-10-11 = v3.4.1) + matching SUSFS branch, compile.
5. Produce and inspect AnyKernel3 ZIP but do not flash until first EvoX baseline boot
   and image/ABI/partition-target checks. Never bypass kernel module version validation.

#!/usr/bin/env bash
set -Eeuo pipefail

KERNEL_DIR="${1:?kernel source directory required}"
WORK="${2:?work directory required}"
PATCH_URL="https://raw.githubusercontent.com/armada-os/armada/b7b322a53c285739dfd00831182ada53b9bc1fa1/packages/kernel/patches/0011-qcom-pm8150b-charger.patch"
PATCH_FILE="$WORK/0011-qcom-pm8150b-charger.patch"

mkdir -p "$WORK"

echo "== Fetch and apply PM8150B charger/fuel-gauge drivers =="
EXPECTED_PATCH_BLOB="671fdee7df686e5636778ea5af6a979ab876373a"
curl -fL --retry 4 --retry-delay 3 "$PATCH_URL" -o "$PATCH_FILE"
ACTUAL_PATCH_BLOB="$(git -C "$KERNEL_DIR" hash-object "$PATCH_FILE")"
if [ "$ACTUAL_PATCH_BLOB" != "$EXPECTED_PATCH_BLOB" ]; then
  echo "ERROR: PM8150B patch blob changed: expected $EXPECTED_PATCH_BLOB, got $ACTUAL_PATCH_BLOB" >&2
  exit 1
fi
grep -q 'drivers/power/supply/qcom_fg.c' "$PATCH_FILE"
grep -q 'drivers/power/supply/qcom_pm8150b_charger.c' "$PATCH_FILE"

# The patch's Makefile hunk targets a different Android kernel tree layout.
# Keep its Kconfig and driver-source hunks; register the two objects below
# using idempotent exact-line checks against this pinned 6.12 source.
FILTERED_PATCH="$WORK/0011-qcom-pm8150b-charger-no-makefile.patch"
python3 - "$PATCH_FILE" "$FILTERED_PATCH" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text().splitlines(keepends=True)
target = pathlib.Path(sys.argv[2])
filtered = []
skip = False
removed = 0

for line in source:
    if line.startswith("diff -rupbN "):
        parts = line.split()
        old_path = parts[2] if len(parts) > 2 else ""
        skip = old_path.endswith("/drivers/power/supply/Makefile")
        if skip:
            removed += 1
            continue
    if not skip:
        filtered.append(line)

if removed != 1:
    raise SystemExit(f"Expected to exclude one power-supply Makefile hunk, found {removed}")
if not any("drivers/power/supply/qcom_fg.c" in line for line in filtered):
    raise SystemExit("Filtered patch lost qcom_fg.c")
if not any("drivers/power/supply/qcom_pm8150b_charger.c" in line for line in filtered):
    raise SystemExit("Filtered patch lost qcom_pm8150b_charger.c")

target.write_text("".join(filtered))
print("PATCH_MAKEFILE_HUNK_EXCLUDED=PASS")
PY

patch --dry-run -p1 --forward -f -d "$KERNEL_DIR" < "$FILTERED_PATCH"
patch -p1 --forward -f -d "$KERNEL_DIR" < "$FILTERED_PATCH"

python3 - "$KERNEL_DIR" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
makefile = root / "drivers/power/supply/Makefile"
lines = makefile.read_text().splitlines(keepends=True)
entries = (
    "obj-$(CONFIG_CHARGER_QCOM_SMB5) += qcom_pm8150b_charger.o",
    "obj-$(CONFIG_BATTERY_QCOM_FG) += qcom_fg.o",
)

for entry in entries:
    count = sum(line.rstrip("\r\n") == entry for line in lines)
    if count > 1:
        raise SystemExit(f"Duplicate power-supply registration: {entry}")
    if count == 0:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        lines.append(entry + "\n")
    print(f"POWER_SUPPLY_REGISTRATION=PASS {entry}")

makefile.write_text("".join(lines))
kconfig = (root / "drivers/power/supply/Kconfig").read_text()
for symbol in ("CHARGER_QCOM_SMB5", "BATTERY_QCOM_FG"):
    if kconfig.count(f"config {symbol}") != 1:
        raise SystemExit(f"Expected exactly one Kconfig symbol: {symbol}")

for source in ("qcom_fg.c", "qcom_pm8150b_charger.c"):
    if not (root / "drivers/power/supply" / source).is_file():
        raise SystemExit(f"Missing PM8150B driver source: {source}")

print("PM8150B_KCONFIG_AND_SOURCES=PASS")
PY

echo "PM8150B_DRIVERS=PASS"

echo "== Add the PM8150B charger and fuel-gauge DT nodes missing from Android Common 6.12 =="
python3 - "$KERNEL_DIR" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
pmic = root / "arch/arm64/boot/dts/qcom/pm8150b.dtsi"
text = pmic.read_text()

nodes = """\t\tpm8150b_charger: charger@1000 {
\t\t\tcompatible = "qcom,pm8150b-charger";
\t\t\treg = <0x1000>;

\t\t\tinterrupts = <0x2 0x13 0x4 IRQ_TYPE_EDGE_BOTH>,
\t\t\t\t     <0x2 0x12 0x2 IRQ_TYPE_EDGE_BOTH>,
\t\t\t\t     <0x2 0x16 0x1 IRQ_TYPE_EDGE_RISING>,
\t\t\t\t     <0x2 0x13 0x7 IRQ_TYPE_EDGE_RISING>;
\t\t\tinterrupt-names = "usbin-plugin",
\t\t\t\t\t  "bat-ov",
\t\t\t\t\t  "wdog-bark",
\t\t\t\t\t  "usbin-icl-change";

\t\t\tio-channels = <&pm8150b_adc 7>,
\t\t\t\t      <&pm8150b_adc 8>;
\t\t\tio-channel-names = "usb_in_i_uv", "usb_in_v_div_16";

\t\t\tstatus = "disabled";
\t\t};

\t\tpm8150b_fg: fuel-gauge@4000 {
\t\t\tcompatible = "qcom,pm8150b-fg";
\t\t\treg = <0x4000>;
\t\t\tinterrupts = <0x2 0x40 0x3 IRQ_TYPE_EDGE_RISING>;
\t\t\tinterrupt-names = "soc-delta";
\t\t\tstatus = "disabled";
\t\t};

"""
if "pm8150b_charger:" not in text and "pm8150b_fg:" not in text:
    marker = "\n\t\tpm8150b_adc: adc@3100 {"
    if text.count(marker) != 1:
        raise SystemExit(f"Expected one PM8150B ADC node anchor, found {text.count(marker)}")
    text = text.replace(marker, "\n" + nodes + "\t\tpm8150b_adc: adc@3100 {", 1)
elif text.count("pm8150b_charger:") != 1 or text.count("pm8150b_fg:") != 1:
    raise SystemExit("Partial or duplicate PM8150B charger/fuel-gauge nodes detected")

channels = """\t\t\tchannel@7 {
\t\t\t\treg = <ADC5_USB_IN_I>;
\t\t\t\tqcom,pre-scaling = <1 1>;
\t\t\t\tlabel = "usb_in_i_uv";
\t\t\t};

\t\t\tchannel@8 {
\t\t\t\treg = <ADC5_USB_IN_V_16>;
\t\t\t\tqcom,pre-scaling = <1 16>;
\t\t\t\tlabel = "usb_in_v_div_16";
\t\t\t};

"""
if "channel@7 {" not in text and "channel@8 {" not in text:
    marker = "\n\t\t\tchannel@9 {"
    if text.count(marker) != 1:
        raise SystemExit(f"Expected one PM8150B ADC channel@9 anchor, found {text.count(marker)}")
    text = text.replace(marker, "\n" + channels + "\t\t\tchannel@9 {", 1)
elif text.count("channel@7 {") != 1 or text.count("channel@8 {") != 1:
    raise SystemExit("Partial or duplicate PM8150B ADC channels detected")

if text.count("pm8150b_charger:") != 1 or text.count("pm8150b_fg:") != 1:
    raise SystemExit("PM8150B node registration validation failed")
if text.count("channel@7 {") != 1 or text.count("channel@8 {") != 1:
    raise SystemExit("PM8150B ADC channel validation failed")

pmic.write_text(text)
print("PM8150B_DTS_NODES=PASS")
print("PM8150B_ADC_CHANNELS=PASS")
PY

echo "== Adapt panel DSC packetization to the Android Common 6.12 MSM DSI host =="
python3 - "$KERNEL_DIR" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
panel = root / "drivers/gpu/drm/panel/panel-samsung-ams667xx01.c"
host = root / "drivers/gpu/drm/msm/dsi/dsi_host.c"
source = panel.read_text()
host_source = host.read_text()

old = "\tdsi->dsc_slice_per_pkt = 2;\n"
new = "\t/* Android Common 6.12 MSM DSI host supports one DSC slice per packet. */\n"

if "only supports slice_per_pkt = 1" not in host_source:
    raise SystemExit("MSM DSI host capability anchor changed; refusing speculative DSC edit")
if source.count(old) == 1:
    source = source.replace(old, new, 1)
elif old not in source and source.count(new) == 1:
    pass
else:
    raise SystemExit("Unexpected dsc_slice_per_pkt assignment count in Alioth panel driver")

if "slice_width = 540" not in source or "slice_count = 2" not in source:
    raise SystemExit("Alioth panel DSC geometry changed; refusing to alter packetization blindly")
if "dsc_slice_per_pkt" in source:
    raise SystemExit("Unsupported dsc_slice_per_pkt field remains in panel source")

panel.write_text(source)
print("PANEL_DSC_HOST_COMPAT=PASS (2 slices per line, 1 slice per packet)")
PY

echo "== Remove duplicate label from the Alioth SD870 OPP extension =="
python3 - "$KERNEL_DIR" <<'PY'
import pathlib
import sys

dts = pathlib.Path(sys.argv[1]) / "arch/arm64/boot/dts/qcom/sm8250-xiaomi-alioth.dts"
source = dts.read_text()
old = "\tcpu7_opp21: opp-3187200000 {"
new = "\topp-3187200000 {"

if source.count(old) == 1:
    source = source.replace(old, new, 1)
elif source.count(new) == 1:
    pass
else:
    raise SystemExit(
        "Expected exactly one Alioth 3.1872 GHz OPP label to remove; "
        f"label_count={source.count(old)}, node_count={source.count(new)}"
    )

if source.count("opp-3187200000 {") != 1:
    raise SystemExit("Alioth 3.1872 GHz OPP node is missing or duplicated")
if "cpu7_opp21: opp-3187200000" in source:
    raise SystemExit("Duplicate cpu7_opp21 label remains on the 3.1872 GHz OPP")

dts.write_text(source)
print("ALIOTH_SD870_OPP_LABEL=PASS (unreferenced duplicate label removed)")
PY

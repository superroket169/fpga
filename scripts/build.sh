#!/usr/bin/env bash
# Tang Nano 20K (GW2AR-18C) build + FLASH script
# Always operates on the repo root regardless of where it's invoked from.

set -euo pipefail
cd "$(dirname "$0")/.."

OSS_CAD_ENV="/home/isa/oss-cad-suite/environment"
if ! command -v nextpnr-himbaechel &>/dev/null; then
    if [[ -f "$OSS_CAD_ENV" ]]; then
        echo "== oss-cad-suite source ing =="
        source "$OSS_CAD_ENV"
    else
        echo "HATA: nextpnr-himbaechel bulunamadi ve ${OSS_CAD_ENV} yok." >&2
        exit 1
    fi
fi

VERILOG_FILE="${1:-src/main.v}"
TOP_MODULE="${2:-top}"
CST_FILE="${3:-src/tangnano20k.cst}"

DEVICE="GW2AR-LV18QN88C8/I7"
FAMILY_SYNTH="gw2a"
FAMILY_PNR="GW2A-18C"
FREQ="27"

BUILD_DIR="build"
JSON_OUT="${BUILD_DIR}/${TOP_MODULE}.json"
PNR_OUT="${BUILD_DIR}/${TOP_MODULE}_pnr.json"
FS_OUT="${BUILD_DIR}/${TOP_MODULE}.fs"

if [[ ! -f "$VERILOG_FILE" ]]; then
    echo "HATA: '$VERILOG_FILE' bulunamadi." >&2
    exit 1
fi

if [[ ! -f "$CST_FILE" ]]; then
    echo "HATA: '$CST_FILE' bulunamadi. Pin constraint dosyasi olmadan devam edilemez." >&2
    exit 1
fi

mkdir -p "$BUILD_DIR"

echo "== [1/4] Yosys synth (family=${FAMILY_SYNTH}, top=${TOP_MODULE}) =="
yosys -p "read_verilog ${VERILOG_FILE}; synth_gowin -top ${TOP_MODULE} -family ${FAMILY_SYNTH} -json ${JSON_OUT}"

echo "== [2/4] nextpnr-himbaechel place & route (device=${DEVICE}, family=${FAMILY_PNR}) =="
nextpnr-himbaechel \
    --json "$JSON_OUT" \
    --write "$PNR_OUT" \
    --freq "$FREQ" \
    --device "$DEVICE" \
    --vopt family="$FAMILY_PNR" \
    --vopt cst="$CST_FILE"

echo "== [3/4] gowin_pack (bitstream uretimi) =="
gowin_pack -d "$FAMILY_PNR" -o "$FS_OUT" "$PNR_OUT"

echo "== [4/4] openFPGALoader - HARICI FLASH'A KALICI YAZMA =="
openFPGALoader -b tangnano20k -f "$FS_OUT"

echo ""
echo "Basarili: ${FS_OUT} flash'a kalici olarak yazildi."
echo "Kart artik USB'den bagimsiz calisir, MCU gibi power-on'da otomatik baslar."

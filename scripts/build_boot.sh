#!/usr/bin/env bash
#
# build_boot.sh - Fast standalone boot.img, vendor_boot.img, and dtbo.img packager
# Targets Xiaomi zorn (Poco F7 Pro / Redmi K80, SM8650 "pineapple")
#

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS_DIR="${1:-$PROJECT_DIR/artifacts}"
TMP_DIR=$(mktemp -d /tmp/zorn_boot_pack.XXXXXX)
KERNEL_REPO="https://github.com/Little-Zorn-ID/device_xiaomi_zorn-kernel.git"
KERNEL_BRANCH="lineage-23.0"
KERNEL_DIR="$TMP_DIR/kernel_source"

function cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "=== Packaging Fastboot Boot & Recovery Artifacts for Xiaomi zorn ==="
mkdir -p "$ARTIFACTS_DIR"

# Ensure mkbootimg is available
if ! command -v mkbootimg &>/dev/null; then
    echo "mkbootimg not found in PATH, cloning mkbootimg repo from Android Open Source..."
    git clone --depth=1 https://android.googlesource.com/platform/system/tools/mkbootimg.git "$TMP_DIR/mkbootimg_repo"
    cat << EOF > "$TMP_DIR/mkbootimg"
#!/usr/bin/env bash
python3 "$TMP_DIR/mkbootimg_repo/mkbootimg.py" "\$@"
EOF
    chmod +x "$TMP_DIR/mkbootimg"
    export PATH="$TMP_DIR:$PATH"
fi

# Ensure avbtool is available
if ! command -v avbtool &>/dev/null; then
    echo "avbtool not found in PATH, downloading standalone avbtool..."
    curl -sSL "https://android.googlesource.com/platform/external/avb/+/refs/heads/main/avbtool.py?format=TEXT" | base64 -d > "$TMP_DIR/avbtool"
    chmod +x "$TMP_DIR/avbtool"
    export PATH="$TMP_DIR:$PATH"
fi

# 1. Fetch prebuilt kernel repository
echo "[1/6] Fetching prebuilt GKI 6.1 kernel, dtb, dtbo, and vendor ramdisk..."
git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_DIR"

# 2. Prepare DTB image
echo "[2/6] Concatenating SoC DTBs..."
cat "$KERNEL_DIR/dtb/"*.dtb > "$TMP_DIR/dtb.img"

# 3. Build boot.img (GKI v4 header - kernel only)
echo "[3/6] Packaging boot.img (Header v4)..."
mkbootimg \
    --header_version 4 \
    --kernel "$KERNEL_DIR/kernel" \
    --pagesize 4096 \
    --os_version 15.0.0 \
    --os_patch_level 2025-03 \
    -o "$ARTIFACTS_DIR/boot.img"

# 4. Prepare vendor_bootconfig & vendor_ramdisk
echo "[4/6] Creating vendor_bootconfig and compressing vendor_ramdisk with lz4..."
cat << 'EOF' > "$TMP_DIR/bootconfig"
androidboot.hardware=qcom
androidboot.hypervisor.protected_vm.supported=0
androidboot.load_modules_parallel=true
androidboot.memcg=1
androidboot.usbcontroller=a600000.dwc3
androidboot.vendor.qspa=true
androidboot.console=0
EOF

(cd "$KERNEL_DIR/vendor_ramdisk" && find . | cpio -H newc -o 2>/dev/null) | lz4 -l -12 --favor-decSpeed > "$TMP_DIR/vendor_ramdisk.lz4"

# 5. Build vendor_boot.img
echo "[5/6] Packaging vendor_boot.img (Header v4)..."
mkbootimg \
    --header_version 4 \
    --pagesize 4096 \
    --vendor_boot "$ARTIFACTS_DIR/vendor_boot.img" \
    --vendor_ramdisk "$TMP_DIR/vendor_ramdisk.lz4" \
    --dtb "$TMP_DIR/dtb.img" \
    --vendor_cmdline "video=vfb:640x400,bpp=32,memsize=3072000 disable_dma32=on swinfo.fingerprint=lineage_zorn mtdoops.fingerprint=lineage_zorn" \
    --vendor_bootconfig "$TMP_DIR/bootconfig"

# Copy prebuilt dtbo.img
cp "$KERNEL_DIR/dtbo.img" "$ARTIFACTS_DIR/dtbo.img"

# 6. Sign partitions with AVB
echo "[6/6] Signing partitions with AVB test key..."
AVB_KEY="$TMP_DIR/testkey_rsa4096.pem"
openssl genrsa -out "$AVB_KEY" 4096 2>/dev/null

if command -v avbtool &>/dev/null; then
    avbtool add_hash_footer \
        --image "$ARTIFACTS_DIR/boot.img" \
        --partition_size 100663296 \
        --partition_name boot \
        --algorithm SHA256_RSA4096 \
        --key "$AVB_KEY" || true

    avbtool add_hash_footer \
        --image "$ARTIFACTS_DIR/vendor_boot.img" \
        --partition_size 100663296 \
        --partition_name vendor_boot \
        --algorithm SHA256_RSA4096 \
        --key "$AVB_KEY" || true

    avbtool add_hash_footer \
        --image "$ARTIFACTS_DIR/dtbo.img" \
        --partition_size 25165824 \
        --partition_name dtbo \
        --algorithm SHA256_RSA4096 \
        --key "$AVB_KEY" || true
fi

echo "=== Successfully built fastboot bootable artifacts! ==="
ls -lh "$ARTIFACTS_DIR"/boot.img "$ARTIFACTS_DIR"/vendor_boot.img "$ARTIFACTS_DIR"/dtbo.img

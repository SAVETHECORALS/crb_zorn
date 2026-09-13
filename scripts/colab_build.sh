#!/usr/bin/env bash
#
# colab_build.sh - Automated LineageOS 24.0 Build Script for Google Colab
# Targets Xiaomi zorn (Poco F7 Pro / Redmi K80, SM8650)
# Designed for Colab's High-RAM (47GB RAM) and 225GB SSD environments.
#

set -e

TARGET="${1:-recoveryimage}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="/content/android/lineage"
ARTIFACTS_DIR="/content/artifacts"
DRIVE_DIR="/content/drive/MyDrive/zorn_artifacts"

echo "============================================================"
echo " Starting LineageOS 24.0 Build on Google Colab for: $TARGET"
echo "============================================================"
echo "Specs check:"
echo "RAM:  $(free -h | awk '/^Mem:/ {print $2}')"
echo "Disk: $(df -h /content | awk 'NR==2 {print $4}') available"
echo "CPU:  $(nproc) cores"
echo "============================================================"

# 1. Install Android Build Dependencies
echo "[1/6] Installing build dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
  bc bison build-essential ccache curl flex g++-multilib gcc-multilib \
  git gnupg gperf imagemagick libelf-dev liblz4-tool libncurses-dev \
  libssl-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool \
  squashfs-tools xsltproc zip zlib1g-dev python3 python-is-python3 jq

git config --global user.name "SAVETHECORALS"
git config --global user.email "1pro00013@gmail.com"

# Install Google repo tool
mkdir -p ~/bin
curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
export PATH=~/bin:$PATH

# Fast standalone bootimage build if target is bootimage
if [ "$TARGET" = "bootimage" ]; then
    echo "Building standalone boot & kernel artifacts..."
    mkdir -p "$ARTIFACTS_DIR"
    "$PROJECT_DIR/scripts/build_boot.sh" "$ARTIFACTS_DIR"
    if [ -d "/content/drive/MyDrive" ]; then
        mkdir -p "$DRIVE_DIR"
        cp -r "$ARTIFACTS_DIR"/* "$DRIVE_DIR/" || true
        echo "Backed up artifacts to Google Drive: $DRIVE_DIR"
    fi
    echo "Done!"
    exit 0
fi

# 2. Initialize LineageOS 24.0 Shallow Tree
echo "[2/6] Initializing LineageOS 24.0 source tree..."
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

repo init -u https://github.com/LineageOS/android.git \
  -b lineage-24.0 \
  --git-lfs \
  --depth=1 \
  --partial-clone \
  --clone-filter=blob:none \
  -g default,-darwin,-mips,-notdefault,-cts,-vts,-tests

# 3. Inject Xiaomi Zorn Local Manifest
echo "[3/6] Injecting Xiaomi zorn local manifest..."
mkdir -p .repo/local_manifests
cp "$PROJECT_DIR/manifests/zorn_a17.xml" .repo/local_manifests/

# 4. Sync Source Tree
echo "[4/6] Syncing source code with $(nproc) parallel jobs..."
repo sync -c -j$(nproc) --no-clone-bundle --no-tags --force-sync --retry-fetches=3

# Free .repo metadata to maximize build disk space
echo "Pruning .repo git cache to save disk space..."
rm -rf .repo

# 5. Overlay Local Device Tree Modifications
echo "[5/6] Overlaying local device modifications..."
if [ -d "$PROJECT_DIR/device/xiaomi/zorn" ]; then
    rsync -av --exclude='.git' "$PROJECT_DIR/device/xiaomi/zorn/" device/xiaomi/zorn/
fi

# 6. Sourcing & Compiling
echo "[6/6] Sourcing environment and compiling target: $TARGET..."
export CCACHE_DIR=/content/ccache
export USE_CCACHE=1
export WITHOUT_CHECK_API=true
mkdir -p /content/ccache
ccache -M 25G

source build/envsetup.sh
breakfast zorn || lunch lineage_zorn-ap4a-userdebug || lunch lineage_zorn-trunk_staging-userdebug || lunch lineage_zorn-userdebug

mkdir -p "$ARTIFACTS_DIR"

if [ "$TARGET" = "sepolicy" ]; then
    m sepolicy
    touch "$ARTIFACTS_DIR/sepolicy_build_success.txt"
elif [ "$TARGET" = "recoveryimage" ]; then
    m recoveryimage
    cp out/target/product/zorn/recovery.img "$ARTIFACTS_DIR/" || true
    cp out/target/product/zorn/boot.img "$ARTIFACTS_DIR/" || true
    cp out/target/product/zorn/vendor_boot.img "$ARTIFACTS_DIR/" || true
    cp out/target/product/zorn/dtbo.img "$ARTIFACTS_DIR/" || true
elif [ "$TARGET" = "rom" ]; then
    m bacon
    cp out/target/product/zorn/lineage-*.zip "$ARTIFACTS_DIR/" || true
    cp out/target/product/zorn/recovery.img "$ARTIFACTS_DIR/" || true
    cp out/target/product/zorn/boot.img "$ARTIFACTS_DIR/" || true
    cp out/target/product/zorn/vendor_boot.img "$ARTIFACTS_DIR/" || true
    cp out/target/product/zorn/dtbo.img "$ARTIFACTS_DIR/" || true
    cp out/target/product/zorn/super_empty.img "$ARTIFACTS_DIR/" || true
fi

echo "=== Build Finished! Generated artifacts: ==="
ls -lh "$ARTIFACTS_DIR/"

# Backup to Google Drive if connected
if [ -d "/content/drive/MyDrive" ]; then
    echo "Copying artifacts to your Google Drive..."
    mkdir -p "$DRIVE_DIR"
    cp -r "$ARTIFACTS_DIR"/* "$DRIVE_DIR/" || true
    echo "Saved to Google Drive: $DRIVE_DIR"
fi

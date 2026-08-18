#!/bin/bash

set -o pipefail

SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')

CURRENT_DIR=$(pwd)

# ============================================================
# Device
# ============================================================

DEVICE="everpal"
DEFCONFIG="${DEVICE}_defconfig"

# ============================================================
# Toolchain
# ============================================================

TC_DIR="$HOME/toolchains/ZyC-clang-22.0.0"

# ============================================================
# Output
# ============================================================

ZIPNAME="AquaKernel-${DATE}.zip"

# ============================================================
# Build options
# ============================================================

BUILD_JOBS="${BUILD_JOBS:-2}"

CLEAN_BUILD=false
INCLUDE_KSU=false

for arg in "$@"; do
    case "$arg" in
        --clean)
            CLEAN_BUILD=true
            ;;
        --with-ksu)
            INCLUDE_KSU=true
            ;;
        --redo-ksu)
            rm -f out/.ksu_applied
            INCLUDE_KSU=true
            ;;
    esac
done

# ============================================================
# Information
# ============================================================

echo
echo "========================================"
echo "Aqua / evergey Kernel Build"
echo "========================================"

echo "Device       : $DEVICE"
echo "Defconfig    : $DEFCONFIG"
echo "Build jobs   : $BUILD_JOBS"
echo "KernelSU     : $INCLUDE_KSU"
echo "Output       : out"
echo "ZIP          : $ZIPNAME"

echo "========================================"

# ============================================================
# Clean generated files
# ============================================================

echo
echo "Cleaning generated files..."

rm -rf out/arch/arm64/boot

rm -rf .config
rm -rf .config.old
rm -rf .tmp_versions

rm -rf include/generated
rm -rf include/config
rm -rf arch/arm64/include/generated

rm -rf vmlinux*
rm -f System.map
rm -f modules.builtin*
rm -f Module.symvers
rm -f modules.order

rm -rf scripts/kconfig/.tmp*

if [ "$CLEAN_BUILD" = true ]; then
    echo "Performing complete clean build..."
    rm -rf out
fi

mkdir -p out

# ============================================================
# Check defconfig
# ============================================================

if [ ! -f "arch/arm64/configs/$DEFCONFIG" ]; then
    echo
    echo "ERROR:"
    echo "arch/arm64/configs/$DEFCONFIG not found!"
    exit 1
fi

# ============================================================
# Toolchain
# ============================================================

if [ ! -d "$TC_DIR" ]; then

    echo
    echo "========================================"
    echo "Downloading ZyCromerZ Clang 22"
    echo "========================================"

    mkdir -p "$TC_DIR"

    cd "$TC_DIR" || exit 1

    wget -q --show-progress \
        https://github.com/ZyCromerZ/Clang/releases/download/22.0.0git-20250928-release/Clang-22.0.0git-20250928.tar.gz

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to download Clang."
        exit 1
    fi

    tar -xf Clang-22.0.0git-20250928.tar.gz

    rm -f Clang-22.0.0git-20250928.tar.gz

    cd "$CURRENT_DIR" || exit 1
fi

export PATH="$TC_DIR/bin:$PATH"

export CC=clang
export LD=ld.lld

echo
echo "========================================"
echo "Compiler"
echo "========================================"

echo "clang:"
command -v clang
clang --version

echo
echo "ld.lld:"
command -v ld.lld
ld.lld --version

# ============================================================
# KernelSU Next + SUSFS
# ============================================================

if [ -f out/.ksu_applied ]; then
    echo
    echo "KernelSU Next already applied."
fi

if [[ "$INCLUDE_KSU" = true && ! -f out/.ksu_applied ]]; then

    echo
    echo "========================================"
    echo "Applying KernelSU Next + SUSFS"
    echo "========================================"

    curl -LSs \
        "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" \
        | bash

    if [ $? -ne 0 ]; then
        echo "ERROR: KernelSU setup failed!"
        exit 1
    fi

    git clone \
        --depth=1 \
        https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd.git \
        SU_patch

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to clone SU_patch."
        exit 1
    fi

    for patch in SU_patch/Patches/*sh; do
        if [ -f "$patch" ]; then
            echo "Applying: $patch"
            bash "$patch"

            if [ $? -ne 0 ]; then
                echo "ERROR: Patch failed: $patch"
                exit 1
            fi
        fi
    done

    if [ -f SU_patch/Patches/Patch/susfs_patch_to_4.14.patch ]; then

        patch -p1 \
            < SU_patch/Patches/Patch/susfs_patch_to_4.14.patch

        if [ $? -ne 0 ]; then
            echo "ERROR: SUSFS 4.14 patch failed!"
            exit 1
        fi

    fi

    wget -q \
        https://raw.githubusercontent.com/Addster09/EverpalPatches/main/KSUPatches/defconfig-Enable-KSU-and-SUSFS.patch

    wget -q \
        https://raw.githubusercontent.com/Addster09/EverpalPatches/main/KSUPatches/susfs_patch_taskmmu.patch

    patch -p1 < defconfig-Enable-KSU-and-SUSFS.patch

    if [ $? -ne 0 ]; then
        echo "ERROR: KSU defconfig patch failed!"
        exit 1
    fi

    patch -p1 < susfs_patch_taskmmu.patch

    if [ $? -ne 0 ]; then
        echo "ERROR: taskmmu SUSFS patch failed!"
        exit 1
    fi

    rm -f defconfig-Enable-KSU-and-SUSFS.patch
    rm -f susfs_patch_taskmmu.patch

    rm -rf SU_patch

    touch out/.ksu_applied

    echo
    echo "KernelSU Next + SUSFS applied successfully."
fi

# ============================================================
# Defconfig
# ============================================================

echo
echo "========================================"
echo "Generating defconfig"
echo "========================================"

make \
    O=out \
    ARCH=arm64 \
    "$DEFCONFIG"

if [ $? -ne 0 ]; then
    echo "ERROR: defconfig failed!"
    exit 1
fi

# ============================================================
# Clang 22 compatibility
# ============================================================

echo
echo "========================================"
echo "Adjusting compiler compatibility"
echo "========================================"

# Linux 4.14 compiler check is incompatible
# with modern Clang versions.

sed -i \
    's/^CONFIG_CC_STACKPROTECTOR_STRONG=y/# CONFIG_CC_STACKPROTECTOR_STRONG is not set/' \
    out/.config

make \
    O=out \
    ARCH=arm64 \
    olddefconfig

if [ $? -ne 0 ]; then
    echo "ERROR: olddefconfig failed!"
    exit 1
fi

echo
echo "Stack protector configuration:"

grep "CONFIG_CC_STACKPROTECTOR" out/.config || true

# ============================================================
# Build
# ============================================================

echo
echo "========================================"
echo "Starting kernel compilation"
echo "========================================"

echo "Parallel jobs: $BUILD_JOBS"

echo "========================================"

make \
    -j"${BUILD_JOBS}" \
    O=out \
    ARCH=arm64 \
    CC=clang \
    LLVM=1 \
    LLVM_IAS=1 \
    KCFLAGS="-Wno-error=default-const-init-var-unsafe" \
    Image.gz \
    dtbs

BUILD_RESULT=$?

if [ $BUILD_RESULT -ne 0 ]; then

    echo
    echo "========================================"
    echo "COMPILATION FAILED"
    echo "========================================"

    exit $BUILD_RESULT
fi

# ============================================================
# Verify Image
# ============================================================

IMAGE="out/arch/arm64/boot/Image.gz"

echo
echo "========================================"
echo "Checking kernel image"
echo "========================================"

if [ ! -f "$IMAGE" ]; then
    echo "ERROR: Image.gz was not generated!"
    exit 1
fi

ls -lh "$IMAGE"

file "$IMAGE"

# ============================================================
# DTB
# ============================================================

echo
echo "========================================"
echo "Generated DTBs"
echo "========================================"

find out/arch/arm64/boot \
    -type f \
    -name "*.dtb" \
    -print

# ============================================================
# AnyKernel3
# ============================================================

echo
echo "========================================"
echo "Creating AnyKernel3 package"
echo "========================================"

rm -rf AnyKernel3

git clone \
    --depth=1 \
    https://github.com/Addster09/AnyKernel3 \
    AnyKernel3

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to clone AnyKernel3!"
    exit 1
fi

cp "$IMAGE" AnyKernel3/Image.gz

if [ ! -f AnyKernel3/Image.gz ]; then
    echo "ERROR: Failed to copy Image.gz!"
    exit 1
fi

(
    cd AnyKernel3 || exit 1

    zip -r9 \
        "../$ZIPNAME" \
        * \
        -x '*.git*' \
        README.md \
        '*placeholder'
)

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create kernel ZIP!"
    exit 1
fi

# ============================================================
# Verify ZIP
# ============================================================

if [ ! -f "$ZIPNAME" ]; then
    echo "ERROR: $ZIPNAME was not created!"
    exit 1
fi

ZIP_SIZE=$(du -h "$ZIPNAME" | cut -f1)

rm -rf AnyKernel3

# ============================================================
# Finish
# ============================================================

echo
echo "========================================"
echo "BUILD SUCCESSFUL"
echo "========================================"

echo "Kernel:"
echo "$IMAGE"

echo
echo "AnyKernel3:"
echo "$ZIPNAME"

echo
echo "ZIP size:"
echo "$ZIP_SIZE"

echo
echo "Completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)."

echo "========================================"

exit 0

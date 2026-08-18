#!/bin/bash

set -o pipefail

SECONDS=0
DATE="$(date '+%Y%m%d-%H%M')"

CURRENT_DIR="$(pwd)"

# ============================================================
# Device
# ============================================================

DEVICE="camellia"
DEFCONFIG="camellia_defconfig"

# ============================================================
# Toolchain
# ============================================================

TC_DIR="$HOME/toolchains/ZyC-clang-22.0.0"

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
        *)
            echo "Warning: unknown option: $arg"
            ;;
    esac
done

# ============================================================
# Output
# ============================================================

ARTIFACT_DIR="$CURRENT_DIR/artifacts"

# ============================================================
# Information
# ============================================================

echo
echo "========================================"
echo "Aqua / evergey Camellia Kernel Build"
echo "========================================"

echo "Device        : $DEVICE"
echo "Defconfig     : $DEFCONFIG"
echo "Build jobs    : $BUILD_JOBS"
echo "KernelSU      : $INCLUDE_KSU"
echo "Output        : out"
echo "Artifact dir  : $ARTIFACT_DIR"

echo "========================================"

# ============================================================
# Check source
# ============================================================

echo
echo "========================================"
echo "Checking source"
echo "========================================"

if [ ! -f "Makefile" ]; then
    echo "ERROR: Kernel Makefile not found."
    exit 1
fi

if [ ! -f "arch/arm64/configs/$DEFCONFIG" ]; then
    echo "ERROR: $DEFCONFIG not found."
    exit 1
fi

if [ ! -f "scripts/config" ]; then
    echo "ERROR: scripts/config not found."
    exit 1
fi

chmod +x scripts/config

echo "Kernel source:"
pwd

echo
echo "Defconfig:"
ls -lh "arch/arm64/configs/$DEFCONFIG"

# ============================================================
# Clean generated files
# ============================================================

echo
echo "========================================"
echo "Cleaning generated files"
echo "========================================"

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
    echo "Complete clean build requested."
    rm -rf out
fi

mkdir -p out
rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"

# ============================================================
# Prepare Clang 22
# ============================================================

echo
echo "========================================"
echo "Preparing ZyCromerZ Clang 22"
echo "========================================"

if [ ! -x "$TC_DIR/bin/clang" ]; then

    echo "Clang 22 not found."

    mkdir -p "$TC_DIR"

    cd "$TC_DIR" || exit 1

    TOOLCHAIN_ARCHIVE="Clang-22.0.0git-20250928.tar.gz"

    echo "Downloading:"
    echo "$TOOLCHAIN_ARCHIVE"

    wget -q --show-progress \
        "https://github.com/ZyCromerZ/Clang/releases/download/22.0.0git-20250928-release/${TOOLCHAIN_ARCHIVE}"

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to download Clang 22."
        exit 1
    fi

    tar -xf "$TOOLCHAIN_ARCHIVE"

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to extract Clang 22."
        exit 1
    fi

    rm -f "$TOOLCHAIN_ARCHIVE"

    cd "$CURRENT_DIR" || exit 1
fi

export PATH="$TC_DIR/bin:$PATH"

# ============================================================
# Compiler environment
# ============================================================

export ARCH=arm64
export SUBARCH=arm64

export LLVM=1
export LLVM_IAS=1

export CC=clang
export LD=ld.lld

# Important for old 4.14 Android Kbuild
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-

# ============================================================
# Compiler checks
# ============================================================

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

echo
echo "llvm-ar:"
command -v llvm-ar
llvm-ar --version | head -1

echo
echo "llvm-nm:"
command -v llvm-nm

echo
echo "llvm-objcopy:"
command -v llvm-objcopy

echo
echo "clang target:"
clang --target=aarch64-linux-gnu -print-target-triple

echo
echo "CLANG_TRIPLE:"
echo "$CLANG_TRIPLE"

echo
echo "CROSS_COMPILE:"
echo "$CROSS_COMPILE"

# ============================================================
# KernelSU Next + SUSFS
# ============================================================

if [ "$INCLUDE_KSU" = true ]; then

    echo
    echo "========================================"
    echo "KernelSU Next + SUSFS ENABLED"
    echo "========================================"

    if [ ! -f out/.ksu_applied ]; then

        curl -LSs \
            "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" \
            | bash

        if [ $? -ne 0 ]; then
            echo "ERROR: KernelSU setup failed."
            exit 1
        fi

        git clone \
            --depth=1 \
            "https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd.git" \
            SU_patch

        if [ $? -ne 0 ]; then
            echo "ERROR: Failed to clone SU_patch."
            exit 1
        fi

        for patch in SU_patch/Patches/*sh; do

            if [ -f "$patch" ]; then

                echo
                echo "Applying:"
                echo "$patch"

                bash "$patch"

                if [ $? -ne 0 ]; then
                    echo "ERROR: Patch failed:"
                    echo "$patch"
                    exit 1
                fi

            fi

        done

        if [ -f "SU_patch/Patches/Patch/susfs_patch_to_4.14.patch" ]; then

            echo
            echo "Applying SUSFS 4.14 patch..."

            patch -p1 \
                < "SU_patch/Patches/Patch/susfs_patch_to_4.14.patch"

            if [ $? -ne 0 ]; then
                echo "ERROR: SUSFS 4.14 patch failed."
                exit 1
            fi

        fi

        wget -q \
            "https://raw.githubusercontent.com/Addster09/EverpalPatches/main/KSUPatches/defconfig-Enable-KSU-and-SUSFS.patch"

        wget -q \
            "https://raw.githubusercontent.com/Addster09/EverpalPatches/main/KSUPatches/susfs_patch_taskmmu.patch"

        patch -p1 \
            < defconfig-Enable-KSU-and-SUSFS.patch

        if [ $? -ne 0 ]; then
            echo "ERROR: KSU defconfig patch failed."
            exit 1
        fi

        patch -p1 \
            < susfs_patch_taskmmu.patch

        if [ $? -ne 0 ]; then
            echo "ERROR: SUSFS taskmmu patch failed."
            exit 1
        fi

        rm -f defconfig-Enable-KSU-and-SUSFS.patch
        rm -f susfs_patch_taskmmu.patch
        rm -rf SU_patch

        touch out/.ksu_applied

        echo
        echo "KernelSU Next + SUSFS applied successfully."

    else

        echo "KernelSU patch marker already exists."

    fi

else

    echo
    echo "========================================"
    echo "KernelSU Next + SUSFS DISABLED"
    echo "========================================"

fi

# ============================================================
# Generate Camellia defconfig
# ============================================================

echo
echo "========================================"
echo "Generating Camellia defconfig"
echo "========================================"

make \
    O=out \
    ARCH=arm64 \
    CLANG_TRIPLE="$CLANG_TRIPLE" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    LLVM=1 \
    LLVM_IAS=1 \
    "$DEFCONFIG"

DEFCONFIG_RESULT=$?

if [ $DEFCONFIG_RESULT -ne 0 ]; then
    echo "ERROR: defconfig failed."
    exit $DEFCONFIG_RESULT
fi

# ============================================================
# Set unique version string
# ============================================================

echo
echo "========================================"
echo "Setting kernel local version"
echo "========================================"

scripts/config \
    --file out/.config \
    --set-str LOCALVERSION "-AquaCamellia"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to set LOCALVERSION."
    exit 1
fi

# ============================================================
# Clang 22 compatibility
# ============================================================

echo
echo "========================================"
echo "Adjusting Clang compatibility"
echo "========================================"

# Old Linux 4.14 compiler check can reject modern Clang.
if grep -q '^CONFIG_CC_STACKPROTECTOR_STRONG=y' out/.config; then

    echo "Disabling CONFIG_CC_STACKPROTECTOR_STRONG..."

    scripts/config \
        --file out/.config \
        --disable CC_STACKPROTECTOR_STRONG

fi

make \
    O=out \
    ARCH=arm64 \
    CLANG_TRIPLE="$CLANG_TRIPLE" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    LLVM=1 \
    LLVM_IAS=1 \
    olddefconfig

OLDDEFCONFIG_RESULT=$?

if [ $OLDDEFCONFIG_RESULT -ne 0 ]; then
    echo "ERROR: olddefconfig failed."
    exit $OLDDEFCONFIG_RESULT
fi

# ============================================================
# Show final configuration
# ============================================================

echo
echo "========================================"
echo "Final Camellia configuration"
echo "========================================"

grep '^CONFIG_ARCH_MTK_PROJECT' out/.config || true
grep '^CONFIG_CUSTOM_KERNEL_IMGSENSOR' out/.config || true
grep '^CONFIG_CUSTOM_KERNEL_LCM' out/.config || true
grep '^CONFIG_MTK_FINGERPRINT_SELECT' out/.config || true
grep '^CONFIG_LOCALVERSION' out/.config || true
grep '^CONFIG_LTO' out/.config || true
grep '^CONFIG_CC_STACKPROTECTOR' out/.config || true

# ============================================================
# Build kernel
# ============================================================

echo
echo "========================================"
echo "Starting kernel compilation"
echo "========================================"

echo "Parallel jobs : $BUILD_JOBS"
echo "Device        : $DEVICE"
echo "Defconfig     : $DEFCONFIG"
echo "Compiler      : $(clang --version | head -1)"
echo "CLANG_TRIPLE  : $CLANG_TRIPLE"
echo "CROSS_COMPILE : $CROSS_COMPILE"

echo "========================================"

make \
    -j"${BUILD_JOBS}" \
    O=out \
    ARCH=arm64 \
    CC=clang \
    CLANG_TRIPLE="$CLANG_TRIPLE" \
    CROSS_COMPILE="$CROSS_COMPILE" \
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

    echo "Exit code: $BUILD_RESULT"

    exit $BUILD_RESULT
fi

# ============================================================
# Verify Image.gz
# ============================================================

IMAGE="out/arch/arm64/boot/Image.gz"

echo
echo "========================================"
echo "Verifying Image.gz"
echo "========================================"

if [ ! -f "$IMAGE" ]; then
    echo "ERROR: Image.gz was not generated."
    exit 1
fi

ls -lh "$IMAGE"

file "$IMAGE"

# ============================================================
# Verify kernel version
# ============================================================

echo
echo "========================================"
echo "Kernel version"
echo "========================================"

rm -f /tmp/AquaCamellia-Image

gunzip -c "$IMAGE" > /tmp/AquaCamellia-Image

strings /tmp/AquaCamellia-Image \
    | grep -m1 "Linux version" \
    || true

rm -f /tmp/AquaCamellia-Image

# ============================================================
# Copy artifacts
# ============================================================

echo
echo "========================================"
echo "Collecting artifacts"
echo "========================================"

cp "$IMAGE" \
    "$ARTIFACT_DIR/Image.gz"

cp out/.config \
    "$ARTIFACT_DIR/camellia.config"

if [ -f "System.map" ]; then
    cp System.map "$ARTIFACT_DIR/System.map"
fi

find out/arch/arm64/boot \
    -type f \
    -name "*.dtb" \
    -exec cp --parents {} "$ARTIFACT_DIR/" \;

echo
echo "Artifact tree:"

find "$ARTIFACT_DIR" \
    -type f \
    -print \
    | sort

# ============================================================
# Finish
# ============================================================

echo
echo "========================================"
echo "BUILD SUCCESSFUL"
echo "========================================"

echo "Device       : $DEVICE"
echo "Kernel image : $IMAGE"
echo "Artifacts    : $ARTIFACT_DIR"

echo
echo "Completed in:"
echo "$((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)"

echo "========================================"

exit 0

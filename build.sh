#!/bin/bash

set -o pipefail

SECONDS=0
DATE="$(date '+%Y%m%d-%H%M')"

CURRENT_DIR="$(pwd)"

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
        *)
            echo "Warning: unknown option: $arg"
            ;;
    esac
done

# ============================================================
# Build information
# ============================================================

echo
echo "========================================"
echo "Aqua / evergey Kernel Build"
echo "========================================"

echo "Kernel       : Linux 4.14"
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

# ============================================================
# Check defconfig
# ============================================================

echo
echo "========================================"
echo "Checking defconfig"
echo "========================================"

if [ ! -f "arch/arm64/configs/$DEFCONFIG" ]; then
    echo "ERROR: arch/arm64/configs/$DEFCONFIG not found!"
    exit 1
fi

echo "Found:"
ls -lh "arch/arm64/configs/$DEFCONFIG"

# ============================================================
# Prepare ZyCromerZ Clang 22
# ============================================================

echo
echo "========================================"
echo "Preparing ZyCromerZ Clang 22"
echo "========================================"

if [ ! -x "$TC_DIR/bin/clang" ]; then

    echo "Clang 22 not found."
    echo "Downloading..."

    mkdir -p "$TC_DIR"

    cd "$TC_DIR" || exit 1

    TOOLCHAIN_ARCHIVE="Clang-22.0.0git-20250928.tar.gz"

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
# Kernel build environment
# ============================================================

export ARCH=arm64
export SUBARCH=arm64

export LLVM=1
export LLVM_IAS=1

export CC=clang
export LD=ld.lld

# IMPORTANT:
# This old Android 4.14 Kbuild uses CLANG_TRIPLE / CROSS_COMPILE
# to establish the AArch64 target for Clang.
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-

# Do not force HOSTCC/HOSTCXX here.
# The kernel's own Makefile selects them when LLVM=1.

# ============================================================
# Compiler information
# ============================================================

echo
echo "========================================"
echo "Compiler"
echo "========================================"

echo "clang:"
command -v clang
clang --version

echo
echo "clang target:"
clang -print-target-triple

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
echo "Configured target:"
echo "$CLANG_TRIPLE"

echo
echo "CROSS_COMPILE:"
echo "$CROSS_COMPILE"

# ============================================================
# Check target triple explicitly
# ============================================================

echo
echo "========================================"
echo "Testing AArch64 Clang target"
echo "========================================"

cat > /tmp/test_arm64.c <<'EOF'
int test_function(void)
{
    return 0;
}
EOF

clang \
    --target=aarch64-linux-gnu \
    -c \
    /tmp/test_arm64.c \
    -o /tmp/test_arm64.o

if [ $? -ne 0 ]; then
    echo "ERROR: Clang cannot compile for AArch64."
    exit 1
fi

file /tmp/test_arm64.o

rm -f /tmp/test_arm64.c
rm -f /tmp/test_arm64.o

# ============================================================
# KernelSU Next + SUSFS
# ============================================================

if [ -f out/.ksu_applied ]; then
    echo
    echo "KernelSU Next has already been applied."
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
            echo "Applying patch script:"
            echo "$patch"

            bash "$patch"

            if [ $? -ne 0 ]; then
                echo "ERROR: Patch script failed:"
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

    echo
    echo "Downloading Everpal KSU patches..."

    wget -q \
        "https://raw.githubusercontent.com/Addster09/EverpalPatches/main/KSUPatches/defconfig-Enable-KSU-and-SUSFS.patch"

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to download KSU defconfig patch."
        exit 1
    fi

    wget -q \
        "https://raw.githubusercontent.com/Addster09/EverpalPatches/main/KSUPatches/susfs_patch_taskmmu.patch"

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to download SUSFS taskmmu patch."
        exit 1
    fi

    echo
    echo "Applying KSU/SUSFS defconfig patch..."

    patch -p1 < defconfig-Enable-KSU-and-SUSFS.patch

    if [ $? -ne 0 ]; then
        echo "ERROR: KSU defconfig patch failed."
        exit 1
    fi

    echo
    echo "Applying taskmmu SUSFS patch..."

    patch -p1 < susfs_patch_taskmmu.patch

    if [ $? -ne 0 ]; then
        echo "ERROR: taskmmu SUSFS patch failed."
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
# Generate defconfig
# ============================================================

echo
echo "========================================"
echo "Generating defconfig"
echo "========================================"

make \
    O=out \
    ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    LLVM=1 \
    LLVM_IAS=1 \
    "$DEFCONFIG"

DEFCONFIG_RESULT=$?

if [ $DEFCONFIG_RESULT -ne 0 ]; then
    echo "ERROR: defconfig failed."
    exit $DEFCONFIG_RESULT
fi

# ============================================================
# Clang 22 / old-kernel compatibility
# ============================================================

echo
echo "========================================"
echo "Adjusting compiler compatibility"
echo "========================================"

if grep -q '^CONFIG_CC_STACKPROTECTOR_STRONG=y' out/.config; then

    echo "Disabling CONFIG_CC_STACKPROTECTOR_STRONG..."

    sed -i \
        's/^CONFIG_CC_STACKPROTECTOR_STRONG=y/# CONFIG_CC_STACKPROTECTOR_STRONG is not set/' \
        out/.config
fi

make \
    O=out \
    ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    LLVM=1 \
    LLVM_IAS=1 \
    olddefconfig

OLDDEFCONFIG_RESULT=$?

if [ $OLDDEFCONFIG_RESULT -ne 0 ]; then
    echo "ERROR: olddefconfig failed."
    exit $OLDDEFCONFIG_RESULT
fi

echo
echo "Stack protector configuration:"

grep "CONFIG_CC_STACKPROTECTOR" out/.config || true

# ============================================================
# Build command diagnostic
# ============================================================

echo
echo "========================================"
echo "Build environment"
echo "========================================"

echo "ARCH          = $ARCH"
echo "SUBARCH       = $SUBARCH"
echo "CC            = $CC"
echo "LD            = $LD"
echo "LLVM          = $LLVM"
echo "LLVM_IAS      = $LLVM_IAS"
echo "CLANG_TRIPLE  = $CLANG_TRIPLE"
echo "CROSS_COMPILE = $CROSS_COMPILE"
echo "BUILD_JOBS    = $BUILD_JOBS"

# ============================================================
# Kernel compilation
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
    CLANG_TRIPLE=aarch64-linux-gnu- \
    CROSS_COMPILE=aarch64-linux-gnu- \
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

    echo
    echo "For diagnostic purposes, print the exact command"
    echo "for scripts/mod/empty.o with V=1..."

    make \
        -j1 \
        O=out \
        ARCH=arm64 \
        CC=clang \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-gnu- \
        LLVM=1 \
        LLVM_IAS=1 \
        V=1 \
        scripts/mod/empty.o \
        || true

    exit $BUILD_RESULT
fi

# ============================================================
# Verify Image.gz
# ============================================================

IMAGE="out/arch/arm64/boot/Image.gz"

echo
echo "========================================"
echo "Checking kernel image"
echo "========================================"

if [ ! -f "$IMAGE" ]; then
    echo "ERROR: Image.gz was not generated."
    exit 1
fi

echo "Kernel image:"
ls -lh "$IMAGE"

echo
file "$IMAGE"

# ============================================================
# Show DTBs
# ============================================================

echo
echo "========================================"
echo "Generated DTBs"
echo "========================================"

find out/arch/arm64/boot \
    -type f \
    -name "*.dtb" \
    -print \
    | sort

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
    "https://github.com/Addster09/AnyKernel3" \
    AnyKernel3

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to clone AnyKernel3."
    exit 1
fi

cp "$IMAGE" AnyKernel3/Image.gz

if [ ! -f AnyKernel3/Image.gz ]; then
    echo "ERROR: Failed to copy Image.gz."
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

ZIP_RESULT=$?

if [ $ZIP_RESULT -ne 0 ]; then
    echo "ERROR: Failed to create kernel ZIP."
    exit $ZIP_RESULT
fi

# ============================================================
# Verify ZIP
# ============================================================

echo
echo "========================================"
echo "Checking kernel ZIP"
echo "========================================"

if [ ! -f "$ZIPNAME" ]; then
    echo "ERROR: $ZIPNAME was not created."
    exit 1
fi

ZIP_SIZE="$(du -h "$ZIPNAME" | cut -f1)"

ls -lh "$ZIPNAME"

echo
echo "ZIP size: $ZIP_SIZE"

# ============================================================
# Cleanup
# ============================================================

rm -rf AnyKernel3

# ============================================================
# Finished
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
echo "Completed in:"
echo "$((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)"

echo "========================================"

exit 0

#!/bin/bash

# Compile script for Aqua / evergey kernel

set -o pipefail

SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')

CURRENT_DIR=$(pwd)

# Toolchain
TC_DIR="$HOME/toolchains/ZyC-clang-22.0.0"

# Device Config
DEVICE="everpal"
DEFCONFIG="${DEVICE}_defconfig"
ZIPNAME="AquaKernel-${DATE}.zip"

echo "========================================"
echo "Aqua Kernel Build"
echo "========================================"
echo "Device     : $DEVICE"
echo "Defconfig  : $DEFCONFIG"
echo "Output     : out"
echo "Zip        : $ZIPNAME"
echo "========================================"

# ------------------------------------------------------------
# Clean generated files
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# Optional clean build
# ------------------------------------------------------------

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

if [ "$CLEAN_BUILD" = true ]; then
    echo "Performing complete clean build..."
    rm -rf out
fi

mkdir -p out

# ------------------------------------------------------------
# Toolchain
# ------------------------------------------------------------

if [ ! -d "$TC_DIR" ]; then

    echo
    echo "========================================"
    echo "Downloading ZyCromerZ Clang 22"
    echo "========================================"

    mkdir -p "$TC_DIR"

    cd "$TC_DIR" || exit 1

    wget -q --show-progress \
        https://github.com/ZyCromerZ/Clang/releases/download/22.0.0git-20250928-release/Clang-22.0.0git-20250928.tar.gz

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

command -v clang
clang --version

echo
command -v ld.lld
ld.lld --version

# ------------------------------------------------------------
# KernelSU Next
# ------------------------------------------------------------

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

    git clone \
        https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd.git \
        --depth=1 \
        SU_patch

    for patch in SU_patch/Patches/*sh; do
        if [ -f "$patch" ]; then
            bash "$patch"
        fi
    done

    if [ -f SU_patch/Patches/Patch/susfs_patch_to_4.14.patch ]; then
        patch -p1 < SU_patch/Patches/Patch/susfs_patch_to_4.14.patch
    fi

    wget -q \
        https://raw.githubusercontent.com/Addster09/EverpalPatches/main/KSUPatches/defconfig-Enable-KSU-and-SUSFS.patch

    wget -q \
        https://raw.githubusercontent.com/Addster09/EverpalPatches/main/KSUPatches/susfs_patch_taskmmu.patch

    patch -p1 < defconfig-Enable-KSU-and-SUSFS.patch
    patch -p1 < susfs_patch_taskmmu.patch

    rm -f defconfig-Enable-KSU-and-SUSFS.patch
    rm -f susfs_patch_taskmmu.patch

    rm -rf SU_patch

    touch out/.ksu_applied

    echo "KernelSU Next + SUSFS applied."
fi

# ------------------------------------------------------------
# Defconfig
# ------------------------------------------------------------

echo
echo "========================================"
echo "Generating kernel configuration"
echo "========================================"

if [ ! -f "arch/arm64/configs/$DEFCONFIG" ]; then
    echo "ERROR: $DEFCONFIG not found!"
    exit 1
fi

make \
    O=out \
    ARCH=arm64 \
    "$DEFCONFIG"

if [ $? -ne 0 ]; then
    echo "ERROR: defconfig failed!"
    exit 1
fi

# ------------------------------------------------------------
# Build
# ------------------------------------------------------------

BUILD_JOBS="${BUILD_JOBS:-2}"

echo
echo "========================================"
echo "Starting compilation"
echo "========================================"
echo "Parallel jobs: $BUILD_JOBS"
echo "========================================"

if make \
    -j"${BUILD_JOBS}" \
    O=out \
    ARCH=arm64 \
    CC="ccache clang" \
    LLVM=1 \
    LLVM_IAS=1 \
    KCFLAGS="-Wno-error=default-const-init-var-unsafe" \
    Image.gz \
    dtbs; then

    echo
    echo "========================================"
    echo "Kernel compiled successfully!"
    echo "========================================"

else

    echo
    echo "========================================"
    echo "Compilation FAILED!"
    echo "========================================"

    exit 1
fi

# ------------------------------------------------------------
# Verify Image
# ------------------------------------------------------------

IMAGE="out/arch/arm64/boot/Image.gz"

echo
echo "Checking kernel image..."

if [ ! -f "$IMAGE" ]; then
    echo "ERROR: Image.gz was not generated!"
    exit 1
fi

echo "Image:"
ls -lh "$IMAGE"

# ------------------------------------------------------------
# AnyKernel3
# ------------------------------------------------------------

echo
echo "========================================"
echo "Creating AnyKernel3 package"
echo "========================================"

rm -rf AnyKernel3

git clone \
    -q \
    --depth=1 \
    https://github.com/Addster09/AnyKernel3 \
    AnyKernel3

if [ ! -d AnyKernel3 ]; then
    echo "ERROR: Failed to clone AnyKernel3!"
    exit 1
fi

cp "$IMAGE" AnyKernel3/Image.gz

(
    cd AnyKernel3 || exit 1

    zip -r9 \
        "../$ZIPNAME" \
        * \
        -x '*.git*' \
        README.md \
        '*placeholder'
)

if [ ! -f "$ZIPNAME" ]; then
    echo "ERROR: AnyKernel ZIP was not created!"
    exit 1
fi

# ------------------------------------------------------------
# Finish
# ------------------------------------------------------------

rm -rf AnyKernel3

echo
echo "========================================"
echo "BUILD SUCCESSFUL"
echo "========================================"

echo "Kernel : $IMAGE"
echo "ZIP    : $ZIPNAME"
echo "Size   : $(du -h "$ZIPNAME" | cut -f1)"

echo
echo "Completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)."

exit 0

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVER="$(uname -r)"
KVER_BASE="${KVER%%-*}"
MAJOR_VER="${KVER_BASE%%.*}"
BUILD_DIR="/usr/lib/modules/${KVER}/build"
UPDATES_DIR="/usr/lib/modules/${KVER}/updates"
SRC_DIR="${SCRIPT_DIR}/linux-${KVER_BASE}"

echo "==> Target kernel: ${KVER} (base: ${KVER_BASE})"

if [[ ! -d "${BUILD_DIR}" ]]; then
    echo "ERROR: Kernel build directory ${BUILD_DIR} not found!" >&2
    echo "Please ensure kernel headers are installed (e.g. linux-headers or linux-omarchy-headers)." >&2
    exit 1
fi

# Ensure source directory exists
if [[ ! -d "${SRC_DIR}/drivers/gpu/drm/amd/amdgpu" ]]; then
    echo "==> Kernel source not found locally. Downloading drivers from kernel.org..."
    TAR_URL="https://cdn.kernel.org/pub/linux/kernel/v${MAJOR_VER}.x/linux-${KVER_BASE}.tar.xz"
    mkdir -p "${SRC_DIR}"
    if command -v curl >/dev/null 2>&1; then
        curl -fL "${TAR_URL}" | tar -xJ -C "${SRC_DIR}" --strip-components=1 \
            "linux-${KVER_BASE}/drivers/gpu/drm/amd" \
            "linux-${KVER_BASE}/include"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "${TAR_URL}" | tar -xJ -C "${SRC_DIR}" --strip-components=1 \
            "linux-${KVER_BASE}/drivers/gpu/drm/amd" \
            "linux-${KVER_BASE}/include"
    else
        echo "ERROR: Neither curl nor wget found to download kernel source." >&2
        exit 1
    fi
fi

# Apply patch if not already applied
if ! grep -q "amdgpu_fclk_fix" "${SRC_DIR}/drivers/gpu/drm/amd/pm/swsmu/smu13/smu_v13_0_4_ppt.c" 2>/dev/null; then
    echo "==> Applying amdgpu-fclk-floor.patch..."
    patch -d "${SRC_DIR}" -p1 < "${SCRIPT_DIR}/amdgpu-fclk-floor.patch"
fi

echo "==> Compiling amdgpu module..."
make -j"$(nproc)" -C "${BUILD_DIR}" M="${SRC_DIR}/drivers/gpu/drm/amd/amdgpu" modules

echo "==> Stripping debug symbols..."
strip --strip-debug "${SRC_DIR}/drivers/gpu/drm/amd/amdgpu/amdgpu.ko" -o "${SCRIPT_DIR}/amdgpu.ko"

echo "==> Compressing with zstd..."
zstd -f -19 "${SCRIPT_DIR}/amdgpu.ko" -o "${SCRIPT_DIR}/amdgpu.ko.zst"
rm -f "${SCRIPT_DIR}/amdgpu.ko"

echo "==> Installing to ${UPDATES_DIR}/amdgpu.ko.zst..."
mkdir -p "${UPDATES_DIR}"
cp -f "${SCRIPT_DIR}/amdgpu.ko.zst" "${UPDATES_DIR}/amdgpu.ko.zst"

echo "==> Running depmod..."
depmod -a

echo "==> Updating boot images..."
if command -v limine-mkinitcpio >/dev/null 2>&1; then
    limine-mkinitcpio
elif command -v mkinitcpio >/dev/null 2>&1; then
    mkinitcpio -P
else
    echo "WARNING: Neither limine-mkinitcpio nor mkinitcpio found. Please update your initramfs manually." >&2
fi

echo "==> Success! Reboot your system to load the updated driver."

#!/usr/bin/env bash
set -euo pipefail

KVER="$(uname -r)"
UPDATES_DIR="/usr/lib/modules/${KVER}/updates"

echo "==> Reverting amdgpu module to factory stock for kernel ${KVER}..."

if [[ -f "${UPDATES_DIR}/amdgpu.ko.zst" ]]; then
    rm -f "${UPDATES_DIR}/amdgpu.ko.zst"
    echo "Removed ${UPDATES_DIR}/amdgpu.ko.zst"
fi

if [[ -d "${UPDATES_DIR}" ]] && [[ -z "$(ls -A "${UPDATES_DIR}")" ]]; then
    rmdir "${UPDATES_DIR}"
    echo "Removed empty directory ${UPDATES_DIR}"
fi

echo "==> Updating module dependencies..."
depmod -a

echo "==> Updating boot images..."
if command -v limine-mkinitcpio >/dev/null 2>&1; then
    limine-mkinitcpio
elif command -v mkinitcpio >/dev/null 2>&1; then
    mkinitcpio -P
else
    echo "WARNING: Neither limine-mkinitcpio nor mkinitcpio found. Please update your initramfs manually." >&2
fi

echo "==> Done! Factory stock driver restored. Reboot to load it."

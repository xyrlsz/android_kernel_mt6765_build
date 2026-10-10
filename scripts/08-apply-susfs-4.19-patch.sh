#!/usr/bin/env bash
set -euo pipefail

KERNEL_MAJOR=$(sed -n 's/^VERSION = //p' Makefile)
KERNEL_MINOR=$(sed -n 's/^PATCHLEVEL = //p' Makefile)
if [ "$KERNEL_MAJOR" != "4" ] || [ "$KERNEL_MINOR" != "19" ]; then
  echo "::error::指定的 SUSFS 补丁仅适用于 Linux 4.19；当前版本为 ${KERNEL_MAJOR:-unknown}.${KERNEL_MINOR:-unknown}"
  exit 1
fi

PATCH_COMMIT="b5d7e5be60398f040b9e9919186c410c01a228da"
PATCH_URL="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/${PATCH_COMMIT}/Patches/Patch/susfs_patch_to_4.19.patch"
EXPECTED_SHA256="5E277F18FC8304E0818CEA3E8A7B838292CB9E59FDFFDAA1BE9CEFA288ABBADB"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ADAPTATION_PATCH="$SCRIPT_DIR/patches/susfs-4.19-adaptation.patch"
PATCH_FILE=$(mktemp)
trap 'rm -f "$PATCH_FILE"' EXIT

echo "===== 下载 SUSFS v2.3.0 Linux 4.19 移植补丁（固定提交 ${PATCH_COMMIT}） ====="
curl -fL --retry 3 --retry-delay 5 -o "$PATCH_FILE" "$PATCH_URL"
echo "$EXPECTED_SHA256  $PATCH_FILE" | sha256sum --check --status || {
  echo "::error::SUSFS 补丁 SHA-256 校验失败"
  exit 1
}

echo "===== 检查 SUSFS 补丁是否适配当前内核源码 ====="
if grep -Fq 'obj-$(CONFIG_KSU_SUSFS) += susfs.o' fs/Makefile ||
  grep -Fq 'susfs_spoof_cmdline_or_bootconfig' fs/proc/cmdline.c; then
  echo "::error::检测到 SUSFS 补丁或相关适配已存在，拒绝重复应用"
  exit 1
fi

echo "===== 检查 SUSFS 补丁（适配文件） ====="
if ! git apply --check \
  --exclude=fs/Makefile \
  --exclude=fs/proc/cmdline.c \
  "$PATCH_FILE" ||
  ! git apply --check --ignore-space-change "$ADAPTATION_PATCH"; then
  echo "::error::SUSFS 补丁无法应用到当前内核源码；请确认补丁基线兼容"
  exit 1
fi

echo "===== 应用 SUSFS 内核侧补丁 ====="
git apply \
  --exclude=fs/Makefile \
  --exclude=fs/proc/cmdline.c \
  "$PATCH_FILE"
git apply --ignore-space-change "$ADAPTATION_PATCH"

echo "===== SUSFS 4.19 补丁应用完成 ====="
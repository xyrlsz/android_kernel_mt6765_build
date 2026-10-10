#!/usr/bin/env bash
set -euo pipefail

KERNEL_MAJOR=$(sed -n 's/^VERSION = //p' Makefile)
KERNEL_MINOR=$(sed -n 's/^PATCHLEVEL = //p' Makefile)
if [ "$KERNEL_MAJOR" != "4" ] || [ "$KERNEL_MINOR" != "19" ]; then
  echo "::error::此 SUSFS 补丁仅适用于 Linux 4.19；当前版本为 ${KERNEL_MAJOR:-unknown}.${KERNEL_MINOR:-unknown}"
  exit 1
fi

PATCH_COMMIT="b5d7e5be60398f040b9e9919186c410c01a228da"
PATCH_URL="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/${PATCH_COMMIT}/Patches/Patch/susfs_patch_to_4.19.patch"
EXPECTED_SHA256="5E277F18FC8304E0818CEA3E8A7B838292CB9E59FDFFDAA1BE9CEFA288ABBADB"
REQUIRED_SUSFS_VERSION="v2.3.0"
SUSFS_HEADER="include/linux/susfs.h"
PATCH_FILE=$(mktemp)
trap 'rm -f "$PATCH_FILE"' EXIT

echo "===== 检查内核源码中的 SUSFS 版本 ====="
if [ -f "$SUSFS_HEADER" ]; then
  current=$(sed -n 's/^#define SUSFS_VERSION[[:space:]]*"\(.*\)"/\1/p' "$SUSFS_HEADER" | head -n1)
  if [ -n "$current" ] && [ "$(printf '%s\n%s\n' "${REQUIRED_SUSFS_VERSION#v}" "${current#v}" | sort -V | tail -n1)" = "${current#v}" ]; then
    echo "===== 已带有 SUSFS ${current}（>= ${REQUIRED_SUSFS_VERSION}），跳过重复应用 ====="
    exit 0
  fi
  echo "::error::内核源码仍带有旧版 SUSFS（${current:-未知}），与 Baka-SU 需要的 ${REQUIRED_SUSFS_VERSION} 不兼容"
  echo "::error::请确认 06-strip-legacy-kernelsu.sh 已清理旧的 KernelSU / SUSFS 集成"
  exit 1
fi

echo "===== 下载 SUSFS ${REQUIRED_SUSFS_VERSION} Linux 4.19 移植补丁（固定提交 ${PATCH_COMMIT}） ====="
curl -fL --retry 3 --retry-delay 5 -o "$PATCH_FILE" "$PATCH_URL"
echo "$EXPECTED_SHA256  $PATCH_FILE" | sha256sum --check --status || {
  echo "::error::SUSFS 补丁 SHA-256 校验失败"
  exit 1
}

echo "===== 检查 SUSFS 补丁能否应用到当前内核源码 ====="
if ! git apply --check "$PATCH_FILE"; then
  echo "::error::SUSFS 补丁无法应用到当前内核源码；上面列出的文件需要按当前内核基线适配"
  exit 1
fi

echo "===== 应用 SUSFS 内核侧补丁 ====="
git apply "$PATCH_FILE"

echo "===== SUSFS 4.19 补丁应用完成 ====="

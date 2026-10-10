#!/usr/bin/env bash
set -euo pipefail

# 上游补丁（JackA1ltman/NonGKI_Kernel_Build_2nd @ b5d7e5be60398f040b9e9919186c410c01a228da
#   Patches/Patch/susfs_patch_to_4.19.patch，sha256 5E277F18...BADB）的上下文按另一套 4.19 基线写成，
# 无法直接应用到本内核（fs/namei.c、fs/namespace.c、fs/proc/*、fs/readdir.c、fs/statfs.c、
# fs/notify/fdinfo.c、kernel/kallsyms.c、kernel/sys.c、mm/memory.c、security/selinux/avc.c 等对不上）。
# 因此本步骤应用按当前基线适配后的补丁 scripts/patches/susfs-4.19-adapted.patch：
# hook 代码内容与上游完全一致，仅调整落点/上下文。

KERNEL_MAJOR=$(sed -n 's/^VERSION = //p' Makefile)
KERNEL_MINOR=$(sed -n 's/^PATCHLEVEL = //p' Makefile)
if [ "$KERNEL_MAJOR" != "4" ] || [ "$KERNEL_MINOR" != "19" ]; then
  echo "::error::此 SUSFS 补丁仅适用于 Linux 4.19；当前版本为 ${KERNEL_MAJOR:-unknown}.${KERNEL_MINOR:-unknown}"
  exit 1
fi

REQUIRED_SUSFS_VERSION="v2.3.0"
SUSFS_HEADER="include/linux/susfs.h"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ADAPTED_PATCH="$SCRIPT_DIR/patches/susfs-4.19-adapted.patch"

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

if [ ! -f "$ADAPTED_PATCH" ]; then
  echo "::error::缺少 SUSFS 适配补丁：$ADAPTED_PATCH"
  exit 1
fi

echo "===== 检查 SUSFS ${REQUIRED_SUSFS_VERSION} 补丁能否应用 ====="
if ! git apply --check "$ADAPTED_PATCH"; then
  echo "::error::SUSFS 补丁无法应用到当前内核源码；上面的文件需要重新做基线适配"
  exit 1
fi

echo "===== 应用 SUSFS 内核侧补丁 ====="
git apply "$ADAPTED_PATCH"

echo "===== 验证 SUSFS 集成结果 ====="
for f in fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h; do
  if [ ! -f "$f" ]; then
    echo "::error::SUSFS 补丁应用后缺少 $f"
    exit 1
  fi
done
if ! grep -q '^obj-\$(CONFIG_KSU_SUSFS) += susfs.o' fs/Makefile; then
  echo "::error::fs/Makefile 缺少 susfs.o"
  exit 1
fi

echo "===== SUSFS 4.19 补丁应用完成（$(sed -n 's/^#define SUSFS_VERSION[[:space:]]*"\(.*\)"/\1/p' include/linux/susfs.h | head -n1)） ====="

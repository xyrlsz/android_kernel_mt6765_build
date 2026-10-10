#!/usr/bin/env bash
set -euo pipefail

# 参考 android_kernel_xiaomi_sdm660 的清理逻辑：
# 先把内核树里残留的旧 KernelSU 手动 hook / 注册项抹掉，避免与 Baka-SU + SUSFS inline hook 混用。
# 新流程要求：
#   - 删除 drivers/kernelsu
#   - 删除 fs/* / security/selinux / drivers/input 中已接入的 ksu_handle_* 调用
#   - 清除 drivers/Makefile / drivers/Kconfig 里的 kernelsu 引用
# 这样 Baka-SU 集成和后续 SUSFS inline hook 才能稳定工作。

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STRIP_PATCH="$SCRIPT_DIR/patches/strip-legacy-kernelsu.patch"

echo "===== 检查是否还残留旧 KernelSU ====="
if [ ! -d drivers/kernelsu ] && ! grep -RIn --include='*.c' --include='*.h' 'ksu_' fs kernel security drivers 2>/dev/null | head -n 5 >/dev/null; then
  echo "未检测到旧 KernelSU 集成，跳过清理"
  exit 0
fi

if [ -d drivers/kernelsu ]; then
  echo "===== 移除旧 KernelSU 源码目录 ====="
  rm -rf drivers/kernelsu
fi

if [ -f "$STRIP_PATCH" ]; then
  echo "===== 移除旧 KernelSU 的 hook 与注册项 ====="
  git apply --check "$STRIP_PATCH"
  git apply "$STRIP_PATCH"
else
  echo "::error::缺少清理补丁：$STRIP_PATCH"
  exit 1
fi

echo "===== 验证清理结果 ====="
if grep -rq --include='*.c' --include='*.h' 'ksu_' fs kernel security drivers/input 2>/dev/null; then
  echo "::error::仍有 KernelSU 残留引用："
  grep -rn --include='*.c' --include='*.h' 'ksu_' fs kernel security drivers/input | head -20
  exit 1
fi
if grep -q 'kernelsu' drivers/Makefile drivers/Kconfig 2>/dev/null; then
  echo "::error::drivers/Makefile 或 drivers/Kconfig 仍引用 kernelsu"
  exit 1
fi

echo "===== 旧 KernelSU 清理完成 ====="

#!/usr/bin/env bash
set -euo pipefail

KERNEL_MAJOR=$(sed -n 's/^VERSION = //p' Makefile)
KERNEL_MINOR=$(sed -n 's/^PATCHLEVEL = //p' Makefile)
if [ "$KERNEL_MAJOR" != "4" ] || [ "$KERNEL_MINOR" != "14" ]; then
  echo "::error::此 SUSFS inline-hook 脚本仅适用于 Linux 4.14；当前版本为 ${KERNEL_MAJOR:-unknown}.${KERNEL_MINOR:-unknown}"
  exit 1
fi

INLINE_HOOK_URL="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/c308af79251ca6d7d4e6deb54a2d9f035bddf102/Patches/susfs_inline_hook_patches.sh"
EXPECTED_SHA256="9afa89ee6474b80e2615096b926c1d8eef1cb7585f74130a375fbe6cf63d00f2"
HOOK_SCRIPT=$(mktemp)
trap 'rm -f "$HOOK_SCRIPT"' EXIT

echo "===== 下载并校验 SUSFS inline-hook 脚本 ====="
curl -fL --retry 3 --retry-delay 5 -o "$HOOK_SCRIPT" "$INLINE_HOOK_URL"
echo "$EXPECTED_SHA256  $HOOK_SCRIPT" | sha256sum --check --status || {
  echo "::error::SUSFS inline-hook 脚本 SHA-256 校验失败"
  exit 1
}

echo "===== 检查 KernelSU inline-hook 集成前置条件 ====="
if ! grep -rq --include='*.c' --include='*.h' 'ksu_handle_setresuid' drivers/kernelsu/; then
  echo "::error::Baka-SU 源码中未找到 ksu_handle_setresuid；无法应用 SUSFS inline hooks"
  exit 1
fi

for source in \
  fs/exec.c \
  fs/open.c \
  fs/read_write.c \
  fs/stat.c \
  drivers/input/input.c \
  kernel/reboot.c \
  kernel/sys.c; do
  if grep -q 'CONFIG_KSU_MANUAL_HOOK' "$source"; then
    echo "::error::检测到 $source 已有 manual-hook 代码，不能与 SUSFS inline hooks 混用"
    exit 1
  fi
done

echo "===== 应用 SUSFS inline hooks ====="
bash "$HOOK_SCRIPT"

echo "===== 验证 inline-hook 注入结果 ====="
for check in \
  'fs/exec.c:ksu_handle_execveat_sucompat' \
  'fs/open.c:ksu_handle_faccessat' \
  'fs/read_write.c:ksu_handle_sys_read' \
  'fs/stat.c:ksu_handle_stat' \
  'drivers/input/input.c:ksu_handle_input_handle_event' \
  'kernel/reboot.c:ksu_handle_sys_reboot' \
  'kernel/sys.c:ksu_handle_setresuid'; do
  source=${check%%:*}
  hook=${check#*:}
  if ! grep -Fq "$hook" "$source"; then
    echo "::error::SUSFS inline hook 未能注入 $hook（$source）"
    exit 1
  fi
done

echo "===== SUSFS inline hooks 应用完成 ====="

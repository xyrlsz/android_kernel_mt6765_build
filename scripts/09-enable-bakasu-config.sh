#!/usr/bin/env bash
set -euo pipefail

export PATH="/home/runner/zyc-clang/bin:/tmp/gcc64/bin:/tmp/gcc32/bin:$PATH"

CFG="out/.config"

echo "===== 启用 Baka-SU + SUSFS inline-hook 配置 ====="
./scripts/config --file "$CFG" \
  -e KSU \
  -e THREAD_INFO_IN_TASK \
  -e KSU_SUSFS \
  -d KSU_MANUAL_HOOK \
  -d KSU_TRACEPOINT_HOOK

# Inline hooks use SUSFS hooks, not Kprobes or Baka-SU's manual-hook mode.
./scripts/config --file "$CFG" -d KPROBES
./scripts/config --file "$CFG" \
  -d KSU_MANUAL_HOOK_AUTO_INPUT_HOOK \
  -d KSU_MANUAL_HOOK_AUTO_SETUID_HOOK \
  -d KSU_MANUAL_HOOK_AUTO_INITRC_HOOK

# 处理依赖
make O=out ARCH=arm64 SUBARCH=arm64 \
  CC="ccache clang" \
  HOSTCC="ccache clang" \
  KCFLAGS="-gdwarf-4" \
  olddefconfig

echo ""
echo "===== Baka-SU + SUSFS inline-hook 配置检查 ====="
grep -E "CONFIG_(KSU|THREAD_INFO_IN_TASK|KPROBES)" out/.config || true

if ! grep -q '^CONFIG_KSU_SUSFS=y$' out/.config; then
  echo "::error::CONFIG_KSU_SUSFS 未启用；请确认所选 Baka-SU 版本包含 SUSFS 支持及其依赖满足"
  exit 1
fi

if grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' out/.config ||
  grep -q '^CONFIG_KSU_TRACEPOINT_HOOK=y$' out/.config; then
  echo "::error::SUSFS inline-hook 模式不能与 manual-hook 或 tracepoint-hook 模式同时启用"
  exit 1
fi

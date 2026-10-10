#!/usr/bin/env bash
set -euo pipefail

AK="/tmp/AnyKernel3"

if [ ! -f out/arch/arm64/boot/Image.gz ]; then
  echo "::error::Image.gz 未生成"
  ls -la out/arch/arm64/boot/
  exit 1
fi
cp out/arch/arm64/boot/Image.gz "$AK/Image.gz"

if [ -f out/arch/arm64/boot/dtb ]; then
  cp out/arch/arm64/boot/dtb "$AK/dtb"
elif [ -f out/arch/arm64/boot/dtb.img ]; then
  cp out/arch/arm64/boot/dtb.img "$AK/dtb"
fi

# do.systemless=0 时，AnyKernel3 按 .ko 在 modules/ 里的相对路径决定写入位置：
# modules/vendor/lib/modules/x.ko -> /vendor/lib/modules/x.ko（并按 vendor 目录打 SELinux 标签）。
# 本机型 ROM 的内核模块就在 vendor 分区（LineageOS kernel.mk 默认装到 /vendor/lib/modules）。
MODDIR="$AK/modules/vendor/lib/modules"
rm -rf "$AK/modules"
mkdir -p "$MODDIR"
find out -name '*.ko' -exec cp -v {} "$MODDIR/" \;
echo "模块数量: $(find "$AK/modules" -name '*.ko' | wc -l)"

echo "===== AnyKernel3 内容 ====="
ls -lh "$AK/Image.gz"
if [ -f "$AK/dtb" ]; then
  ls -lh "$AK/dtb"
else
  echo "未带 dtb（沿用原 boot）"
fi

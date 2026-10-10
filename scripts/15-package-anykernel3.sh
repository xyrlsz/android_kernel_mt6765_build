#!/usr/bin/env bash
set -euo pipefail

cd /tmp/AnyKernel3

ZIP="$GITHUB_WORKSPACE/boot-dandelion-kernel-anykernel-${GITHUB_RUN_NUMBER}.zip"
rm -f "$ZIP"

zip -r9 "$ZIP" . -x ".git/*" "README.md" "*.zip"

ls -lh "$ZIP"

LIST=$(unzip -l "$ZIP")
echo "$LIST" | grep -q 'Image.gz' || { echo "::error::zip 中缺少 Image.gz"; exit 1; }
echo "$LIST" | grep -q '^ *[0-9]* .*anykernel.sh$' || { echo "::error::zip 中缺少 anykernel.sh"; exit 1; }

echo "===== zip 内容 ====="
echo "$LIST" | head -80 || true

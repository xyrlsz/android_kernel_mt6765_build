#!/usr/bin/env bash
set -euo pipefail

rm -rf /tmp/AnyKernel3
git clone --depth=1 https://github.com/osm0sis/AnyKernel3.git /tmp/AnyKernel3

cd /tmp/AnyKernel3

rm -f zImage Image.gz Image.lz4 Image.gz-dtb dtb dtbo.img 2>/dev/null || true

sed -i 's/^kernel.string=.*/kernel.string=Jujutsu Kernel for Redmi 9A (dandelion, MT6765) by GitHub Actions/' anykernel.sh
sed -i 's/^do.devicecheck=.*/do.devicecheck=1/' anykernel.sh
sed -i 's/^do.modules=.*/do.modules=1/' anykernel.sh
sed -i 's/^do.systemless=.*/do.systemless=0/' anykernel.sh
sed -i 's/^do.cleanup=.*/do.cleanup=1/' anykernel.sh
sed -i 's/^do.cleanuponabort=.*/do.cleanuponabort=0/' anykernel.sh
sed -i 's/^device.name1=.*/device.name1=blossom/' anykernel.sh
sed -i 's/^device.name2=.*/device.name2=dandelion/' anykernel.sh
sed -i 's/^device.name3=.*/device.name3=angelica/' anykernel.sh
sed -i 's/^device.name4=.*/device.name4=angelican/' anykernel.sh
sed -i 's/^device.name5=.*/device.name5=cattail/' anykernel.sh
sed -i 's/^device.name6=.*/device.name6=angelicain/' anykernel.sh
sed -i 's|^BLOCK=.*|BLOCK=boot;|' anykernel.sh
sed -i 's/^IS_SLOT_DEVICE=.*/IS_SLOT_DEVICE=auto;/' anykernel.sh
sed -i 's/^RAMDISK_COMPRESSION=.*/RAMDISK_COMPRESSION=auto;/' anykernel.sh

echo "===== anykernel.sh 关键项 ====="
grep -E 'kernel.string|do.devicecheck|do.modules|device.name1|device.name2|^BLOCK=|^IS_SLOT_DEVICE=|^RAMDISK_COMPRESSION=' anykernel.sh

for key in 'BLOCK=boot;' 'IS_SLOT_DEVICE=auto;' 'RAMDISK_COMPRESSION=auto;' \
           'device.name1=blossom' 'device.name2=dandelion' 'do.modules=1' 'do.devicecheck=1'; do
  grep -qF "$key" anykernel.sh || { echo "::error::anykernel.sh 未正确设置（$key）"; exit 1; }
done

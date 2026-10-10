#!/usr/bin/env bash
set -euo pipefail

find arch/arm64/boot/dts -name Makefile -print0 \
  | xargs -0 -I{} sed -i 's/^dtbo-/dtbo-DISABLED-/g' {} || true

grep -rn "^dtbo-DISABLED-" arch/arm64/boot/dts/lge/Makefile | head -3 || true

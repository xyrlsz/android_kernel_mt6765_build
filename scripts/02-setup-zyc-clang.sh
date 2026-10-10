#!/usr/bin/env bash
set -euo pipefail

mkdir -p /home/runner/zyc-clang
cd /home/runner/zyc-clang

wget -q \
  "https://github.com/ZyCromerZ/Clang/releases/download/${ZYC_CLANG_VERSION}-release/Clang-${ZYC_CLANG_VERSION}.tar.gz" \
  -O zyc-clang.tar.gz

tar -zxf zyc-clang.tar.gz
rm zyc-clang.tar.gz

/home/runner/zyc-clang/bin/clang --version

echo "/home/runner/zyc-clang/bin" >> "$GITHUB_PATH"

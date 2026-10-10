#!/usr/bin/env bash
set -euo pipefail

# 修复内核源码自带的编译错误（与本仓库的 KernelSU / SUSFS 集成无关）。
#
# 内核源（plmzaq2112/android_kernel_mt6765 @ main）里 MTK 的 CONFIG_PROC_STRIPPED 定制
# 把 ipc/msg.c 的 msg_init()、ipc/sem.c 的 sem_init() 从返回 int 改成了 void，
# 但提前返回的语句没有一起改，导致内核无法编译：
#   ../ipc/msg.c:1296:10: error: use of undeclared identifier 'err'
#   ../ipc/sem.c:247:10: error: void function 'sem_init' should not return a value
# 这两个文件不在 KernelSU / SUSFS 的改动范围内，属于源码自身的问题。
#
# 只改「void 函数里 CONFIG_PROC_STRIPPED 的提前返回带了返回值」这一种情况：
# 其它使用 CONFIG_PROC_STRIPPED 的地方（返回 int 的函数里的 return 0; 等）保持原样。

echo "===== 修复内核源码自带的编译错误 ====="

mapfile -t CANDIDATES < <(grep -rl 'IS_ENABLED(CONFIG_PROC_STRIPPED)' --include='*.c' --include='*.h' . || true)
echo "  扫描到 ${#CANDIDATES[@]} 个使用 CONFIG_PROC_STRIPPED 的源文件"

python3 - "${CANDIDATES[@]}" <<'PY'
import re
import sys

GUARD = re.compile(r'^[ \t]*if \(IS_ENABLED\(CONFIG_PROC_STRIPPED\)\)[ \t]*$')
VALUE_RETURN = re.compile(r'^([ \t]*)return[ \t]+[^;\r\n]+;(\r?\n?)$')
FUNC_HEADER = re.compile(r'^([A-Za-z_][A-Za-z0-9_ \t\*]*?)\b([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*\)[ \t]*\{?[ \t]*$')


def enclosing_return_type(lines, index):
    """往上找离 index 最近的、顶格写的函数头，返回它的返回类型文本。"""
    for k in range(index - 1, -1, -1):
        line = lines[k].rstrip('\r\n')
        if not line or line[0] in ' \t' or line.startswith('#'):
            continue
        match = FUNC_HEADER.match(line)
        if match:
            return match.group(1)
    return None


def returns_void(type_text):
    if type_text is None:
        return False
    tokens = type_text.split()
    return bool(tokens) and 'void' in tokens and not type_text.rstrip().endswith('*')


fixed = 0
skipped = []
remaining = []
for path in sys.argv[1:]:
    with open(path, encoding='latin-1', newline='') as fh:
        lines = fh.readlines()

    changed = False
    for i, line in enumerate(lines):
        if not GUARD.match(line.rstrip('\r\n')):
            continue
        if i + 1 >= len(lines):
            continue
        ret = VALUE_RETURN.match(lines[i + 1])
        if not ret:
            continue
        if not returns_void(enclosing_return_type(lines, i)):
            skipped.append('%s:%d' % (path, i + 2))
            continue
        lines[i + 1] = '%sreturn;%s' % (ret.group(1), ret.group(2))
        changed = True
        fixed += 1

    if changed:
        with open(path, 'w', encoding='latin-1', newline='') as fh:
            fh.writelines(lines)

    for i, line in enumerate(lines):
        if GUARD.match(line.rstrip('\r\n')) and i + 1 < len(lines) and VALUE_RETURN.match(lines[i + 1]):
            if returns_void(enclosing_return_type(lines, i)):
                remaining.append('%s:%d' % (path, i + 2))

if skipped:
    print('  跳过（所在函数不是 void，保持原样）: %s' % ', '.join(skipped))
print('  共修复 %d 处' % fixed)
if remaining:
    print('::error::以下位置仍是 void 函数返回带值的 return: %s' % ', '.join(remaining))
    sys.exit(1)
PY

echo "===== 内核源码编译错误修复完成 ====="

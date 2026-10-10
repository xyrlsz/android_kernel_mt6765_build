#!/usr/bin/env bash
set -euo pipefail

# 内核源（plmzaq2112/android_kernel_mt6765）自带另一套 KernelSU / SUSFS 集成，必须先整块移除：
#   - 旧 KernelSU hook：CONFIG_KSU / CONFIG_KSU_MANUAL_HOOK 守卫的 ksu_handle_* 调用
#   - 旧 SUSFS（v2.1.0）内核侧代码：CONFIG_KSU_SUSFS* 守卫的代码块 + fs/susfs.c 等文件
# 不移除的后果：
#   - 08-apply-susfs-4.19-patch.sh 的 SUSFS v2.3.0 补丁无法应用（旧 SUSFS 已占用同一批文件）
#   - 08-apply-susfs-inline-hooks.sh 的前置检查失败，且旧 hook 与 inline hook 签名/守卫不一致
# 移除方式：按预处理块整块删除（支持嵌套、支持 #if/#else 分支），只删除 KernelSU/SUSFS 的那一支，
# 保留另一支的代码并解开 #if/#else 指令，同时回收删除点多余空行。

HOOK_FILES=(
  fs/exec.c
  fs/open.c
  fs/read_write.c
  fs/stat.c
  fs/namei.c
  drivers/input/input.c
  security/security.c
  security/selinux/hooks.c
  security/selinux/ss/services.c
  kernel/reboot.c
  kernel/sys.c
)

echo "===== 移除内核树中遗留的 KernelSU / SUSFS 集成 ====="
python3 - <<'PY'
import os
import re

IF_RE = re.compile(r"^[ \t]*#[ \t]*(if|ifdef|ifndef)\b(.*)$")
ELSIF_RE = re.compile(r"^[ \t]*#[ \t]*elif\b(.*)$")
ELSE_RE = re.compile(r"^[ \t]*#[ \t]*else\b")
ENDIF_RE = re.compile(r"^[ \t]*#[ \t]*endif\b")

HOOK_MARKER_RE = re.compile(r"ksu_|susfs_|SUSFS_")

SUSFS_FILES = (
    "fs/susfs.c",
    "include/linux/susfs.h",
    "include/linux/susfs_def.h",
)

SKIP_DIRS = {".git", "out", "KernelSU", "kernelsu"}
KSU_SUSFS_MARK = ("CONFIG_KSU_SUSFS", "susfs.o")


def condition_kind(cond_text):
    """返回 (是否与 KernelSU 相关, 是否为否定形式)。"""
    if "CONFIG_KSU" not in cond_text:
        return (False, False)
    match = IF_RE.match(cond_text)
    kind = match.group(1) if match else "if"
    arg = match.group(2).strip() if match else ""
    negated = kind == "ifndef" or arg.startswith("!")
    return (True, negated)


def find_block(lines, start):
    """返回从 start 开始的预处理块的 (分支类型, 指令行号) 列表。"""
    depth = 0
    segments = []
    index = start
    while index < len(lines):
        line = lines[index]
        if IF_RE.match(line):
            depth += 1
            if depth == 1:
                segments.append(("if", index))
        elif ELSIF_RE.match(line) and depth == 1:
            segments.append(("elif", index))
        elif ELSE_RE.match(line) and depth == 1:
            segments.append(("else", index))
        elif ENDIF_RE.match(line):
            depth -= 1
            if depth == 0:
                segments.append(("endif", index))
                return segments
        index += 1
    return segments


def mark(lines, start, end, dropped):
    index = start
    while index <= end:
        line = lines[index]
        if not IF_RE.match(line):
            index += 1
            continue

        segments = find_block(lines, index)
        if not segments:
            index += 1
            continue
        block_end = segments[-1][1]
        span_text = "".join(lines[index:block_end + 1])
        mentions_ksu, negated = condition_kind(line)

        removable = False
        if "CONFIG_KSU_SUSFS" in line:
            removable = True
        elif mentions_ksu and HOOK_MARKER_RE.search(span_text):
            removable = True

        if not removable:
            # 非 KernelSU/SUSFS 块：继续向内查找
            mark(lines, index + 1, block_end - 1, dropped)
            index = block_end + 1
            continue

        branch_segments = [seg for seg in segments if seg[0] != "endif"]
        endif_index = segments[-1][1]
        bounds = []
        for pos, (kind, seg_index) in enumerate(branch_segments):
            branch_start = seg_index + 1
            if pos + 1 < len(branch_segments):
                branch_end = branch_segments[pos + 1][1] - 1
            else:
                branch_end = endif_index - 1
            bounds.append((kind, seg_index, branch_start, branch_end))

        for pos, (kind, seg_index, branch_start, branch_end) in enumerate(bounds):
            if kind == "if":
                drop = not negated
            elif kind == "else" and len(bounds) == 2:
                drop = negated
            else:
                drop = True
            if drop:
                dropped.update(range(branch_start, branch_end + 1))
                dropped.add(seg_index)
            else:
                dropped.add(seg_index)
                mark(lines, branch_start, branch_end, dropped)

        dropped.add(endif_index)
        index = block_end + 1


def rewrite(path, lines, dropped, root):
    kept = []
    previous_input_dropped = False
    for idx, line in enumerate(lines):
        if idx in dropped:
            previous_input_dropped = True
            continue
        # 删除点相邻处容易出现连续空行，合并为一个
        if line.strip() == "" and kept and kept[-1].strip() == "" and previous_input_dropped:
            previous_input_dropped = False
            continue
        kept.append(line)
        previous_input_dropped = False

    with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as handle:
        handle.writelines(kept)
    print("[strip] %s: -%d 行" % (os.path.relpath(path, root).replace(os.sep, "/"), len(dropped)))
    return len(dropped)


def strip_file(path, root):
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as handle:
        lines = handle.readlines()
    dropped = set()
    mark(lines, 0, len(lines) - 1, dropped)
    if not dropped:
        return 0
    return rewrite(path, lines, dropped, root)


def strip_kbuild(path, root):
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as handle:
        lines = handle.readlines()
    dropped = set(i for i, ln in enumerate(lines) if any(m in ln for m in KSU_SUSFS_MARK))
    if not dropped:
        return 0
    return rewrite(path, lines, dropped, root)


def main(root):
    total = 0
    for rel in SUSFS_FILES:
        target = os.path.join(root, rel)
        if os.path.isfile(target) or os.path.islink(target):
            os.remove(target)
            print("[strip] 删除旧 SUSFS 文件: %s" % rel)

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if not name.endswith((".c", ".h", ".S")):
                continue
            path = os.path.join(dirpath, name)
            if os.path.relpath(path, root).replace(os.sep, "/") in SUSFS_FILES:
                continue
            total += strip_file(path, root)

    for rel in ("fs/Makefile", "drivers/Makefile", "security/Makefile",
                "mm/Makefile", "kernel/Makefile", "include/linux/Makefile"):
        path = os.path.join(root, rel)
        if os.path.isfile(path):
            total += strip_kbuild(path, root)

    print("[strip] 共删除 %d 行" % total)


main(os.getcwd())
PY

echo "===== 验证清理结果 ====="
failed=0

for f in "${HOOK_FILES[@]}"; do
  [ -f "$f" ] || continue
  if grep -qE 'ksu_handle|ksu_sid|CONFIG_KSU_MANUAL_HOOK' "$f"; then
    echo "::error::$f 仍残留旧 KernelSU hook 代码"
    grep -nE 'ksu_handle|ksu_sid|CONFIG_KSU_MANUAL_HOOK' "$f" | head -5
    failed=1
  fi
done

leftovers=$(grep -rlE 'CONFIG_KSU_SUSFS|susfs_' \
  --include='*.c' --include='*.h' --include='*.S' \
  fs kernel security mm include drivers 2>/dev/null || true)
if [ -n "$leftovers" ]; then
  echo "::error::内核树中仍有旧 SUSFS 残留引用："
  echo "$leftovers" | head -20
  failed=1
fi

for stale in fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h; do
  if [ -e "$stale" ]; then
    echo "::error::$stale 未被移除"
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "===== 旧 KernelSU / SUSFS 清理完成 ====="

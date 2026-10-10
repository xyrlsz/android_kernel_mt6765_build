#!/usr/bin/env bash
set -euo pipefail

# 内核源（plmzaq2112/android_kernel_mt6765）自带另一套 KernelSU / SUSFS 集成，必须整块移除：
#   - 旧 KernelSU hook：CONFIG_KSU / CONFIG_KSU_MANUAL_HOOK 守卫的 ksu_handle_* 调用
#   - 旧 SUSFS（v2.1.0）内核侧代码：CONFIG_KSU_SUSFS* 守卫的代码块 + fs/susfs.c 等文件
# 不移除的后果：
#   - 08-apply-susfs-inline-hooks.sh 的前置检查会直接失败（fs/stat.c 已有 manual-hook 代码）
#   - 08-apply-susfs-4.19-patch.sh 的 SUSFS v2.3.0 补丁无法应用（旧 SUSFS 已占用同一批文件）
#   - 旧 hook 的守卫/签名与 SUSFS inline hook（CONFIG_KSU_SUSFS）不一致，混用会编译失败
# 移除方式：按预处理块（#if/#ifdef/#elif/#else/#endif，支持嵌套）整块删除，
# 并回收删除点两侧多余的空行，使源码尽量回到补丁所需的干净基线。

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
ELSIF_RE = re.compile(r"^[ \t]*#[ \t]*(elif|else)\b(.*)$")
ENDIF_RE = re.compile(r"^[ \t]*#[ \t]*endif\b")

# 旧 KernelSU hook 的识别特征
KSU_HOOK_RE = re.compile(
    r"ksu_("
    r"handle|cred|sid|execveat|init_rc_hook|input_hook|vfs_read_hook|"
    r"selinux_hide|install_su_fd|is_init_rc_hook_enabled|is_input_hook_enabled|"
    r"is_allow_uid_for_current"
    r")"
)

SUSFS_FILES = (
    "fs/susfs.c",
    "include/linux/susfs.h",
    "include/linux/susfs_def.h",
)

SKIP_DIRS = {".git", "out", "KernelSU", "kernelsu"}
KSU_SUSFS_MARK = ("CONFIG_KSU_SUSFS", "susfs.o")


def collect_blocks(lines):
    """返回所有 #if 块：(起始行, 结束行, 条件文本, 块内文本)。"""
    stack = []
    blocks = []
    for idx, line in enumerate(lines):
        if IF_RE.match(line):
            stack.append({"start": idx, "conds": [line]})
            continue
        if ELSIF_RE.match(line) and stack:
            stack[-1]["conds"].append(line)
            continue
        if ENDIF_RE.match(line) and stack:
            frame = stack.pop()
            blocks.append((
                frame["start"],
                idx,
                "\n".join(frame["conds"]),
                "\n".join(lines[frame["start"]:idx + 1]),
            ))
    return blocks


def is_blank(line):
    return line.strip() == ""


def strip_file(path, root):
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
        lines = fh.readlines()

    removed = set()
    for start, end, conds, span in collect_blocks(lines):
        if "CONFIG_KSU_SUSFS" in conds:
            removable = True
        elif "CONFIG_KSU" in conds and KSU_HOOK_RE.search(span):
            removable = True
        else:
            removable = False
        if not removable:
            continue
        removed.update(range(start, end + 1))
        # 补丁插入形式为 <空行> + 代码块 + <空行>；删掉代码块后需回收一侧空行
        if start > 0 and end + 1 < len(lines) and \
                is_blank(lines[start - 1]) and is_blank(lines[end + 1]):
            removed.add(end + 1)

    if not removed:
        return 0

    kept = []
    for idx, line in enumerate(lines):
        if idx in removed:
            continue
        # 删除点相邻处可能出现连续空行，合并为一个
        if is_blank(line) and kept and is_blank(kept[-1]) and (idx - 1) in removed:
            continue
        kept.append(line)

    with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.writelines(kept)
    print("[strip] %s: -%d 行" % (os.path.relpath(path, root).replace(os.sep, "/"), len(removed)))
    return len(removed)


def strip_kbuild(path, root):
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
        lines = fh.readlines()

    removed = [i for i, ln in enumerate(lines) if any(m in ln for m in KSU_SUSFS_MARK)]
    if not removed:
        return 0

    kept = []
    for idx, line in enumerate(lines):
        if idx in removed:
            continue
        if is_blank(line) and kept and is_blank(kept[-1]) and (idx - 1) in removed:
            continue
        kept.append(line)

    with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.writelines(kept)
    print("[strip] %s: -%d 行" % (os.path.relpath(path, root).replace(os.sep, "/"), len(removed)))
    return len(removed)


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

    print("[strip] 共删除 %d 行受守卫保护的代码" % total)


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

if [ -e include/linux/susfs.h ]; then
  echo "::error::include/linux/susfs.h 未被移除"
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "===== 旧 KernelSU / SUSFS 清理完成 ====="

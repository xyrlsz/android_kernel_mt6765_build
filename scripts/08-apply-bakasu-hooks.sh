#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "===== 应用 Baka-SU 手动钩子 ====="
echo "=========================================="

# ---------- 1. stat hook (fs/stat.c) ----------
echo "----- [1/7] 应用 stat hook (fs/stat.c) -----"

sed -i '/^#if !defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_SYS_NEWFSTATAT)$/i \
#ifdef CONFIG_KSU_MANUAL_HOOK\
__attribute__((hot))\
extern int ksu_handle_stat(int *dfd, const char __user **filename_user,\
				int *flags);\
\
extern void ksu_handle_newfstat_ret(unsigned int *fd, struct stat __user **statbuf_ptr);\
#if defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_COMPAT_STAT64)\
extern void ksu_handle_fstat64_ret(unsigned long *fd, struct stat64 __user **statbuf_ptr);\
#endif\
#endif' fs/stat.c

sed -i '/^SYSCALL_DEFINE4(newfstatat,/,/^\terror = vfs_fstatat(dfd, filename, &stat, flag);$/{
  /^\terror = vfs_fstatat(dfd, filename, &stat, flag);$/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	ksu_handle_stat(\&dfd, \&filename, \&flag);\
#endif
}' fs/stat.c

sed -i '/^SYSCALL_DEFINE4(fstatat64,/,/^\terror = vfs_fstatat(dfd, filename, &stat, flag);$/{
  /^\terror = vfs_fstatat(dfd, filename, &stat, flag);$/i\
#ifdef CONFIG_KSU_MANUAL_HOOK // 32-bit su\
	ksu_handle_stat(\&dfd, \&filename, \&flag);\
#endif
}' fs/stat.c

sed -i '/^SYSCALL_DEFINE2(newfstat,/,/^}/{
  /return error;/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	ksu_handle_newfstat_ret(\&fd, \&statbuf);\
#endif
}' fs/stat.c

sed -i '/^SYSCALL_DEFINE2(fstat64,/,/^}/{
  /return error;/i\
#ifdef CONFIG_KSU_MANUAL_HOOK // for 32-bit\
	ksu_handle_fstat64_ret(\&fd, \&statbuf);\
#endif
}' fs/stat.c

echo "✓ stat hook 已应用"

# ---------- 2. execve hook (fs/exec.c) — 4.14 使用 do_execveat_common ----------
echo "----- [2/7] 应用 execve hook (fs/exec.c) -----"

sed -i '/^static int do_execveat_common(/i \
#ifdef CONFIG_KSU_MANUAL_HOOK\
__attribute__((hot))\
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\
				void *argv, void *envp, int *flags);\
__attribute__((hot))\
extern int ksu_handle_post_execveat(int *fd, struct filename **filename_ptr,\
				void *argv, void *envp, int *flags, int *retval);\
#endif' fs/exec.c

sed -i '/^static int do_execveat_common(/,/^\tif (IS_ERR(filename))$/{
  /^\tif (IS_ERR(filename))$/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	ksu_handle_execveat(\&fd, \&filename, \&argv, \&envp, \&flags);\
#endif
}' fs/exec.c

# 成功后取返回值与失败后（out_ret）各调用一次 post hook，
# 且都位于 putname() 之前，避免访问已被释放的 filename
sed -i '/execve succeeded/,/^\tputname(filename);$/{
  /^\tputname(filename);$/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	ksu_handle_post_execveat(\&fd, \&filename, \&argv, \&envp, \&flags, \&retval);\
#endif
}' fs/exec.c

sed -i '/^out_ret:/a\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	ksu_handle_post_execveat(\&fd, \&filename, \&argv, \&envp, \&flags, \&retval);\
#endif' fs/exec.c

echo "✓ execve hook 已应用"

# ---------- 3. faccessat hook (fs/open.c) ----------
echo "----- [3/7] 应用 faccessat hook (fs/open.c) -----"

sed -i '/^SYSCALL_DEFINE3(faccessat,/i \
#ifdef CONFIG_KSU_MANUAL_HOOK\
__attribute__((hot))\
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\
				int *mode, int *flags);\
#endif' fs/open.c

sed -i '/^SYSCALL_DEFINE3(faccessat,/,/^\tif (mode & ~S_IRWXO)/{
  /^\tif (mode & ~S_IRWXO)/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	ksu_handle_faccessat(\&dfd, \&filename, \&mode, NULL);\
#endif
}' fs/open.c

echo "✓ faccessat hook 已应用"

# ---------- 4. sys_reboot hook (kernel/reboot.c) ----------
echo "----- [4/7] 应用 sys_reboot hook (kernel/reboot.c) -----"

sed -i '/^SYSCALL_DEFINE4(reboot,/i \
#ifdef CONFIG_KSU_MANUAL_HOOK\
extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\
#endif' kernel/reboot.c

sed -i '/^SYSCALL_DEFINE4(reboot,/,/We only trust the superuser/{
  /We only trust the superuser/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	ksu_handle_sys_reboot(magic1, magic2, cmd, \&arg);\
#endif
}' kernel/reboot.c

echo "✓ sys_reboot hook 已应用"

# ---------- 5. input hook (drivers/input/input.c) ----------
echo "----- [5/7] 应用 input hook (drivers/input/input.c) -----"

sed -i '/^void input_event(struct input_dev \*dev,/i \
#ifdef CONFIG_KSU_MANUAL_HOOK\
extern bool ksu_input_hook __read_mostly;\
extern __attribute__((cold)) int ksu_handle_input_handle_event(\
			unsigned int *type, unsigned int *code, int *value);\
#endif' drivers/input/input.c

sed -i '/^void input_event(struct input_dev \*dev,/,/^\tif (is_event_supported(type, dev->evbit, EV_MAX)) {$/{
  /^\tif (is_event_supported(type, dev->evbit, EV_MAX)) {$/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	if (unlikely(ksu_input_hook))\
		ksu_handle_input_handle_event(\&type, \&code, \&value);\
#endif
}' drivers/input/input.c

echo "✓ input hook 已应用"

# ---------- 6. setuid hook (kernel/sys.c) ----------
echo "----- [6/7] 应用 setuid hook (kernel/sys.c) -----"

sed -i '/^SYSCALL_DEFINE3(setresuid,/i \
#ifdef CONFIG_KSU_MANUAL_HOOK\
extern int ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid);\
#endif' kernel/sys.c

sed -i '/^SYSCALL_DEFINE3(setresuid,/,/^\tkruid = make_kuid(ns, ruid);$/{
  /^\tkruid = make_kuid(ns, ruid);$/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	(void)ksu_handle_setresuid(ruid, euid, suid);\
#endif
}' kernel/sys.c

echo "✓ setuid hook 已应用"

# ---------- 7. sys_read hook (fs/read_write.c) ----------
echo "----- [7/7] 应用 sys_read hook (fs/read_write.c) -----"

sed -i '/^SYSCALL_DEFINE3(read,/i \
#ifdef CONFIG_KSU_MANUAL_HOOK\
extern bool ksu_init_rc_hook __read_mostly;\
extern __attribute__((cold)) int ksu_handle_sys_read(unsigned int fd,\
				char __user **buf_ptr, size_t *count_ptr);\
#endif' fs/read_write.c

sed -i '/^SYSCALL_DEFINE3(read, unsigned int, fd, char __user \*, buf, size_t, count)$/,/^\tif (f\.file) {$/{
  /^\tif (f\.file) {$/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	if (unlikely(ksu_init_rc_hook))\
		ksu_handle_sys_read(fd, \&buf, \&count);\
#endif
}' fs/read_write.c

echo "✓ sys_read hook 已应用"

echo ""
echo "=========================================="
echo "===== 所有手动钩子应用完成 ====="
echo "=========================================="

#!/usr/bin/env bash
set -euo pipefail

KSU_DIR="${1:-$(pwd)}"
cd "${KSU_DIR}"

python3 - <<'PY'
from pathlib import Path


def read(path):
    return Path(path).read_text()


def write(path, text):
    Path(path).write_text(text)


def replace_once(path, old, new):
    s = read(path)
    if new in s:
        return
    if old not in s:
        raise SystemExit(f"missing pattern in {path}: {old[:80]!r}")
    write(path, s.replace(old, new, 1))


def insert_after(path, anchor, text, marker=None):
    s = read(path)
    if (marker or text.strip()) in s:
        return
    if anchor not in s:
        raise SystemExit(f"missing anchor in {path}: {anchor[:80]!r}")
    write(path, s.replace(anchor, anchor + text, 1))


def insert_before(path, anchor, text, marker=None):
    s = read(path)
    if (marker or text.strip()) in s:
        return
    if anchor not in s:
        raise SystemExit(f"missing anchor in {path}: {anchor[:80]!r}")
    write(path, s.replace(anchor, text + anchor, 1))


# kernel/Kconfig
kconfig = Path("kernel/Kconfig")
s = kconfig.read_text()
if "config KSU_SUSFS" not in s:
    block = r'''
menu "KernelSU - SUSFS"

config KSU_SUSFS
	bool "KernelSU addon - SUSFS"
	depends on KSU
	depends on THREAD_INFO_IN_TASK
	default y
	help
	  Patch and enable SUSFS in the kernel with KernelSU.

config KSU_SUSFS_SUS_PATH
	bool "Enable hiding suspicious paths"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_SUS_MOUNT
	bool "Enable hiding suspicious mounts"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_SUS_KSTAT
	bool "Enable spoofing suspicious kstat"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_SPOOF_UNAME
	bool "Enable uname spoofing"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_ENABLE_LOG
	bool "Enable SUSFS kernel logging"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
	bool "Hide KernelSU and SUSFS symbols from kallsyms"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
	bool "Spoof /proc/bootconfig or /proc/cmdline"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_OPEN_REDIRECT
	bool "Enable open redirect"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_SUS_MAP
	bool "Enable hiding selected mapped files"
	depends on KSU_SUSFS
	default y

endmenu
'''
    pos = s.rfind("\nendmenu")
    if pos < 0:
        raise SystemExit("missing final endmenu in kernel/Kconfig")
    s = s[:pos] + block + s[pos:]
    kconfig.write_text(s)

# kernel/core/init.c
insert_after(
    "kernel/core/init.c",
    "#include <linux/sched.h>\n",
    "#include <linux/susfs.h>\n",
    "<linux/susfs.h>",
)
insert_after(
    "kernel/core/init.c",
    "\tksu_syscall_hook_init();\n",
    "\n#ifdef CONFIG_KSU_SUSFS\n\tsusfs_init();\n#endif\n",
    "susfs_init();",
)

# kernel/hook/setuid_hook.c
insert_after(
    "kernel/hook/setuid_hook.c",
    "#include <linux/task_work.h>\n",
    "#include <linux/susfs_def.h>\n#include <linux/workqueue.h>\n",
    "<linux/susfs_def.h>",
)
insert_after(
    "kernel/hook/setuid_hook.c",
    "#include <linux/uidgid.h>\n",
    "\n#include \"selinux/selinux.h\"\n",
    '"selinux/selinux.h"',
)
insert_after(
    "kernel/hook/setuid_hook.c",
    "#include \"feature/kernel_umount.h\"\n",
    r'''
#ifdef CONFIG_KSU_SUSFS
extern struct work_struct susfs_extra_works;

static inline void ksu_handle_extra_susfs_work(void)
{
	if (!work_pending(&susfs_extra_works))
		schedule_work(&susfs_extra_works);
}
#endif
''',
    "ksu_handle_extra_susfs_work",
)
replace_once(
    "kernel/hook/setuid_hook.c",
    "int ksu_handle_setresuid(uid_t old_uid, uid_t new_uid)\n{\n",
    "int ksu_handle_setresuid(uid_t old_uid, uid_t new_uid, uid_t suid)\n{\n\t(void)suid;\n",
)
insert_after(
    "kernel/hook/setuid_hook.c",
    "\tksu_handle_umount(old_uid, new_uid);\n",
    r'''

#ifdef CONFIG_KSU_SUSFS
	if (new_uid != WEBVIEW_ZYGOTE_UID && is_zygote(current_cred()) &&
	    (is_isolated_process(new_uid) ||
	     (is_appuid(new_uid) && ksu_uid_should_umount(new_uid)))) {
		ksu_handle_extra_susfs_work();
		susfs_set_current_proc_umounted();
	}
#endif
''',
    "susfs_set_current_proc_umounted",
)

# kernel/hook/setuid_hook.h
replace_once(
    "kernel/hook/setuid_hook.h",
    "int ksu_handle_setresuid(uid_t old_uid, uid_t new_uid);",
    "int ksu_handle_setresuid(uid_t old_uid, uid_t new_uid, uid_t suid);",
)

# kernel/hook/syscall_event_bridge.c
replace_once(
    "kernel/hook/syscall_event_bridge.c",
    "\tksu_handle_setresuid(old_uid, current_uid().val);",
    "\tksu_handle_setresuid(old_uid, current_uid().val, current_suid().val);",
)

# kernel/selinux/selinux.c
insert_after(
    "kernel/selinux/selinux.c",
    "u32 ksu_file_sid __read_mostly = 0;\n",
    "\nu32 susfs_ksu_sid __read_mostly = 0;\nu32 susfs_init_sid __read_mostly = 0;\nu32 susfs_zygote_sid __read_mostly = 0;\nu32 susfs_priv_app_sid __read_mostly = 0;\n",
    "susfs_ksu_sid",
)
insert_after(
    "kernel/selinux/selinux.c",
    "\t} else {\n\t\tpr_info(\"Cached ksu_file SID: %u\\n\", ksu_file_sid);\n\t}\n",
    r'''

	susfs_ksu_sid = cached_su_sid;
	susfs_init_sid = cached_init_sid;
	susfs_zygote_sid = cached_zygote_sid;

	err = security_secctx_to_secid("u:r:priv_app:s0:c512,c768",
					       strlen("u:r:priv_app:s0:c512,c768"),
					       &susfs_priv_app_sid);
	if (err)
		pr_warn("Failed to cache susfs priv_app SID: %d\n", err);
	else
		pr_info("Cached susfs priv_app SID: %u\n", susfs_priv_app_sid);
''',
    "Cached susfs priv_app SID",
)
insert_after(
    "kernel/selinux/selinux.c",
    "\tcommit_creds(cred);\n}\n",
    r'''

bool susfs_is_sid_equal(const struct cred *cred, u32 sid2)
{
	return is_sid_match(cred, sid2, "");
}

u32 susfs_get_current_sid(void)
{
	return current_sid();
}

bool susfs_is_current_zygote_domain(void)
{
	return current_sid() == susfs_zygote_sid;
}

bool susfs_is_current_ksu_domain(void)
{
	return is_ksu_domain();
}
''',
    "susfs_is_current_ksu_domain",
)

# kernel/selinux/selinux.h
insert_before(
    "kernel/selinux/selinux.h",
    "#endif\n",
    r'''
extern u32 susfs_ksu_sid;
extern u32 susfs_init_sid;
extern u32 susfs_zygote_sid;
extern u32 susfs_priv_app_sid;

bool susfs_is_sid_equal(const struct cred *cred, u32 sid2);
u32 susfs_get_current_sid(void);
bool susfs_is_current_zygote_domain(void);
bool susfs_is_current_ksu_domain(void);

''',
    "susfs_get_current_sid",
)

# kernel/supercall/supercall.c
insert_after(
    "kernel/supercall/supercall.c",
    "#include <linux/version.h>\n",
    "#include <linux/susfs.h>\n#include <linux/susfs_def.h>\n",
    "<linux/susfs.h>",
)
insert_before(
    "kernel/supercall/supercall.c",
    "\t/* Check if this is a request to install KSU fd */\n",
    r'''
#ifdef CONFIG_KSU_SUSFS
	if (magic1 == KSU_INSTALL_MAGIC1 && magic2 == SUSFS_MAGIC && current_uid().val == 0) {
		void __user **susfs_arg = (void __user **)arg4;

		switch (cmd) {
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
		case CMD_SUSFS_ADD_SUS_PATH:
			susfs_add_sus_path(susfs_arg);
			return 0;
		case CMD_SUSFS_ADD_SUS_PATH_LOOP:
			susfs_add_sus_path_loop(susfs_arg);
			return 0;
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
		case CMD_SUSFS_HIDE_SUS_MNTS_FOR_NON_SU_PROCS:
			susfs_set_hide_sus_mnts_for_non_su_procs(susfs_arg);
			return 0;
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT
		case CMD_SUSFS_ADD_SUS_KSTAT:
		case CMD_SUSFS_ADD_SUS_KSTAT_STATICALLY:
			susfs_add_sus_kstat(susfs_arg);
			return 0;
		case CMD_SUSFS_UPDATE_SUS_KSTAT:
			susfs_update_sus_kstat(susfs_arg);
			return 0;
#endif
#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME
		case CMD_SUSFS_SET_UNAME:
			susfs_set_uname(susfs_arg);
			return 0;
#endif
#ifdef CONFIG_KSU_SUSFS_ENABLE_LOG
		case CMD_SUSFS_ENABLE_LOG:
			susfs_enable_log(susfs_arg);
			return 0;
#endif
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
		case CMD_SUSFS_SET_CMDLINE_OR_BOOTCONFIG:
			susfs_set_cmdline_or_bootconfig(susfs_arg);
			return 0;
#endif
#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT
		case CMD_SUSFS_ADD_OPEN_REDIRECT:
			susfs_add_open_redirect(susfs_arg);
			return 0;
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
		case CMD_SUSFS_ADD_SUS_MAP:
			susfs_add_sus_map(susfs_arg);
			return 0;
#endif
		case CMD_SUSFS_ENABLE_AVC_LOG_SPOOFING:
			susfs_set_avc_log_spoofing(susfs_arg);
			return 0;
		case CMD_SUSFS_SHOW_ENABLED_FEATURES:
			susfs_get_enabled_features(susfs_arg);
			return 0;
		case CMD_SUSFS_SHOW_VARIANT:
			susfs_show_variant(susfs_arg);
			return 0;
		case CMD_SUSFS_SHOW_VERSION:
			susfs_show_version(susfs_arg);
			return 0;
		default:
			return 0;
		}
	}
#endif

''',
    "CMD_SUSFS_SHOW_VERSION",
)
PY

git diff --check

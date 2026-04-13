<<<<<<< HEAD
#include <linux/uaccess.h>
#include <linux/types.h>
#include <linux/version.h>
=======
#include "linux/rcupdate.h"
#include "security.h"
#include <linux/uaccess.h>
#include <linux/types.h>
#include <linux/version.h>
#include <linux/slab.h>
#include <linux/string.h>
#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 12, 0)
#include <linux/sched/types.h>
#endif
#include <linux/stop_machine.h>
>>>>>>> 7b9651e4bd9e (drivers: Import KernelSU-Next v3.1.0 legacy susfs)

#include "../klog.h" // IWYU pragma: keep
#include "selinux.h"
#include "sepolicy.h"
#include "ss/services.h"
#include "linux/lsm_audit.h" // IWYU pragma: keep
#include "xfrm.h"
<<<<<<< HEAD
=======
#include "kernel_compat.h"
>>>>>>> 7b9651e4bd9e (drivers: Import KernelSU-Next v3.1.0 legacy susfs)

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)
#define SELINUX_POLICY_INSTEAD_SELINUX_SS
#endif

#define ALL NULL

<<<<<<< HEAD
=======
static DEFINE_MUTEX(ksu_rules);

>>>>>>> 7b9651e4bd9e (drivers: Import KernelSU-Next v3.1.0 legacy susfs)
static struct policydb *get_policydb(void)
{
    struct policydb *db;
#ifdef KSU_COMPAT_USE_SELINUX_STATE
#ifdef SELINUX_POLICY_INSTEAD_SELINUX_SS
<<<<<<< HEAD
	struct selinux_policy *policy = selinux_state.policy;
	db = &policy->policydb;
#else
	struct selinux_ss *ss = selinux_state.ss;
	db = &ss->policydb;
#endif
#else
	db = &policydb;
=======
    struct selinux_policy *policy = selinux_state.policy;
    db = &policy->policydb;
#else
    struct selinux_ss *ss = selinux_state.ss;
    db = &ss->policydb;
#endif
#else
    db = &policydb;
>>>>>>> 7b9651e4bd9e (drivers: Import KernelSU-Next v3.1.0 legacy susfs)
#endif
    return db;
}

<<<<<<< HEAD
static DEFINE_MUTEX(ksu_rules);

void apply_kernelsu_rules()
{
    struct policydb *db;

    if (!getenforce()) {
        pr_info("SELinux permissive or disabled, apply rules!\n");
    }

    mutex_lock(&ksu_rules);

    db = get_policydb();
=======
#if ((!defined(KSU_COMPAT_USE_SELINUX_STATE)) || \
	LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
extern int avc_ss_reset(u32 seqno);
#else
extern int avc_ss_reset(struct selinux_avc *avc, u32 seqno);
#endif
// reset avc cache table, otherwise the new rules will not take effect if already denied
static void reset_avc_cache()
{
#if ((!defined(KSU_COMPAT_USE_SELINUX_STATE)) || \
	LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
    avc_ss_reset(0);
    selnl_notify_policyload(0);
    selinux_status_update_policyload(0);
#else
    struct selinux_avc *avc = selinux_state.avc;
    avc_ss_reset(avc, 0);
    selnl_notify_policyload(0);
    selinux_status_update_policyload(&selinux_state, 0);
#endif
    selinux_xfrm_notify_policyload();
}

#ifndef SELINUX_POLICY_INSTEAD_SELINUX_SS

// rwlock
#if defined(KSU_COMPAT_USE_SELINUX_STATE)
static inline rwlock_t *ksu_get_policy_rwlock(void) { return &selinux_state.ss->policy_rwlock; }
#elif defined(KSU_COMPAT_HAS_EXPORTED_POLICY_RWLOCK)
static inline rwlock_t *ksu_get_policy_rwlock(void) { extern rwlock_t policy_rwlock; return &policy_rwlock; }
#else
static inline rwlock_t *ksu_get_policy_rwlock(void) { return NULL; }
#endif
#endif // #ifndef SELINUX_POLICY_INSTEAD_SELINUX_SS

static int apply_kernelsu_rules_fn(void *ptr)
{
	struct policydb *db = (struct policydb *)ptr;
>>>>>>> 7b9651e4bd9e (drivers: Import KernelSU-Next v3.1.0 legacy susfs)

    ksu_permissive(db, KERNEL_SU_DOMAIN);
    ksu_typeattribute(db, KERNEL_SU_DOMAIN, "mlstrustedsubject");
    ksu_typeattribute(db, KERNEL_SU_DOMAIN, "netdomain");
    ksu_typeattribute(db, KERNEL_SU_DOMAIN, "bluetoothdomain");

    // Create unconstrained file type
    ksu_type(db, KERNEL_SU_FILE, "file_type");
    ksu_typeattribute(db, KERNEL_SU_FILE, "mlstrustedobject");
<<<<<<< HEAD
    ksu_allow(db, ALL, KERNEL_SU_FILE, ALL, ALL);
=======
    ksu_allow(db, "domain", KERNEL_SU_FILE, ALL, ALL);
>>>>>>> 7b9651e4bd9e (drivers: Import KernelSU-Next v3.1.0 legacy susfs)

    // allow all!
    ksu_allow(db, KERNEL_SU_DOMAIN, ALL, ALL, ALL);

    // allow us do any ioctl
    if (db->policyvers >= POLICYDB_VERSION_XPERMS_IOCTL) {
        ksu_allowxperm(db, KERNEL_SU_DOMAIN, ALL, "blk_file", ALL);
        ksu_allowxperm(db, KERNEL_SU_DOMAIN, ALL, "fifo_file", ALL);
        ksu_allowxperm(db, KERNEL_SU_DOMAIN, ALL, "chr_file", ALL);
        ksu_allowxperm(db, KERNEL_SU_DOMAIN, ALL, "file", ALL);
    }

    // we need to save allowlist in /data/adb/ksu
    ksu_allow(db, "kernel", "adb_data_file", "dir", ALL);
    ksu_allow(db, "kernel", "adb_data_file", "file", ALL);
    // we need to search /data/app
    ksu_allow(db, "kernel", "apk_data_file", "file", "open");
    ksu_allow(db, "kernel", "apk_data_file", "dir", "open");
    ksu_allow(db, "kernel", "apk_data_file", "dir", "read");
    ksu_allow(db, "kernel", "apk_data_file", "dir", "search");
    // we may need to do mount on shell
    ksu_allow(db, "kernel", "shell_data_file", "file", ALL);
    // we need to read /data/system/packages.list
    ksu_allow(db, "kernel", "kernel", "capability", "dac_override");
    // Android 10+:
    // http://aospxref.com/android-12.0.0_r3/xref/system/sepolicy/private/file_contexts#512
    ksu_allow(db, "kernel", "packages_list_file", "file", ALL);
    // Kernel 4.4
    ksu_allow(db, "kernel", "packages_list_file", "dir", ALL);
    // Android 9-:
    // http://aospxref.com/android-9.0.0_r61/xref/system/sepolicy/private/file_contexts#360
    ksu_allow(db, "kernel", "system_data_file", "file", ALL);
    ksu_allow(db, "kernel", "system_data_file", "dir", ALL);
    // our ksud triggered by init
    ksu_allow(db, "init", "adb_data_file", "file", ALL);
    ksu_allow(db, "init", "adb_data_file", "dir", ALL); // #1289
    ksu_allow(db, "init", KERNEL_SU_DOMAIN, ALL, ALL);
    // we need to umount modules in zygote
    ksu_allow(db, "zygote", "adb_data_file", "dir", "search");

    // copied from Magisk rules
    // suRights
    ksu_allow(db, "servicemanager", KERNEL_SU_DOMAIN, "dir", "search");
    ksu_allow(db, "servicemanager", KERNEL_SU_DOMAIN, "dir", "read");
    ksu_allow(db, "servicemanager", KERNEL_SU_DOMAIN, "file", "open");
    ksu_allow(db, "servicemanager", KERNEL_SU_DOMAIN, "file", "read");
    ksu_allow(db, "servicemanager", KERNEL_SU_DOMAIN, "process", "getattr");
<<<<<<< HEAD
    ksu_allow(db, ALL, KERNEL_SU_DOMAIN, "process", "sigchld");
=======
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "process", "sigchld");
>>>>>>> 7b9651e4bd9e (drivers: Import KernelSU-Next v3.1.0 legacy susfs)

    // allowLog
    ksu_allow(db, "logd", KERNEL_SU_DOMAIN, "dir", "search");
    ksu_allow(db, "logd", KERNEL_SU_DOMAIN, "file", "read");
    ksu_allow(db, "logd", KERNEL_SU_DOMAIN, "file", "open");
    ksu_allow(db, "logd", KERNEL_SU_DOMAIN, "file", "getattr");

<<<<<<< HEAD
    // dumpsys
    ksu_allow(db, ALL, KERNEL_SU_DOMAIN, "fd", "use");
    ksu_allow(db, ALL, KERNEL_SU_DOMAIN, "fifo_file", "write");
    ksu_allow(db, ALL, KERNEL_SU_DOMAIN, "fifo_file", "read");
    ksu_allow(db, ALL, KERNEL_SU_DOMAIN, "fifo_file", "open");
    ksu_allow(db, ALL, KERNEL_SU_DOMAIN, "fifo_file", "getattr");
=======
    // dumpsys, send fd
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "fd", "use");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "fifo_file", "write");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "fifo_file", "read");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "fifo_file", "open");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "fifo_file", "getattr");
>>>>>>> 7b9651e4bd9e (drivers: Import KernelSU-Next v3.1.0 legacy susfs)

    // bootctl
    ksu_allow(db, "hwservicemanager", KERNEL_SU_DOMAIN, "dir", "search");
    ksu_allow(db, "hwservicemanager", KERNEL_SU_DOMAIN, "file", "read");
    ksu_allow(db, "hwservicemanager", KERNEL_SU_DOMAIN, "file", "open");
    ksu_allow(db, "hwservicemanager", KERNEL_SU_DOMAIN, "process", "getattr");

    // For mounting loop devices, mirrors, tmpfs
    ksu_allow(db, "kernel", ALL, "file", "read");
    ksu_allow(db, "kernel", ALL, "file", "write");

    // Allow all binder transactions
<<<<<<< HEAD
    ksu_allow(db, ALL, KERNEL_SU_DOMAIN, "binder", ALL);
=======
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "binder", ALL);
>>>>>>> 7b9651e4bd9e (drivers: Import KernelSU-Next v3.1.0 legacy susfs)

    // Allow system server kill su process
    ksu_allow(db, "system_server", KERNEL_SU_DOMAIN, "process", "getpgid");
    ksu_allow(db, "system_server", KERNEL_SU_DOMAIN, "process", "sigkill");

<<<<<<< HEAD
    mutex_unlock(&ksu_rules);
}

#define MAX_SEPOL_LEN 128
=======
    return 0;
}

void apply_kernelsu_rules()
{
	struct policydb *db;

	if (!getenforce()) {
		pr_info("SELinux permissive or disabled, apply rules!\n");
	}

#ifdef SELINUX_POLICY_INSTEAD_SELINUX_SS
	struct selinux_policy *pol, *old_pol = selinux_state.policy;
	mutex_lock(&selinux_state.policy_mutex);
	pol = ksu_dup_sepolicy(rcu_dereference_protected(old_pol, lockdep_is_held(&selinux_state.policy_mutex)));
	if (!pol) {
		pr_err("failed to dup selinux_policy\n");
		goto out_unlock;
	}
	db = &pol->policydb;

	apply_kernelsu_rules_fn((void *)db);

	rcu_assign_pointer(selinux_state.policy, pol);
	synchronize_rcu();
	ksu_destroy_sepolicy(old_pol);

	reset_avc_cache();
out_unlock:
	mutex_unlock(&selinux_state.policy_mutex);
#else
	db = get_policydb();
	rwlock_t *lock = ksu_get_policy_rwlock();
	
	if (!lock)
		goto do_stop_machine;

	write_lock(lock);
	apply_kernelsu_rules_fn((void *)db);
	write_unlock(lock);
	goto out_flush;

do_stop_machine:
	stop_machine(apply_kernelsu_rules_fn, (void *)db, NULL);

out_flush:
	smp_mb();
	reset_avc_cache();
#ifdef CONFIG_KSU_SUSFS
    // Allow umount in zygote process without installing zygisk
    //ksu_allow(db, "zygote", "labeledfs", "filesystem", "unmount");
    susfs_set_priv_app_sid();
    susfs_set_init_sid();
    susfs_set_ksu_sid();
    susfs_set_zygote_sid();
#endif // #ifdef CONFIG_KSU_SUSFS
#endif
}

#define KSU_SEPOLICY_MAX_BATCH_SIZE (8U * 1024U * 1024U)
#define KSU_SEPOLICY_MAX_ARGS 5
>>>>>>> 7b9651e4bd9e (drivers: Import KernelSU-Next v3.1.0 legacy susfs)

#define CMD_NORMAL_PERM 1
#define CMD_XPERM 2
#define CMD_TYPE_STATE 3
#define CMD_TYPE 4
#define CMD_TYPE_ATTR 5
#define CMD_ATTR 6
#define CMD_TYPE_TRANSITION 7
#define CMD_TYPE_CHANGE 8
#define CMD_GENFSCON 9

<<<<<<< HEAD
struct sepol_data {
    u32 cmd;
    u32 subcmd;
    char __user *sepol1;
    char __user *sepol2;
    char __user *sepol3;
    char __user *sepol4;
    char __user *sepol5;
    char __user *sepol6;
    char __user *sepol7;
};

static int get_object(char *buf, char __user *user_object, size_t buf_sz,
                      char **object)
{
    if (!user_object) {
        *object = ALL;
        return 0;
    }

    if (strncpy_from_user(buf, user_object, buf_sz) < 0) {
        return -EINVAL;
    }

    *object = buf;

    return 0;
}
#if ((!defined(KSU_COMPAT_USE_SELINUX_STATE)) || \
	LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
extern int avc_ss_reset(u32 seqno);
#else
extern int avc_ss_reset(struct selinux_avc *avc, u32 seqno);
#endif
// reset avc cache table, otherwise the new rules will not take effect if already denied
static void reset_avc_cache()
{
#if ((!defined(KSU_COMPAT_USE_SELINUX_STATE)) || \
	LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
    avc_ss_reset(0);
    selnl_notify_policyload(0);
    selinux_status_update_policyload(0);
#else
    struct selinux_avc *avc = selinux_state.avc;
    avc_ss_reset(avc, 0);
    selnl_notify_policyload(0);
    selinux_status_update_policyload(&selinux_state, 0);
#endif
    selinux_xfrm_notify_policyload();
}

int handle_sepolicy(unsigned long arg3, void __user *arg4)
{
    struct policydb *db;

    if (!arg4) {
        return -EINVAL;
    }

    if (!getenforce()) {
        pr_info("SELinux permissive or disabled when handle policy!\n");
    }

    struct sepol_data data;
    if (copy_from_user(&data, arg4, sizeof(struct sepol_data))) {
        pr_err("sepol: copy sepol_data failed.\n");
        return -EINVAL;
    }

    u32 cmd = data.cmd;
    u32 subcmd = data.subcmd;

    mutex_lock(&ksu_rules);

    db = get_policydb();

    int ret = -EINVAL;
    if (cmd == CMD_NORMAL_PERM) {
        char src_buf[MAX_SEPOL_LEN];
        char tgt_buf[MAX_SEPOL_LEN];
        char cls_buf[MAX_SEPOL_LEN];
        char perm_buf[MAX_SEPOL_LEN];

        char *s, *t, *c, *p;
        if (get_object(src_buf, data.sepol1, sizeof(src_buf), &s) < 0) {
            pr_err("sepol: copy src failed.\n");
            goto exit;
        }

        if (get_object(tgt_buf, data.sepol2, sizeof(tgt_buf), &t) < 0) {
            pr_err("sepol: copy tgt failed.\n");
            goto exit;
        }

        if (get_object(cls_buf, data.sepol3, sizeof(cls_buf), &c) < 0) {
            pr_err("sepol: copy cls failed.\n");
            goto exit;
        }

        if (get_object(perm_buf, data.sepol4, sizeof(perm_buf), &p) < 0) {
            pr_err("sepol: copy perm failed.\n");
            goto exit;
        }

        bool success = false;
        if (subcmd == 1) {
            success = ksu_allow(db, s, t, c, p);
        } else if (subcmd == 2) {
            success = ksu_deny(db, s, t, c, p);
        } else if (subcmd == 3) {
            success = ksu_auditallow(db, s, t, c, p);
        } else if (subcmd == 4) {
            success = ksu_dontaudit(db, s, t, c, p);
        } else {
            pr_err("sepol: unknown subcmd: %d\n", subcmd);
        }
        ret = success ? 0 : -EINVAL;

    } else if (cmd == CMD_XPERM) {
        char src_buf[MAX_SEPOL_LEN];
        char tgt_buf[MAX_SEPOL_LEN];
        char cls_buf[MAX_SEPOL_LEN];

        char __maybe_unused operation[MAX_SEPOL_LEN]; // it is always ioctl now!
        char perm_set[MAX_SEPOL_LEN];

        char *s, *t, *c;
        if (get_object(src_buf, data.sepol1, sizeof(src_buf), &s) < 0) {
            pr_err("sepol: copy src failed.\n");
            goto exit;
        }
        if (get_object(tgt_buf, data.sepol2, sizeof(tgt_buf), &t) < 0) {
            pr_err("sepol: copy tgt failed.\n");
            goto exit;
        }
        if (get_object(cls_buf, data.sepol3, sizeof(cls_buf), &c) < 0) {
            pr_err("sepol: copy cls failed.\n");
            goto exit;
        }
        if (strncpy_from_user(operation, data.sepol4, sizeof(operation)) < 0) {
            pr_err("sepol: copy operation failed.\n");
            goto exit;
        }
        if (strncpy_from_user(perm_set, data.sepol5, sizeof(perm_set)) < 0) {
            pr_err("sepol: copy perm_set failed.\n");
            goto exit;
        }

        bool success = false;
        if (subcmd == 1) {
            success = ksu_allowxperm(db, s, t, c, perm_set);
        } else if (subcmd == 2) {
            success = ksu_auditallowxperm(db, s, t, c, perm_set);
        } else if (subcmd == 3) {
            success = ksu_dontauditxperm(db, s, t, c, perm_set);
        } else {
            pr_err("sepol: unknown subcmd: %d\n", subcmd);
        }
        ret = success ? 0 : -EINVAL;
    } else if (cmd == CMD_TYPE_STATE) {
        char src[MAX_SEPOL_LEN];

        if (strncpy_from_user(src, data.sepol1, sizeof(src)) < 0) {
            pr_err("sepol: copy src failed.\n");
            goto exit;
        }

        bool success = false;
        if (subcmd == 1) {
            success = ksu_permissive(db, src);
        } else if (subcmd == 2) {
            success = ksu_enforce(db, src);
        } else {
            pr_err("sepol: unknown subcmd: %d\n", subcmd);
        }
        if (success)
            ret = 0;

    } else if (cmd == CMD_TYPE || cmd == CMD_TYPE_ATTR) {
        char type[MAX_SEPOL_LEN];
        char attr[MAX_SEPOL_LEN];

        if (strncpy_from_user(type, data.sepol1, sizeof(type)) < 0) {
            pr_err("sepol: copy type failed.\n");
            goto exit;
        }
        if (strncpy_from_user(attr, data.sepol2, sizeof(attr)) < 0) {
            pr_err("sepol: copy attr failed.\n");
            goto exit;
        }

        bool success = false;
        if (cmd == CMD_TYPE) {
            success = ksu_type(db, type, attr);
        } else {
            success = ksu_typeattribute(db, type, attr);
        }
        if (!success) {
            pr_err("sepol: %d failed.\n", cmd);
            goto exit;
        }
        ret = 0;

    } else if (cmd == CMD_ATTR) {
        char attr[MAX_SEPOL_LEN];

        if (strncpy_from_user(attr, data.sepol1, sizeof(attr)) < 0) {
            pr_err("sepol: copy attr failed.\n");
            goto exit;
        }
        if (!ksu_attribute(db, attr)) {
            pr_err("sepol: %d failed.\n", cmd);
            goto exit;
        }
        ret = 0;

    } else if (cmd == CMD_TYPE_TRANSITION) {
        char src[MAX_SEPOL_LEN];
        char tgt[MAX_SEPOL_LEN];
        char cls[MAX_SEPOL_LEN];
        char default_type[MAX_SEPOL_LEN];
        char object[MAX_SEPOL_LEN];

        if (strncpy_from_user(src, data.sepol1, sizeof(src)) < 0) {
            pr_err("sepol: copy src failed.\n");
            goto exit;
        }
        if (strncpy_from_user(tgt, data.sepol2, sizeof(tgt)) < 0) {
            pr_err("sepol: copy tgt failed.\n");
            goto exit;
        }
        if (strncpy_from_user(cls, data.sepol3, sizeof(cls)) < 0) {
            pr_err("sepol: copy cls failed.\n");
            goto exit;
        }
        if (strncpy_from_user(default_type, data.sepol4, sizeof(default_type)) <
            0) {
            pr_err("sepol: copy default_type failed.\n");
            goto exit;
        }
        char *real_object;
        if (data.sepol5 == NULL) {
            real_object = NULL;
        } else {
            if (strncpy_from_user(object, data.sepol5, sizeof(object)) < 0) {
                pr_err("sepol: copy object failed.\n");
                goto exit;
            }
            real_object = object;
        }

        bool success =
            ksu_type_transition(db, src, tgt, cls, default_type, real_object);
        if (success)
            ret = 0;

    } else if (cmd == CMD_TYPE_CHANGE) {
        char src[MAX_SEPOL_LEN];
        char tgt[MAX_SEPOL_LEN];
        char cls[MAX_SEPOL_LEN];
        char default_type[MAX_SEPOL_LEN];

        if (strncpy_from_user(src, data.sepol1, sizeof(src)) < 0) {
            pr_err("sepol: copy src failed.\n");
            goto exit;
        }
        if (strncpy_from_user(tgt, data.sepol2, sizeof(tgt)) < 0) {
            pr_err("sepol: copy tgt failed.\n");
            goto exit;
        }
        if (strncpy_from_user(cls, data.sepol3, sizeof(cls)) < 0) {
            pr_err("sepol: copy cls failed.\n");
            goto exit;
        }
        if (strncpy_from_user(default_type, data.sepol4, sizeof(default_type)) <
            0) {
            pr_err("sepol: copy default_type failed.\n");
            goto exit;
        }
        bool success = false;
        if (subcmd == 1) {
            success = ksu_type_change(db, src, tgt, cls, default_type);
        } else if (subcmd == 2) {
            success = ksu_type_member(db, src, tgt, cls, default_type);
        } else {
            pr_err("sepol: unknown subcmd: %d\n", subcmd);
        }
        if (success)
            ret = 0;
    } else if (cmd == CMD_GENFSCON) {
        char name[MAX_SEPOL_LEN];
        char path[MAX_SEPOL_LEN];
        char context[MAX_SEPOL_LEN];
        if (strncpy_from_user(name, data.sepol1, sizeof(name)) < 0) {
            pr_err("sepol: copy name failed.\n");
            goto exit;
        }
        if (strncpy_from_user(path, data.sepol2, sizeof(path)) < 0) {
            pr_err("sepol: copy path failed.\n");
            goto exit;
        }
        if (strncpy_from_user(context, data.sepol3, sizeof(context)) < 0) {
            pr_err("sepol: copy context failed.\n");
            goto exit;
        }

        if (!ksu_genfscon(db, name, path, context)) {
            pr_err("sepol: %d failed.\n", cmd);
            goto exit;
        }
        ret = 0;
    } else {
        pr_err("sepol: unknown cmd: %d\n", cmd);
    }

exit:
    mutex_unlock(&ksu_rules);

    // only allow and xallow needs to reset avc cache, but we cannot do that because
    // we are in atomic context. so we just reset it every time.
    reset_avc_cache();

    return ret;
}
=======
#define SUBCMD_NORMAL_PERM_ALLOW 1
#define SUBCMD_NORMAL_PERM_DENY 2
#define SUBCMD_NORMAL_PERM_AUDITALLOW 3
#define SUBCMD_NORMAL_PERM_DONTAUDIT 4

#define SUBCMD_XPERM_ALLOW 1
#define SUBCMD_XPERM_AUDITALLOW 2
#define SUBCMD_XPERM_DONTAUDIT 3

#define SUBCMD_TYPE_STATE_PERMISSIVE 1
#define SUBCMD_TYPE_STATE_ENFORCE 2

#define SUBCMD_TYPE_CHANGE_CHANGE 1
#define SUBCMD_TYPE_CHANGE_MEMBER 2

struct sepol_data {
    u32 cmd;
    u32 subcmd;
};

struct sepol_batch_cursor {
    const u8 *cur;
    const u8 *end;
};

static size_t sepol_remaining(const struct sepol_batch_cursor *cursor)
{
    return (size_t)(cursor->end - cursor->cur);
}

static int sepol_read_cmd_header(struct sepol_batch_cursor *cursor,
                                 struct sepol_data *header)
{
    if (sepol_remaining(cursor) < sizeof(*header)) {
        return -EINVAL;
    }

    memcpy(header, cursor->cur, sizeof(*header));
    cursor->cur += sizeof(*header);

    return 0;
}

static int sepol_read_string(struct sepol_batch_cursor *cursor,
                             const char **out)
{
    u32 len;
    const char *str;

    if (sepol_remaining(cursor) < sizeof(len)) {
        return -EINVAL;
    }

    memcpy(&len, cursor->cur, sizeof(len));
    cursor->cur += sizeof(len);

    if (len >= sepol_remaining(cursor)) {
        return -EINVAL;
    }

    str = (const char *)cursor->cur;
    if (memchr(str, '\0', len) != NULL || str[len] != '\0') {
        return -EINVAL;
    }

    cursor->cur += len + 1;
    if (len == 0) {
        *out = ALL;
        return 0;
    }

    *out = str;
    return 0;
}

static int sepol_require_not_all(const char *value, const char *name)
{
    if (value != ALL) {
        return 0;
    }

    pr_err("sepol: %s cannot be ALL.\n", name);
    return -EINVAL;
}

static int sepol_expected_argc(u32 cmd)
{
    switch (cmd) {
    case CMD_NORMAL_PERM:
        return 4;
    case CMD_XPERM:
        return 5;
    case CMD_TYPE_STATE:
        return 1;
    case CMD_TYPE:
    case CMD_TYPE_ATTR:
        return 2;
    case CMD_ATTR:
        return 1;
    case CMD_TYPE_TRANSITION:
        return 5;
    case CMD_TYPE_CHANGE:
        return 4;
    case CMD_GENFSCON:
        return 3;
    default:
        return -EINVAL;
    }
}

static int apply_one_sepolicy_cmd(struct policydb *db,
                                  const struct sepol_data *header,
                                  const char **args)
{
    bool success = false;
    int ret;

    switch (header->cmd) {
    case CMD_NORMAL_PERM:
        if (header->subcmd == SUBCMD_NORMAL_PERM_ALLOW) {
            success = ksu_allow(db, args[0], args[1], args[2], args[3]);
        } else if (header->subcmd == SUBCMD_NORMAL_PERM_DENY) {
            success = ksu_deny(db, args[0], args[1], args[2], args[3]);
        } else if (header->subcmd == SUBCMD_NORMAL_PERM_AUDITALLOW) {
            success = ksu_auditallow(db, args[0], args[1], args[2], args[3]);
        } else if (header->subcmd == SUBCMD_NORMAL_PERM_DONTAUDIT) {
            success = ksu_dontaudit(db, args[0], args[1], args[2], args[3]);
        } else {
            pr_err("sepol: unknown subcmd: %d\n", header->subcmd);
        }
        return success ? 0 : -EINVAL;

    case CMD_XPERM:
        ret = sepol_require_not_all(args[3], "operation");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[4], "perm_set");
        if (ret < 0) {
            return ret;
        }

        if (header->subcmd == SUBCMD_XPERM_ALLOW) {
            success = ksu_allowxperm(db, args[0], args[1], args[2], args[4]);
        } else if (header->subcmd == SUBCMD_XPERM_AUDITALLOW) {
            success =
                ksu_auditallowxperm(db, args[0], args[1], args[2], args[4]);
        } else if (header->subcmd == SUBCMD_XPERM_DONTAUDIT) {
            success =
                ksu_dontauditxperm(db, args[0], args[1], args[2], args[4]);
        } else {
            pr_err("sepol: unknown subcmd: %d\n", header->subcmd);
        }
        return success ? 0 : -EINVAL;

    case CMD_TYPE_STATE:
        ret = sepol_require_not_all(args[0], "type");
        if (ret < 0) {
            return ret;
        }

        if (header->subcmd == SUBCMD_TYPE_STATE_PERMISSIVE) {
            success = ksu_permissive(db, args[0]);
        } else if (header->subcmd == SUBCMD_TYPE_STATE_ENFORCE) {
            success = ksu_enforce(db, args[0]);
        } else {
            pr_err("sepol: unknown subcmd: %d\n", header->subcmd);
        }
        return success ? 0 : -EINVAL;

    case CMD_TYPE:
    case CMD_TYPE_ATTR:
        ret = sepol_require_not_all(args[0], "type");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[1], "attribute");
        if (ret < 0) {
            return ret;
        }

        if (header->cmd == CMD_TYPE) {
            success = ksu_type(db, args[0], args[1]);
        } else {
            success = ksu_typeattribute(db, args[0], args[1]);
        }
        if (!success) {
            pr_err("sepol: %d failed.\n", header->cmd);
            return -EINVAL;
        }
        return 0;

    case CMD_ATTR:
        ret = sepol_require_not_all(args[0], "attribute");
        if (ret < 0) {
            return ret;
        }

        if (!ksu_attribute(db, args[0])) {
            pr_err("sepol: %d failed.\n", header->cmd);
            return -EINVAL;
        }
        return 0;

    case CMD_TYPE_TRANSITION: {
        const char *object = ALL;

        ret = sepol_require_not_all(args[0], "src");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[1], "tgt");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[2], "cls");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[3], "default_type");
        if (ret < 0) {
            return ret;
        }

        object = args[4];

        success =
            ksu_type_transition(db, args[0], args[1], args[2], args[3], object);
        return success ? 0 : -EINVAL;
    }

    case CMD_TYPE_CHANGE:
        ret = sepol_require_not_all(args[0], "src");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[1], "tgt");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[2], "cls");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[3], "default_type");
        if (ret < 0) {
            return ret;
        }

        if (header->subcmd == SUBCMD_TYPE_CHANGE_CHANGE) {
            success = ksu_type_change(db, args[0], args[1], args[2], args[3]);
        } else if (header->subcmd == SUBCMD_TYPE_CHANGE_MEMBER) {
            success = ksu_type_member(db, args[0], args[1], args[2], args[3]);
        } else {
            pr_err("sepol: unknown subcmd: %d\n", header->subcmd);
        }
        return success ? 0 : -EINVAL;

    case CMD_GENFSCON:
        ret = sepol_require_not_all(args[0], "name");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[1], "path");
        if (ret < 0) {
            return ret;
        }
        ret = sepol_require_not_all(args[2], "context");
        if (ret < 0) {
            return ret;
        }

        if (!ksu_genfscon(db, args[0], args[1], args[2])) {
            pr_err("sepol: %d failed.\n", header->cmd);
            return -EINVAL;
        }
        return 0;

    default:
        pr_err("sepol: unknown cmd: %d\n", header->cmd);
        return -EINVAL;
    }
}

#ifdef SELINUX_POLICY_INSTEAD_SELINUX_SS
int handle_sepolicy(void __user *user_data, u64 data_len)
{
	struct selinux_policy *pol, *old_pol;
	struct policydb *db;
	struct sepol_batch_cursor cursor;
	u8 *payload;
	int ret;
	int success_cmd_count;
	u32 cmd_index;

	if (!user_data || !data_len) {
		return -EINVAL;
	}

	if (data_len > KSU_SEPOLICY_MAX_BATCH_SIZE) {
		return -E2BIG;
	}

	payload = kvmalloc((size_t)data_len, GFP_KERNEL);
	if (!payload) {
		return -ENOMEM;
	}

	if (copy_from_user(payload, user_data, (size_t)data_len)) {
		ret = -EFAULT;
		goto out_free;
	}

	if (!getenforce()) {
		pr_info("SELinux permissive or disabled when handle policy!\n");
	}

	mutex_lock(&selinux_state.policy_mutex);

	old_pol = selinux_state.policy;
	pol = ksu_dup_sepolicy(rcu_dereference_protected(
		old_pol, lockdep_is_held(&selinux_state.policy_mutex)));
	if (!pol) {
		ret = -ENOMEM;
		goto out_unlock;
	}
	db = &pol->policydb;

	cursor.cur = payload;
	cursor.end = payload + (size_t)data_len;

	ret = 0;
	success_cmd_count = 0;
	cmd_index = 0;
	while (cursor.cur < cursor.end) {
		struct sepol_data header;
		const char *args[KSU_SEPOLICY_MAX_ARGS] = { 0 };
		int expected_argc;
		u32 arg_index;

		ret = sepol_read_cmd_header(&cursor, &header);
		if (ret < 0) {
			pr_err("sepol: failed to read cmd header #%u.\n", cmd_index);
			goto out_drop_new_policy;
		}

		expected_argc = sepol_expected_argc(header.cmd);
		if (expected_argc < 0 || expected_argc > KSU_SEPOLICY_MAX_ARGS) {
			ret = -EINVAL;
			pr_err("sepol: invalid cmd header #%u.\n", cmd_index);
			goto out_drop_new_policy;
		}

		for (arg_index = 0; arg_index < (u32)expected_argc; arg_index++) {
			ret = sepol_read_string(&cursor, &args[arg_index]);
			if (ret < 0) {
				pr_err("sepol: failed to read cmd #%u arg #%u.\n", cmd_index, arg_index);
				goto out_drop_new_policy;
			}
		}

		ret = apply_one_sepolicy_cmd(db, &header, args);
		if (ret < 0) {
			pr_err("sepol: cmd #%u failed, cmd=%u subcmd=%u.\n", cmd_index, header.cmd, header.subcmd);
		} else {
			success_cmd_count++;
		}
		cmd_index++;
	}

	rcu_assign_pointer(selinux_state.policy, pol);
	synchronize_rcu();
	ksu_destroy_sepolicy(old_pol);

	reset_avc_cache();
	ret = success_cmd_count;
	goto out_unlock;

out_drop_new_policy:
	ksu_destroy_sepolicy(pol);
out_unlock:
	mutex_unlock(&selinux_state.policy_mutex);
out_free:
	kvfree(payload);

	return ret;
}
#else

struct handle_sepolicy_args {
	void *ctx_success_cmd_count;
	void *ctx_payload;
	u64 ctx_data_len;
};

static int handle_sepolicy_fn(void *data)
{
	struct sepol_batch_cursor cursor;
	int ret = 0;
	u32 cmd_index = 0;
	int success_cmd_count = 0;

	struct policydb *db = get_policydb();
	struct handle_sepolicy_args *ctx = (struct handle_sepolicy_args *)data;
	u8 *payload = (u8 *)ctx->ctx_payload;
	u64 data_len = ctx->ctx_data_len;

	cursor.cur = payload;
	cursor.end = payload + (size_t)data_len;

	while (cursor.cur < cursor.end) {
		struct sepol_data header;
		const char *args[KSU_SEPOLICY_MAX_ARGS] = { 0 };
		int expected_argc;
		u32 arg_index;

		ret = sepol_read_cmd_header(&cursor, &header);
		if (ret < 0) {
			pr_err("sepol: failed to read cmd header #%u.\n", cmd_index);
			goto out;
		}

		expected_argc = sepol_expected_argc(header.cmd);
		if (expected_argc < 0 || expected_argc > KSU_SEPOLICY_MAX_ARGS) {
			ret = -EINVAL;
			pr_err("sepol: invalid cmd header #%u.\n", cmd_index);
			goto out;
		}

		for (arg_index = 0; arg_index < (u32)expected_argc; arg_index++) {
			ret = sepol_read_string(&cursor, &args[arg_index]);
			if (ret < 0) {
				pr_err("sepol: failed to read cmd #%u arg #%u.\n", cmd_index, arg_index);
				goto out;
			}
		}

		ret = apply_one_sepolicy_cmd(db, &header, args);
		if (ret < 0)
			pr_err("sepol: cmd #%u failed, cmd=%u subcmd=%u.\n", cmd_index, header.cmd, header.subcmd);
		else {
			success_cmd_count++;
		}

		cmd_index++;
	}

out:
	*(int *)(ctx->ctx_success_cmd_count) = success_cmd_count;
	return ret;
}

int handle_sepolicy(void __user *user_data, u64 data_len)
{
	int ret = 0;
	int success_cmd_count = 0;

	if (!user_data || !data_len) return -EINVAL;
	if (data_len > KSU_SEPOLICY_MAX_BATCH_SIZE) return -E2BIG;

	u8 *payload = kvmalloc((size_t)data_len, GFP_KERNEL);
	if (!payload) return -ENOMEM;

	if (copy_from_user(payload, user_data, (size_t)data_len)) {
		ret = -EFAULT;
		goto out_free;
	}

	if (!getenforce()) {
		pr_info("SELinux permissive or disabled when handle policy!\n");
	}

	struct handle_sepolicy_args ctx = { 0 };
	ctx.ctx_success_cmd_count = (void *)&success_cmd_count;
	ctx.ctx_payload = (void *)payload;
	ctx.ctx_data_len = (u64)data_len;

	rwlock_t *lock = ksu_get_policy_rwlock();
	if (!lock)
		goto do_stop_machine;

	// Since we have GFP_ATOMIC, we can atomically lock
	write_lock(lock);
	ret = handle_sepolicy_fn((void *)&ctx);
	write_unlock(lock);
	goto out_done;

do_stop_machine:
	ret = stop_machine(handle_sepolicy_fn, (void *)&ctx, NULL);

out_done:
	if (ret) goto out_free;

	smp_mb();
	reset_avc_cache();
	ret = success_cmd_count;

out_free:
	kvfree(payload);
	return ret;
}
#endif // SELINUX_POLICY_INSTEAD_SELINUX_SS
>>>>>>> 7b9651e4bd9e (drivers: Import KernelSU-Next v3.1.0 legacy susfs)

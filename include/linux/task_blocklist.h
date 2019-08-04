/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_TASK_BLOCKLIST_H
#define _LINUX_TASK_BLOCKLIST_H

#include <linux/sched.h>
#include <linux/string.h>

static inline bool task_is_blocklisted(struct task_struct *tsk)
{
	char comm[TASK_COMM_LEN];

	get_task_comm(comm, tsk);
	return is_global_init(tsk) ||
			!strncmp(comm, "iop@", 4) ||
			!strncmp(comm, "perf@", 5) ||
			!strncmp(comm, "power@", 6) ||
			!strcmp(comm, "init.qcom.post_") ||
			!strcmp(comm, "NodeLooperThrea") ||
			!strcmp(comm, "PERFD-SERVER") ||
			!strcmp(comm, "power-servic");
}

#endif /* _LINUX_TASK_BLOCKLIST_H */

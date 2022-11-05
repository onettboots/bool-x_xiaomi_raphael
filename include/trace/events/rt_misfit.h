/*
 * rt_cas.h
 *
 * rt_cas sched trace events
 *
 * Copyright (c) 2012-2020 Huawei Technologies Co., Ltd.
 *
 * This software is licensed under the terms of the GNU General Public
 * License version 2, as published by the Free Software Foundation, and
 * may be copied, distributed, and modified under those terms.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 */

#ifdef CONFIG_HW_RT_ACTIVE_LB
TRACE_EVENT(sched_rt_misfit_check,

	TP_PROTO(struct task_struct *task, unsigned long task_util,
		 unsigned int cpu, unsigned int misfit),

	TP_ARGS(task, task_util, cpu, misfit),

	TP_STRUCT__entry(
		__array( char,	comm,	TASK_COMM_LEN	)
		__field( pid_t,		pid		)
		__field( int,		prio		)
		__field( unsigned long,	task_util	)
		__field( int,		cpu		)
		__field( unsigned long,	cap_curr	)
		__field( unsigned long,	cap_orig	)
		__field( unsigned long,	cap		)
		__field( unsigned int,	misfit		)
	),

	TP_fast_assign(
		memcpy(__entry->comm, task->comm, TASK_COMM_LEN);
		__entry->pid		= task->pid;
		__entry->prio		= task->prio;
		__entry->task_util	= task_util;
		__entry->cpu		= cpu;
		__entry->cap_curr	= capacity_curr_of(cpu);
		__entry->cap_orig	= capacity_orig_of(cpu);
		__entry->cap		= capacity_of(cpu);
		__entry->misfit		= misfit;
	),

	TP_printk("comm=%s pid=%d prio=%d task_util=%lu cpu=%d "
		  "cap_orig=%lu/%lu/%lu misfit=%d",
		__entry->comm, __entry->pid, __entry->prio,
		__entry->task_util, __entry->cpu, __entry->cap_curr,
		__entry->cap_orig, __entry->cap, __entry->misfit)
);
#endif

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

#ifdef CONFIG_HW_RT_CAS
TRACE_EVENT(sched_find_cas_cpu_each,

	TP_PROTO(struct task_struct *task, int cpu, int target_cpu,
		int isolated, int high_irq, int idle, unsigned long task_util,
		unsigned long cpu_util, int cpu_cap),

	TP_ARGS(task, cpu, target_cpu, isolated, high_irq, idle, task_util, cpu_util, cpu_cap),

	TP_STRUCT__entry(
		__array( char,	comm,	TASK_COMM_LEN	)
		__field( pid_t,		pid		)
		__field( int,		prio		)
		__field( int,		cpu		)
		__field( int,		target_cpu	)
		__field( int,		isolated	)
		__field( bool,		high_irq	)
		__field( unsigned long,	idle		)
		__field( unsigned long,	task_util	)
		__field( unsigned long,	cpu_util	)
		__field( unsigned long,	cpu_cap		)
	),

	TP_fast_assign(
		memcpy(__entry->comm, task->comm, TASK_COMM_LEN);
		__entry->pid		= task->pid;
		__entry->prio		= task->prio;
		__entry->cpu		= cpu;
		__entry->target_cpu	= target_cpu;
		__entry->isolated	= isolated;
		__entry->high_irq	= high_irq;
		__entry->idle		= idle;
		__entry->task_util	= task_util;
		__entry->cpu_util	= cpu_util;
		__entry->cpu_cap	= cpu_cap;
	),

	TP_printk("comm=%s pid=%d prio=%d cpu=%d target_cpu=%d "
		  "isolated=%d high_irq=%d idle=%d "
		  "task_util=%lu cpu_util=%lu cpu_cap=%lu",
		__entry->comm, __entry->pid, __entry->prio,
		__entry->cpu, __entry->target_cpu, __entry->isolated,
		__entry->high_irq, __entry->idle, __entry->task_util,
		__entry->cpu_util, __entry->cpu_cap)
);

TRACE_EVENT(sched_find_cas_cpu,

	TP_PROTO(struct task_struct *task, struct cpumask *lowest_mask,
		 unsigned long tutil, unsigned int prefer_idle,
		 int prev_cpu, int target_cpu),

	TP_ARGS(task, lowest_mask, tutil, prefer_idle, prev_cpu, target_cpu),

	TP_STRUCT__entry(
		__array( char,	comm,	TASK_COMM_LEN	)
		__field( pid_t,		pid		)
		__field( unsigned int,	prio		)
		__bitmask(lowest, num_possible_cpus()	)
		__field( unsigned long,	tutil		)
		__field( unsigned int,	prefer_idle	)
		__field( int,		prev_cpu	)
		__field( int,		target_cpu	)
	),

	TP_fast_assign(
		memcpy(__entry->comm, task->comm, TASK_COMM_LEN);
		__entry->pid		= task->pid;
		__entry->prio		= task->prio;
		__assign_bitmask(lowest, cpumask_bits(lowest_mask), num_possible_cpus());
		__entry->tutil		= tutil;
		__entry->prefer_idle	= prefer_idle;
		__entry->prev_cpu	= prev_cpu;
		__entry->target_cpu	= target_cpu;
	),

	TP_printk("comm=%s pid=%d prio=%u lowest_mask=%s tutil=%lu prefer_idle=%u prev=%d target=%d\n",
		__entry->comm, __entry->pid, __entry->prio,
		__get_bitmask(lowest), __entry->tutil, __entry->prefer_idle,
		__entry->prev_cpu, __entry->target_cpu)
);
#endif

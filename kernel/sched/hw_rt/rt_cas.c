// SPDX-License-Identifier: GPL-2.0
/*
 * Real-Time Scheduling Class (mapped to the SCHED_FIFO and SCHED_RR
 * policies)
 */

#ifdef CONFIG_HW_RT_CAS

#include <linux/version.h>

extern unsigned long cpu_util(int cpu);

extern unsigned int sysctl_sched_cstate_aware;

unsigned int sysctl_sched_enable_rt_cas = 1;

#define RT_CAPACITY_MARGIN 1280 /* ~20% */

unsigned int sysctl_sched_rt_capacity_margin = RT_CAPACITY_MARGIN;

static unsigned int rt_up_migration_util_filter = 25;
static inline bool rt_favor_litte_core(struct task_struct *p)
{
	return uclamp_task_util(p) * 100 <
		capacity_orig_of(0) * rt_up_migration_util_filter;
}

static int find_cas_cpu(struct sched_domain *sd,
			struct task_struct *task, struct cpumask *lowest_mask)
{
	struct root_domain *rd = cpu_rq(smp_processor_id())->rd;
	struct sched_group *sg = NULL;
	struct sched_group *sg_target = NULL;
	struct sched_group *sg_backup = NULL;
	struct cpumask search_cpu, backup_search_cpu;
	int cpu = -1;
	int target_cpu = -1;
	unsigned long cpu_capacity;
	unsigned long boosted_tutil = uclamp_task_util(task);
	unsigned long target_capacity = ULONG_MAX;
	unsigned long util;
	unsigned long target_cpu_util = ULONG_MAX;
	int target_cpu_idle_idx = INT_MAX;
	int cpu_idle_idx = -1;
	int prev_cpu = task_cpu(task);
#ifdef CONFIG_UCLAMP_TASK_GROUP
	bool boosted = uclamp_boosted(task);
#else
	bool boosted = schedtune_task_boost(task) > 0;
#endif
#ifdef CONFIG_UCLAMP_TASK_GROUP
	bool prefer_idle = uclamp_latency_sensitive(task);
#else
	bool prefer_idle = schedtune_prefer_idle(task) > 0;
#endif
	bool favor_larger_capacity = false;

	if (!sysctl_sched_enable_rt_cas)
		return -1;

	rcu_read_lock();

	sd = rcu_dereference(per_cpu(sd_ea, 0));
	if (!sd) {
		rcu_read_unlock();
		return -1;
	}

	sg = sd->groups;
	do {
		cpu = group_first_cpu(sg);
		if (!cpumask_intersects(lowest_mask, sched_group_span(sg)))
			continue;

#if defined(CONFIG_UCLAMP_TASK_GROUP)
		favor_larger_capacity = boosted;
#endif
		if (favor_larger_capacity) {
			if (cpumask_test_cpu(rd->max_cap_orig_cpu, sched_group_span(sg))) {
				sg_target = sg;
				break;
			}

			sg_backup = sg;
			continue;
		}

		cpu = group_first_cpu(sg);

		/*
		 * 1. add margin to support task migration.
		 * 2. if task_util is high then all cpus, make sure the
		 * sg_backup with the most powerful cpus is selected.
		 */
		if (!rt_task_fits_capacity(task, cpu)) {
			sg_backup = sg;
			continue;
		}

		/* support task boost */
		cpu_capacity = capacity_orig_of(cpu);
		if (boosted_tutil > cpu_capacity) {
			sg_backup = sg;
			continue;
		}

		/* sg_target: select the sg with smaller capacity */
		if (cpu_capacity < target_capacity) {
			target_capacity = cpu_capacity;
			sg_target = sg;
		}
	} while (sg = sg->next, sg != sd->groups);

	if (!sg_target)
		sg_target = sg_backup;

	if (sg_target) {
		cpumask_and(&search_cpu, lowest_mask,
			sched_group_span(sg_target));
		cpumask_copy(&backup_search_cpu, lowest_mask);
		cpumask_andnot(&backup_search_cpu, &backup_search_cpu,
			&search_cpu);
	} else {
		cpumask_copy(&search_cpu, lowest_mask);
		cpumask_clear(&backup_search_cpu);
	}

retry:
	cpu = cpumask_first(&search_cpu);
	do {
		trace_sched_find_cas_cpu_each(task, cpu, target_cpu,
			cpu_isolated(cpu), sched_cpu_high_irqload(cpu),
			idle_cpu(cpu), boosted_tutil, cpu_util(cpu),
			capacity_orig_of(cpu));

		if (cpu_isolated(cpu))
			continue;
		if (!cpumask_test_cpu(cpu, &task->cpus_allowed))
			continue;

		if (sched_cpu_high_irqload(cpu))
			continue;

		if (prefer_idle && idle_cpu(cpu)) {
			target_cpu = cpu;
			break;
		}

		/* !prefer_idle task: find best cpu with smallest max_capacity */
		if (!prefer_idle && target_cpu != -1 &&
		    capacity_orig_of(cpu) > capacity_orig_of(target_cpu))
			continue;

		util = cpu_util(cpu);

		/* Find the least loaded CPU */
		if (util > target_cpu_util)
			continue;
		/*
		 * If the previous CPU has same load, keep it as
		 * target_cpu.
		 */
		if (target_cpu_util == util && target_cpu == prev_cpu)
			continue;

		/*
		 * If candidate CPU is the previous CPU, select it.
		 * Otherwise, if its load is same with target_cpu and in
		 * a shallower C-state, select it.  If all above
		 * conditions are same, select the least cumulative
		 * window demand CPU.
		 */
		if (sysctl_sched_cstate_aware)
			cpu_idle_idx = idle_get_state_idx(cpu_rq(cpu));

		if (cpu != prev_cpu && target_cpu_util == util) {
			if (target_cpu_idle_idx < cpu_idle_idx)
				continue;
		}

		target_cpu_idle_idx = cpu_idle_idx;
		target_cpu_util = util;
		target_cpu = cpu;
	} while ((cpu = cpumask_next(cpu, &search_cpu)) < nr_cpu_ids);

	if (target_cpu != -1 && cpumask_test_cpu(target_cpu, lowest_mask)) {
		goto done;
	} else if (!cpumask_empty(&backup_search_cpu)) {
		cpumask_copy(&search_cpu, &backup_search_cpu);
		cpumask_clear(&backup_search_cpu);
		goto retry;
	}

done:
	trace_sched_find_cas_cpu(task, lowest_mask, boosted_tutil, prefer_idle, prev_cpu, target_cpu);
	rcu_read_unlock();
	return target_cpu;
}
#else
static int find_cas_cpu(struct sched_domain *sd,
			struct task_struct *task, struct cpumask *lowest_mask)
{
	return -1;
}
#endif

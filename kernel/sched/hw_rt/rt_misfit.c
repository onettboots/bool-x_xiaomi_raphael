// SPDX-License-Identifier: GPL-2.0
/*
 * Real-Time Scheduling Class (mapped to the SCHED_FIFO and SCHED_RR
 * policies)
 */

#ifdef CONFIG_HW_RT_ACTIVE_LB


#ifdef CONFIG_HW_RTG
#include <linux/sched/hw_rtg/rtg_sched.h>

unsigned int sysctl_sched_enable_rt_active_lb = 1;
#else
unsigned int sysctl_sched_enable_rt_active_lb = 1;
#endif

static int rt_active_load_balance_cpu_stop(void *data)
{
	struct rq *busiest_rq = data;
	struct task_struct *next_task = busiest_rq->rt_push_task;
	struct rq *lowest_rq = NULL;
	unsigned long flags;

	raw_spin_lock_irqsave(&busiest_rq->lock, flags);
	busiest_rq->rt_active_balance = 0;

	/* find_lock_lowest_rq locks the rq if found */
	lowest_rq = find_lock_lowest_rq(next_task, busiest_rq);
	if (!lowest_rq)
		goto out;

	if (capacity_orig_of(cpu_of(lowest_rq)) <= capacity_orig_of(task_cpu(next_task)))
		goto unlock;

	deactivate_task(busiest_rq, next_task, 0);
	next_task->on_rq = TASK_ON_RQ_MIGRATING;
	set_task_cpu(next_task, lowest_rq->cpu);
	next_task->on_rq = TASK_ON_RQ_QUEUED;
	activate_task(lowest_rq, next_task, 0);

	resched_curr(lowest_rq);

unlock:
	double_unlock_balance(busiest_rq, lowest_rq);

out:
	put_task_struct(next_task);
	raw_spin_unlock_irqrestore(&busiest_rq->lock, flags);

	return 0;
}

void check_for_rt_migration(struct rq *rq, struct task_struct *p)
{
	bool need_actvie_lb = false;
	bool misfit_task = false;
	int cpu = task_cpu(p);
	unsigned long cpu_orig_cap;

	if (!sysctl_sched_enable_rt_active_lb)
		return;

	if (p->nr_cpus_allowed == 1)
		return;

	cpu_orig_cap = capacity_orig_of(cpu);
	/* cpu has max capacity, no need to do balance */
	if (cpu_orig_cap == rq->rd->max_cpu_capacity.val)
		return;

	misfit_task = !rt_task_fits_capacity(p, cpu);

	trace_sched_rt_misfit_check(p, uclamp_task_util(p), cpu, misfit_task);

	if (misfit_task) {
		raw_spin_lock(&rq->lock);
		if (!rq->active_balance && !rq->rt_active_balance) {
			rq->rt_active_balance = 1;
			rq->rt_push_task = p;
			get_task_struct(p);
			need_actvie_lb = true;
		}
		raw_spin_unlock(&rq->lock);

		if (need_actvie_lb)
			stop_one_cpu_nowait(task_cpu(p),
						rt_active_load_balance_cpu_stop,
						rq, &rq->rt_active_balance_work);
	}
}
#endif

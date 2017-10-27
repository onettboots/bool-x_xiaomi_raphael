#ifndef _LINUX_SCHED_ISOLATION_H
#define _LINUX_SCHED_ISOLATION_H

#include <linux/cpumask.h>
#include <linux/init.h>
#include <linux/tick.h>

#ifdef CONFIG_NO_HZ_FULL
DECLARE_STATIC_KEY_FALSE(housekeeping_overriden);
extern int housekeeping_any_cpu(void);
extern const struct cpumask *housekeeping_cpumask(void);
extern void housekeeping_affine(struct task_struct *t);
extern bool housekeeping_test_cpu(int cpu);
extern void __init housekeeping_init(void);

#else

static inline int housekeeping_any_cpu(void)
{
	cpumask_t available;
	int cpu;

	cpumask_andnot(&available, cpu_online_mask, cpu_isolated_mask);
	cpu = cpumask_any(&available);
	if (cpu >= nr_cpu_ids)
		cpu = smp_processor_id();

	return cpu;
}


static inline const struct cpumask *housekeeping_cpumask(void)
{
	return cpu_possible_mask;
}

static inline void housekeeping_affine(struct task_struct *t) { }
static inline void housekeeping_init(void) { }
#endif /* CONFIG_NO_HZ_FULL */

static inline bool housekeeping_cpu(int cpu)
{
#ifdef CONFIG_NO_HZ_FULL
	if (static_branch_unlikely(&housekeeping_overriden))
		return housekeeping_test_cpu(cpu);
#endif
	return !cpu_isolated(cpu);
}

#endif /* _LINUX_SCHED_ISOLATION_H */

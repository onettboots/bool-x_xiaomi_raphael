#ifndef __HW_CAPACITY_AWARE_H__
#define __HW_CAPACITY_AWARE_H__

#ifdef CONFIG_HW_RT_CAS
extern unsigned int sysctl_sched_enable_rt_cas;
#endif
#ifdef CONFIG_HW_RT_ACTIVE_LB
extern unsigned int sysctl_sched_enable_rt_active_lb;
#endif

extern unsigned int sysctl_sched_rt_capacity_margin;

#endif

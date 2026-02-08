// SPDX-License-Identifier: GPL-2.0
/*
 * Piece-Of-Cake (POC) CPU Selector (Backport for 4.14)
 * FINAL FIX V4: Fix cpumask types and sysctl variables
 */

#ifdef CONFIG_SCHED_POC_SELECTOR

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/static_key.h>
#include <linux/sysctl.h>
#include <linux/cpu.h>
#include <linux/topology.h> /* Penting untuk topology_sibling_cpumask */

#define SCHED_POC_SELECTOR_AUTHOR   "Masahito Suzuki"
#define SCHED_POC_SELECTOR_VERSION  "1.8-bp-4.14-fix-v4"

#ifdef CONFIG_SCHED_SMT
#define IF_SMT(code) code
#else
#define IF_SMT(code)
#endif

/**************************************************************
 * Static keys:
 */
struct static_key_true sched_poc_enabled = STATIC_KEY_TRUE_INIT;
struct static_key_true sched_poc_single_word = STATIC_KEY_TRUE_INIT;

/**************************************************************
 * Per-CPU variables:
 */
#define POC_HASH_MULT 0x9E3779B9U
static DEFINE_PER_CPU(u32, poc_rr_counter);

/**************************************************************
 * Debug counters:
 */
#ifdef CONFIG_SCHED_POC_SELECTOR_DEBUG
static DEFINE_PER_CPU(u32, poc_dbg_hit);
static DEFINE_PER_CPU(u32, poc_dbg_fallthrough);
static DEFINE_PER_CPU(u32, poc_dbg_sticky);
static DEFINE_PER_CPU(u32, poc_dbg_llc_hit);
#ifdef CONFIG_SCHED_SMT
static DEFINE_PER_CPU(u32, poc_dbg_smt_tgt);
#endif
static DEFINE_PER_CPU(atomic_t, poc_dbg_selected);

#define POC_DBG_INC_HIT()          __this_cpu_inc(poc_dbg_hit)
#define POC_DBG_INC_FALLTHROUGH()  __this_cpu_inc(poc_dbg_fallthrough)
#define POC_DBG_INC_STICKY()      __this_cpu_inc(poc_dbg_sticky)
#define POC_DBG_INC_LLC_HIT()     __this_cpu_inc(poc_dbg_llc_hit)
#ifdef CONFIG_SCHED_SMT
#define POC_DBG_INC_SMT_TGT()     __this_cpu_inc(poc_dbg_smt_tgt)
#else
#define POC_DBG_INC_SMT_TGT()     do {} while (0)
#endif
#define POC_DBG_INC_SELECTED(cpu)  atomic_inc(&per_cpu(poc_dbg_selected, cpu))
#else
#define POC_DBG_INC_HIT()          do {} while (0)
#define POC_DBG_INC_FALLTHROUGH()  do {} while (0)
#define POC_DBG_INC_STICKY()      do {} while (0)
#define POC_DBG_INC_LLC_HIT()     do {} while (0)
#define POC_DBG_INC_SMT_TGT()     do {} while (0)
#define POC_DBG_INC_SELECTED(cpu)  do {} while (0)
#endif

/**************************************************************
 * Bit manipulation primitives:
 */

/* Tier 1: Hardware CTZ */
#if defined(__x86_64__) && defined(__BMI__)
#define POC_CTZ64(v) ((int)__builtin_ctzll(v))
#define POC_CTZ64_NAME "HW (TZCNT)"
#elif defined(__aarch64__)
#define POC_CTZ64(v) ((int)__builtin_ctzll(v))
#define POC_CTZ64_NAME "HW (RBIT+CLZ)"
/* Tier 2: x86-64 without BMI1 */
#elif defined(__x86_64__)
static __always_inline int poc_ctz64_bsf(u64 v)
{
	if (unlikely(!v))
		return 64;
	return (int)__builtin_ctzll(v);
}
#define POC_CTZ64(v) poc_ctz64_bsf(v)
#define POC_CTZ64_NAME "HW (BSF)"
#else
/* Tier 3: SW Fallback */
#define DEBRUIJN_CTZ64_CONST 0x03F79D71B4CA8B09ULL
static const u8 debruijn_ctz64_tab[64] = {
	 0,  1, 56,  2, 57, 49, 28,  3,
	61, 58, 42, 50, 38, 29, 17,  4,
	62, 47, 59, 36, 45, 43, 51, 22,
	53, 39, 33, 30, 24, 18, 12,  5,
	63, 55, 48, 27, 60, 41, 37, 16,
	46, 35, 44, 21, 52, 32, 23, 11,
	54, 26, 40, 15, 34, 20, 31, 10,
	25, 14, 19,  9, 13,  8,  7,  6,
};
static __always_inline int debruijn_ctz64(u64 v)
{
	if (unlikely(!v))
		return 64;
	u64 lsb = v & (-(s64)v);
	u32 idx = (u32)((lsb * DEBRUIJN_CTZ64_CONST) >> 58);
	return (int)debruijn_ctz64_tab[idx & 63];
}
#define POC_CTZ64(v) debruijn_ctz64(v)
#define POC_CTZ64_NAME "SW (De Bruijn)"
#endif

/* PTSELECT */
#if defined(__x86_64__) && defined(__BMI2__) && \
    !defined(__znver1) && !defined(__znver2)
static __always_inline int poc_ptselect(u64 v, int j)
{
	u64 deposited;
	asm("pdep %2, %1, %0" : "=r"(deposited) : "r"(1ULL << j), "rm"(v));
	return POC_CTZ64(deposited);
}
#define POC_PTSELECT(v, j) poc_ptselect(v, j)
#define POC_PTSELECT_NAME "HW (PDEP)"
#else
static __always_inline int poc_ptselect_sw(u64 v, int j)
{
	int k;
	for (k = 0; k < j; k++)
		v &= v - 1;
	return POC_CTZ64(v);
}
#define POC_PTSELECT(v, j) poc_ptselect_sw(v, j)
#define POC_PTSELECT_NAME "SW (loop)"
#endif

#define POC_FASTRANGE(seed, range) ((u32)(((u64)(seed) * (u32)(range)) >> 32))

/**************************************************************
 * Core idle state management:
 */

static bool is_idle_core_poc(int cpu, struct sched_domain_shared *sd_share)
{
	int base = sd_share->poc_cpu_base;
	int nr_words = sd_share->poc_nr_words;
	int sibling;

	/* FIX: Gunakan topology_sibling_cpumask untuk 4.14 */
	for_each_cpu(sibling, topology_sibling_cpumask(cpu)) {
		int bit  = sibling - base;
		int word = bit >> 6;
		int pos  = bit & 63;

		if ((unsigned int)word >= nr_words)
			return false;

		u64 cpus = (u64)atomic64_read(&sd_share->poc_idle_cpus[word]);

		if (!(cpus & (1ULL << pos)))
			return false;
	}
	return true;
}

void __set_cpu_idle_state(int cpu, int state)
{
	struct sched_domain_shared *sd_share;

	rcu_read_lock();
	sd_share = rcu_dereference(per_cpu(sd_llc_shared, cpu));
	if (!sd_share)
		goto out_unlock;

	int bit  = cpu - sd_share->poc_cpu_base;
	int word = bit >> 6;
	int pos  = bit & 63;

	if ((unsigned int)word >= sd_share->poc_nr_words)
		goto out_unlock;

	if (state > 0)
		atomic64_or(1ULL << pos, &sd_share->poc_idle_cpus[word]);
	else
		atomic64_andnot(1ULL << pos, &sd_share->poc_idle_cpus[word]);

	smp_mb__after_atomic();

	if (sched_smt_active()) {
		/* FIX: Gunakan topology_sibling_cpumask */
		int core     = cpumask_first(topology_sibling_cpumask(cpu));
		int core_bit = core - sd_share->poc_cpu_base;
		int core_w   = core_bit >> 6;
		int core_pos = core_bit & 63;

		if ((unsigned int)core_w < sd_share->poc_nr_words) {
			if (state > 0 && is_idle_core_poc(cpu, sd_share))
				atomic64_or(1ULL << core_pos,
					    &sd_share->poc_idle_cores[core_w]);
			else
				atomic64_andnot(1ULL << core_pos,
						&sd_share->poc_idle_cores[core_w]);
		}
	}

out_unlock:
	rcu_read_unlock();
}

/**************************************************************
 * Idle CPU selection helpers:
 */

static __always_inline int poc_ptselect_multi(const u64 *mask, const int *pcnt,
					      int nr_words, int pick, int base)
{
	int i, acc = 0;

	for (i = 0; i < nr_words; i++) {
		if (pick < acc + pcnt[i])
			return POC_PTSELECT(mask[i], pick - acc)
				+ (i << 6) + base;
		acc += pcnt[i];
	}
	return -1;
}

static __always_inline int poc_select_rr(const u64 *mask, int nr_words,
					 int base, unsigned int seed)
{
	int pcnt[POC_MASK_WORDS_MAX];
	int total = 0;
	int i;

	for (i = 0; i < nr_words; i++) {
		pcnt[i] = hweight64(mask[i]);
		total += pcnt[i];
	}
	return poc_ptselect_multi(mask, pcnt, nr_words,
				  POC_FASTRANGE(seed, total), base);
}

#ifdef CONFIG_SCHED_SMT
static __always_inline int poc_find_idle_smt_sibling(int target,
				const u64 *cpu_mask, int nr_words, int base,
				const u64 *smt_siblings)
{
	int tgt_bit = target - base;
	int w = tgt_bit >> 6;
	u64 sib_mask, idle_sibs;

	if ((unsigned int)tgt_bit >= nr_words * 64)
		return -1;

	sib_mask = smt_siblings[tgt_bit];
	idle_sibs = cpu_mask[w] & sib_mask;

	if (idle_sibs)
		return base + (w << 6) + POC_CTZ64(idle_sibs);

	return -1;
}
#endif

/**************************************************************
 * Fast path dispatcher:
 */

#define DEFINE_SELECT_IDLE_CPU_POC(N) \
static int select_idle_cpu_poc_##N(bool has_idle_core, \
				   int target, \
				   struct sched_domain_shared *sd_share) \
{ \
	int base = sd_share->poc_cpu_base; \
	int tgt_bit = target - base; \
	u64 cpu_mask[(N)]; \
	u64 any = 0; \
	int i; \
	for (i = 0; i < (N); i++) { \
		cpu_mask[i] = (u64)atomic64_read( \
				&sd_share->poc_idle_cpus[i]); \
		any |= cpu_mask[i]; \
	} \
	if (!any) \
		return -1; \
	{ \
		int w   = tgt_bit >> 6; \
		int pos = tgt_bit & 63; \
		if ((unsigned int)w < (N) && \
		    (cpu_mask[w] & (1ULL << pos))) { \
			POC_DBG_INC_STICKY(); \
			return target; \
		} \
	} \
	{ \
		unsigned int seed; \
		seed = __this_cpu_inc_return(poc_rr_counter) * POC_HASH_MULT; \
		if (has_idle_core && sched_smt_active()) { \
			u64 core_mask[(N)]; \
			u64 any_cores = 0; \
			for (i = 0; i < (N); i++) { \
				core_mask[i] = (u64)atomic64_read( \
					&sd_share->poc_idle_cores[i]); \
				any_cores |= core_mask[i]; \
			} \
			if (any_cores) { \
				POC_DBG_INC_LLC_HIT(); \
				return poc_select_rr(core_mask, (N), base, seed); \
			} \
			IF_SMT( \
			{ \
				int smt_tgt = poc_find_idle_smt_sibling( \
					target, cpu_mask, (N), base, \
					sd_share->poc_smt_siblings); \
				if (smt_tgt >= 0) { \
					POC_DBG_INC_SMT_TGT(); \
					return smt_tgt; \
				} \
			} \
			) \
			return poc_select_rr(cpu_mask, (N), base, seed); \
		} \
		POC_DBG_INC_LLC_HIT(); \
		return poc_select_rr(cpu_mask, (N), base, seed); \
	} \
}

DEFINE_SELECT_IDLE_CPU_POC(1)
DEFINE_SELECT_IDLE_CPU_POC(2)

static __always_inline int select_idle_cpu_poc(bool has_idle_core,
				int target,
				struct sched_domain_shared *sd_share)
{
	if (static_branch_likely(&sched_poc_single_word))
		return select_idle_cpu_poc_1(has_idle_core, target, sd_share);
	else
		return select_idle_cpu_poc_2(has_idle_core, target, sd_share);
}

/**************************************************************
 * Sysctl interface and initialization:
 */

#ifdef CONFIG_SYSCTL

/* FIX: Define variabel lokal untuk sysctl */
static int zero = 0;
static int one = 1;

static void poc_resync_idle_state(void)
{
	int cpu;

	for_each_online_cpu(cpu)
		__set_cpu_idle_state(cpu, idle_cpu(cpu));
}

static int sched_poc_sysctl_handler(struct ctl_table *table, int write,
				    void __user *buffer, size_t *lenp, loff_t *ppos)
{
	unsigned int val = static_branch_likely(&sched_poc_enabled) ? 1 : 0;
	struct ctl_table tmp = {
		.data    = &val,
		.maxlen  = sizeof(val),
		.extra1  = &zero,
		.extra2  = &one,
	};
	int ret = proc_douintvec_minmax(&tmp, write, buffer, lenp, ppos);

	if (!ret && write) {
		get_online_cpus();
		if (val) {
			static_branch_enable(&sched_poc_enabled);
			poc_resync_idle_state();
		} else {
			static_branch_disable(&sched_poc_enabled);
		}
		put_online_cpus();
	}
	return ret;
}

static struct ctl_table sched_poc_sysctls[] = {
	{
		.procname	= "sched_poc_selector",
		.data		= NULL,
		.maxlen		= sizeof(unsigned int),
		.mode		= 0644,
		.proc_handler	= sched_poc_sysctl_handler,
	},
	{ }
};

static struct ctl_path kern_path[] = { { .procname = "kernel", }, { } };

static int __init sched_poc_sysctl_init(void)
{
	printk(KERN_INFO "%s %s by %s [CTZ: %s, PTSelect: %s]\n",
		"POC Selector", SCHED_POC_SELECTOR_VERSION,
		SCHED_POC_SELECTOR_AUTHOR, POC_CTZ64_NAME, POC_PTSELECT_NAME);

	register_sysctl_paths(kern_path, sched_poc_sysctls);
	return 0;
}
late_initcall(sched_poc_sysctl_init);

#endif

static int __init sched_poc_rr_init(void)
{
	int cpu;
	for_each_possible_cpu(cpu)
		per_cpu(poc_rr_counter, cpu) = (u32)cpu << 24;
	return 0;
}
early_initcall(sched_poc_rr_init);

/**************************************************************
 * Debug: sysfs interface
 */

#ifdef CONFIG_SCHED_POC_SELECTOR_DEBUG

static u64 poc_dbg_sum_percpu(u32 __percpu *var)
{
	u64 sum = 0;
	int cpu;
	for_each_possible_cpu(cpu)
		sum += per_cpu(*var, cpu);
	return sum;
}

#define DEFINE_POC_DBG_ATTR(ctr) \
static ssize_t poc_dbg_##ctr##_show(struct kobject *kobj, \
		struct kobj_attribute *attr, char *buf) \
{ \
	return scnprintf(buf, PAGE_SIZE, "%llu\n", \
			  poc_dbg_sum_percpu(&poc_dbg_##ctr)); \
} \
static struct kobj_attribute poc_attr_##ctr = { \
	.attr = { .name = #ctr, .mode = 0444 }, \
	.show = poc_dbg_##ctr##_show, \
}

DEFINE_POC_DBG_ATTR(hit);
DEFINE_POC_DBG_ATTR(fallthrough);
DEFINE_POC_DBG_ATTR(sticky);
DEFINE_POC_DBG_ATTR(llc_hit);
#ifdef CONFIG_SCHED_SMT
DEFINE_POC_DBG_ATTR(smt_tgt);
#endif

struct poc_selected_attr {
	struct kobj_attribute kattr;
	int cpu;
};

static ssize_t poc_selected_show(struct kobject *kobj,
				 struct kobj_attribute *attr, char *buf)
{
	struct poc_selected_attr *sa =
		container_of(attr, struct poc_selected_attr, kattr);
	return scnprintf(buf, PAGE_SIZE, "%d\n",
			  atomic_read(&per_cpu(poc_dbg_selected, sa->cpu)));
}

static ssize_t poc_dbg_reset_store(struct kobject *kobj,
				   struct kobj_attribute *attr,
				   const char *buf, size_t count)
{
	int cpu;
	for_each_possible_cpu(cpu) {
		per_cpu(poc_dbg_hit, cpu) = 0;
		per_cpu(poc_dbg_fallthrough, cpu) = 0;
		per_cpu(poc_dbg_sticky, cpu) = 0;
		per_cpu(poc_dbg_llc_hit, cpu) = 0;
#ifdef CONFIG_SCHED_SMT
		per_cpu(poc_dbg_smt_tgt, cpu) = 0;
#endif
		atomic_set(&per_cpu(poc_dbg_selected, cpu), 0);
	}
	return count;
}

static struct kobj_attribute poc_attr_reset = {
	.attr  = { .name = "reset", .mode = 0200 },
	.store = poc_dbg_reset_store,
};

#define DEFINE_POC_HW_ATTR(fname, namestr) \
static ssize_t poc_hw_##fname##_show(struct kobject *kobj, \
		struct kobj_attribute *attr, char *buf) \
{ \
	return scnprintf(buf, PAGE_SIZE, "%s\n", namestr); \
} \
static struct kobj_attribute poc_hw_attr_##fname = { \
	.attr = { .name = #fname, .mode = 0444 }, \
	.show = poc_hw_##fname##_show, \
}

DEFINE_POC_HW_ATTR(ctz, POC_CTZ64_NAME);
DEFINE_POC_HW_ATTR(ptselect, POC_PTSELECT_NAME);

static struct attribute *poc_counter_attrs[] = {
	&poc_attr_hit.attr,
	&poc_attr_fallthrough.attr,
	&poc_attr_sticky.attr,
	&poc_attr_llc_hit.attr,
#ifdef CONFIG_SCHED_SMT
	&poc_attr_smt_tgt.attr,
#endif
	&poc_attr_reset.attr,
	NULL,
};

static const struct attribute_group poc_counter_group = {
	.attrs = poc_counter_attrs,
};

static struct attribute *poc_hw_attrs[] = {
	&poc_hw_attr_ctz.attr,
	&poc_hw_attr_ptselect.attr,
	NULL,
};

static const struct attribute_group poc_hw_group = {
	.attrs = poc_hw_attrs,
};

static int __init sched_poc_debug_init(void)
{
	struct kobject *kobj_poc, *kobj_sel, *kobj_hw;
	int cpu, ret;

	kobj_poc = kobject_create_and_add("poc_selector", kernel_kobj);
	if (!kobj_poc)
		return -ENOMEM;

	ret = sysfs_create_group(kobj_poc, &poc_counter_group);
	if (ret)
		goto err_poc;

	kobj_sel = kobject_create_and_add("selected", kobj_poc);
	if (kobj_sel) {
		for_each_possible_cpu(cpu) {
			struct poc_selected_attr *sa;

			sa = kzalloc(sizeof(*sa), GFP_KERNEL);
			if (!sa)
				continue;
			sa->cpu = cpu;
			sa->kattr.attr.name = kasprintf(GFP_KERNEL, "cpu%d", cpu);
			if (!sa->kattr.attr.name) {
				kfree(sa);
				continue;
			}
			sa->kattr.attr.mode = 0444;
			sa->kattr.show = poc_selected_show;
			sysfs_attr_init(&sa->kattr.attr);
			ret = sysfs_create_file(kobj_sel, &sa->kattr.attr);
			if (ret) {
				kfree(sa->kattr.attr.name);
				kfree(sa);
			}
		}
	}

	kobj_hw = kobject_create_and_add("hw_accel", kobj_poc);
	if (kobj_hw) {
		ret = sysfs_create_group(kobj_hw, &poc_hw_group);
		if (ret)
			kobject_put(kobj_hw);
	}

	return 0;

err_poc:
	kobject_put(kobj_poc);
	return ret;
}
late_initcall(sched_poc_debug_init);

#endif /* CONFIG_SCHED_POC_SELECTOR_DEBUG */
#endif /* CONFIG_SCHED_POC_SELECTOR */

/*
 * ----------------------------------------------------------------------------
 * "THE BEER-WARE LICENSE" (Revision 42):
 * <phk@FreeBSD.org> wrote this file.  As long as you retain this notice you
 * can do whatever you want with this stuff. If we meet some day, and you think
 * this stuff is worth it, you can buy me a beer in return.   Poul-Henning Kamp
 * ----------------------------------------------------------------------------
 *
 * $Id: mplock.s,v 1.7 1997/07/13 00:19:24 smp Exp smp $
 *
 * Functions for locking between CPUs in a SMP system.
 *
 * This is an "exclusive counting semaphore".  This means that it can be
 * free (0xffffffff) or be owned by a CPU (0xXXYYYYYY where XX is CPU-id
 * and YYYYYY is the count).
 *
 * Contrary to most implementations around, this one is entirely atomic:
 * The attempt to seize/release the semaphore and the increment/decrement
 * is done in one atomic operation.  This way we are safe from all kinds
 * of weird reentrancy situations.
 * 
 */


#include "opt_ddb.h"
#include "assym.s"			/* system definitions */
#include <machine/specialreg.h>		/* x86 special registers */
#include <machine/asmacros.h>		/* miscellaneous asm macros */
#include <machine/smptests.h>		/** TEST_LOPRIO, TEST_CPUSTOP */
#ifdef TEST_CPUSTOP
#include <i386/isa/intr_machdep.h>
#endif
#include <machine/apic.h>


	.text
/***********************************************************************
 *  void MPgetlock(unsigned int *lock)
 *  ----------------------------------
 *  Destroys	%eax, %ecx and %edx.
 */

NON_GPROF_ENTRY(MPgetlock)
1:	movl	4(%esp), %edx		/* Get the address of the lock */
  	movl	(%edx), %eax		/* Try to see if we have it already */
	andl	$0x00ffffff, %eax	/* - get count */
	movl	_cpu_lockid, %ecx	/* - get pre-shifted logical cpu id */
	orl	%ecx, %eax		/* - combine them */
	movl	%eax, %ecx
	incl	%ecx			/* - new count is one more */
	lock
	cmpxchg	%ecx, (%edx)		/* - try it atomically */
	jne	2f			/* - miss */
	ret
2:	movl	$0xffffffff, %eax	/* Assume it's free */
	movl	_cpu_lockid, %ecx	/* - get pre-shifted logical cpu id */
	incl	%ecx			/* - new count is one */
	lock
	cmpxchg	%ecx, (%edx)		/* - try it atomically */
	jne	3f			/* ...do not collect $200 */
#if defined(TEST_LOPRIO)
	/* 1st acquire, claim LOW PRIO (ie, ALL INTerrupts) */
#ifdef TEST_CPUSTOP
#define TPR_STACKOFFSET		20(%esp)
	movl	TPR_STACKOFFSET, %eax	/* saved copy */
	andl	$0xffffff00, %eax	/* clear task priority field */
	movl	%eax, TPR_STACKOFFSET	/* 're-save' it */
#else
	movl	lapic_tpr, %eax		/* Task Priority Register */
	andl	$0xffffff00, %eax	/* clear task priority field */
	movl	%eax, lapic_tpr		/* set it */
#endif /** TEST_CPUSTOP */
#endif /** TEST_LOPRIO */
	ret
3:	cmpl	$0xffffffff, (%edx)	/* Wait for it to become free */
	jne	3b
	jmp	2b			/* XXX 1b ? */

/***********************************************************************
 *  int MPtrylock(unsigned int *lock)
 *  ---------------------------------
 *  Destroys	%eax, %ecx and %edx.
 *  Returns	1 if lock was successfull
 */

NON_GPROF_ENTRY(MPtrylock)
1:	movl	4(%esp), %edx		/* Get the address of the lock */
  	movl	(%edx), %eax		/* Try to see if we have it already */
	andl	$0x00ffffff, %eax	/* - get count */
	movl	_cpu_lockid, %ecx	/* - get pre-shifted logical cpu id */
	orl	%ecx, %eax		/* - combine them */
	movl	%eax, %ecx
	incl	%ecx			/* - new count is one more */
	lock
	cmpxchg	%ecx, (%edx)		/* - try it atomically */
	jne	2f			/* - miss */
	movl	$1, %eax
	ret
2:	movl	$0xffffffff, %eax	/* Assume it's free */
	movl	_cpu_lockid, %ecx	/* - get pre-shifted logical cpu id */
	incl	%ecx			/* - new count is one */
	lock
	cmpxchg	%ecx, (%edx)		/* - try it atomically */
	jne	3f			/* ...do not collect $200 */
	movl	$1, %eax
	ret
3:	movl	$0, %eax
	ret

/***********************************************************************
 *  void MPrellock(unsigned int *lock)
 *  ----------------------------------
 *  Destroys	%eax, %ecx and %edx.
 */

NON_GPROF_ENTRY(MPrellock)
1:	movl	4(%esp), %edx		/* Get the address of the lock */
  	movl	(%edx), %eax		/* - get the value */
	movl	%eax,%ecx
	decl	%ecx			/* - new count is one less */
	testl	$0x00ffffff, %ecx	/* - Unless it's zero... */
	jnz	2f
#if defined(TEST_LOPRIO)
	/* last release, give up LOW PRIO (ie, arbitrate INTerrupts) */
	movl	lapic_tpr, %eax		/* Task Priority Register */
	andl	$0xffffff00, %eax	/* clear task priority field */
	orl	$0x00000010, %eax	/* set task priority to 'arbitrate' */
	movl	%eax, lapic_tpr		/* set it */
  	movl	(%edx), %eax		/* - get the value AGAIN */
#endif /** TEST_LOPRIO */
	movl	$0xffffffff, %ecx	/* - In which case we release it */
2:	lock
	cmpxchg	%ecx, (%edx)		/* - try it atomically */
	jne	1b			/* ...do not collect $200 */
	ret

/***********************************************************************
 *  void get_mplock()
 *  -----------------
 *  All registers preserved
 *
 *  Stack (after call to _MPgetlock):
 *	
 *	&mp_lock	 4(%esp)
 *	edx		 8(%esp)
 *	ecx		12(%esp)
 *	EFLAGS		16(%esp)
 *	local APIC TPR	20(%esp)
 *	eax		24(%esp)
 */

NON_GPROF_ENTRY(get_mplock)
	pushl	%eax

#ifdef TEST_CPUSTOP
	movl	lapic_tpr, %eax		/* get current TPR */
	pushl	%eax			/* save current TPR */
	pushfl				/* save current EFLAGS */
	btl	$9, (%esp)		/* test EI bit */
	jc	1f			/* INTs currently enabled */
	andl	$0xffffff00, %eax	/* clear task priority field */
	orl	$TPR_BLOCK_HWI, %eax	/* only allow IPIs
	movl	%eax, lapic_tpr		/* set it */
	sti				/* allow IPI (and only IPI) INTS */
1:
#endif /* TEST_CPUSTOP */

	pushl	%ecx
	pushl	%edx
	pushl	$_mp_lock
	call	_MPgetlock
	add	$4, %esp
	popl	%edx
	popl	%ecx

#ifdef TEST_CPUSTOP
	popfl				/* restore original EFLAGS */
	popl	%eax			/* get original/modified TPR value */
	movl	%eax, lapic_tpr		/* restore TPR */
#endif /* TEST_CPUSTOP */

	popl	%eax
	ret

/***********************************************************************
 *  void try_mplock()
 *  -----------------
 *  reg %eax == 1 if success
 */

NON_GPROF_ENTRY(try_mplock)
	pushl	%ecx
	pushl	%edx
	pushl	$_mp_lock
	call	_MPtrylock
	add	$4, %esp
	popl	%edx
	popl	%ecx
	ret

/***********************************************************************
 *  void rel_mplock()
 *  -----------------
 *  All registers preserved
 */

NON_GPROF_ENTRY(rel_mplock)
	pushl	%eax

	pushl	%ecx
	pushl	%edx
	pushl	$_mp_lock
	call	_MPrellock
	add	$4, %esp
	popl	%edx
	popl	%ecx

	popl	%eax
	ret


	.data
	.globl _mp_lock
	.align  2	/* mp_lock SHALL be aligned on i386 */
_mp_lock:	.long	0		

/* cacheR5kALib.s - MIPS R5000 cache management assembly routines */

/* Copyright 1984-2001 Wind River Systems, Inc. */
	.data
	.globl  copyright_wind_river

/*
 * This file has been developed or significantly modified by the
 * MIPS Center of Excellence Dedicated Engineering Staff.
 * This notice is as per the MIPS Center of Excellence Master Partner
 * Agreement, do not remove this notice without checking first with
 * WR/Platforms MIPS Center of Excellence engineering management.
 */

/*
modification history
--------------------
01g,18jan02,agf  add explicit align directive to data section(s)
01f,16nov01,tlc  Reorder icache loops in reset routine.
01f,02aug01,mem  Diab integration
01e,16jul01,ros  add CofE comment
01d,14feb01,mem  Change cache reset to three step process.
01c,12feb01,sru  Adding HAZARD macros
01b,04jan01,tlc  Backport from Cirrus.
01a,08jul99,dra  Created this file based on cacheR4kALib.s.
*/
	
/*
DESCRIPTION
This library contains MIPS R5000 cache set-up and invalidation routines
written in assembly language.  The R5000 utilizes a variable-size
instruction and data cache that operates in write-back mode.  Cache
line size also varies. See also the manual entry for cacheR5kLib.

For general information about caching, see the manual entry for cacheLib.

INCLUDE FILES: cacheLib.h

SEE ALSO: cacheR5kLib, cacheLib
*/

#define _ASMLANGUAGE
#include "vxWorks.h"
#include "asm.h"

#define CFG_SE	0x00001000		/* Secondary cache enable */

/*
 * cacheop macro to automate cache operations
 * first some helpers...
 */
#define _mincache(size, maxsize) \
	bltu	size,maxsize,9f ;	\
	move	size,maxsize ;		\
9:

#define _align(minaddr, maxaddr, linesize) \
	.set noat ; \
	subu	AT,linesize,1 ;	\
	not	AT ;			\
	and	minaddr,AT ;		\
	addu	maxaddr,-1 ;		\
	and	maxaddr,AT ;		\
	.set at
	
/* general operations */

#define doop1(op1) \
	cache	op1,0(a0) ;		\
	HAZARD_CACHE
	
#define doop2(op1, op2) \
	cache	op1,0(a0) ;		\
	HAZARD_CACHE      ;		\
	cache	op2,0(a0) ;		\
	HAZARD_CACHE		

#define doop1lw(op1)			\
	lw	zero,0(a0)
	
#define doop1lw1(op1)			\
	cache	op1,0(a0) ;		\
	HAZARD_CACHE      ;		\
	lw	zero,0(a0);		\
	cache	op1,0(a0) ;		\
	HAZARD_CACHE      
	
#define doop121(op1,op2)		\
	cache	op1,0(a0) ;		\
	HAZARD_CACHE      ;		\
	cache	op2,0(a0) ;		\
	HAZARD_CACHE      ;		\
	cache	op1,0(a0) ;		\
	HAZARD_CACHE

#define _oploopn(minaddr, maxaddr, linesize, tag, ops) \
	.set	noreorder ;		\
10: 	doop##tag##ops ;	\
	bne     minaddr,maxaddr,10b ;	\
	add   	minaddr,linesize ;	\
	.set	reorder

/* finally the cache operation macros */
#define vcacheopn(kva, n, cacheSize, cacheLineSize, tag, ops) \
 	blez	n,11f ;			\
	addu	n,kva ;			\
	_align(kva, n, cacheLineSize) ; \
	_oploopn(kva, n, cacheLineSize, tag, ops) ; \
11:

#define icacheopn(kva, n, cacheSize, cacheLineSize, tag, ops) \
	_mincache(n, cacheSize);	\
 	blez	n,11f ;			\
	addu	n,kva ;			\
	_align(kva, n, cacheLineSize) ; \
	_oploopn(kva, n, cacheLineSize, tag, ops) ; \
11:

#define vcacheop(kva, n, cacheSize, cacheLineSize, op) \
	vcacheopn(kva, n, cacheSize, cacheLineSize, 1, (op))

#define icacheop(kva, n, cacheSize, cacheLineSize, op) \
	icacheopn(kva, n, cacheSize, cacheLineSize, 1, (op))

	.text

	.globl GTEXT(cacheR5kReset)		/* low level cache init */
	.globl GTEXT(cacheR5kRomTextUpdate)	/* cache-text-update */
	.globl GTEXT(cacheR5kDCFlushInvalidateAll)/* flush entire data cache */
	.globl GTEXT(cacheR5kDCFlushInvalidate) /* flush data cache locations */
	.globl GTEXT(cacheR5kICInvalidateAll)	/* invalidate entire inst cache */
	.globl GTEXT(cacheR5kICInvalidate)	/* invalidate inst. cache */
	.globl GTEXT(cacheR5kVirtPageFlush)	/* flush cache on MMU page unmap */
	.globl GTEXT(cacheR5kSync)		/* cache sync operation */

	.globl GDATA(cacheR5kDCacheSize)	/* data cache size */
	.globl GDATA(cacheR5kICacheSize)	/* inst. cache size */
	.globl GDATA(cacheR5kSCacheSize)	/* secondary cache size */

	.globl GDATA(cacheR5kDCacheLineSize)	/* data cache line size */
	.globl GDATA(cacheR5kICacheLineSize)	/* inst. cache line size */
	.globl GDATA(cacheR5kSCacheLineSize)	/* secondary cache line size */
	
	.data
	.align	4
cacheR5kICacheSize:
	.word	0
cacheR5kDCacheSize:
	.word	0
cacheR5kSCacheSize:
	.word	0
cacheR5kICacheLineSize:
	.word	0
cacheR5kDCacheLineSize:
	.word	0
cacheR5kSCacheLineSize:
	.word	0
	
	.text
	.set	reorder
/******************************************************************************
*
* cacheR5kReset - low level initialisation of the R5000 caches
*
* This routine initialises the R5000 caches to ensure that they
* have good parity.  It must be called by the ROM before any cached locations
* are used to prevent the possibility of data with bad parity being written to
* memory.
* To initialise the instruction cache it is essential that a source of data
* with good parity is available. If the initMem argument is set, this routine
* will initialise an area of memory starting at location zero to be used as
* a source of parity; otherwise it is assumed that memory has been
* initialised and already has good parity.
*
* RETURNS: N/A
*

* void cacheR5kReset (initMem)

*/
	.ent	cacheR5kReset
FUNC_LABEL(cacheR5kReset)
	/* disable all i/u and cache exceptions */
	mfc0	v0,C0_SR
	HAZARD_CP_READ
	or	v1,SR_DE
	mtc0	v1,C0_SR
	HAZARD_CP_WRITE

	/* disable secondary cache */
	mfc0	t6,C0_CONFIG
	HAZARD_CP_READ
	and	t7,t6,~CFG_SE
	mtc0	t7,C0_CONFIG
	
	/* set invalid tag */
	mtc0	zero,C0_TAGLO
	mtc0	zero,C0_TAGHI
	HAZARD_CACHE_TAG

	/*
	 * The caches are probably in an indeterminate state, so we force
	 * good parity into them by doing an invalidate, load/fill, 
	 * invalidate for each line.  We do an invalidate of each line in
	 * the cache before we perform any fills, because we need to 
	 * ensure that each way of an n-way associative cache is invalid
	 * before performing the first Fill_I cacheop.
	 */
	
	/* initialize icache tags */
	li	a0,K0BASE
	move	a2,t0		# icacheSize
	move	a3,t1		# icacheLineSize
	move	a1,a2
	icacheop(a0,a1,a2,a3,Index_Store_Tag_I)

	/* fill icache */
	li	a0,K0BASE
	move	a2,t0		# icacheSize
	move	a3,t1		# icacheLineSize
	move	a1,a2
	icacheop(a0,a1,a2,a3,Fill_I)

	/* clear icache tags */
	li	a0,K0BASE
	move	a2,t0		# icacheSize
	move	a3,t1		# icacheLineSize
	move	a1,a2
	icacheop(a0,a1,a2,a3,Index_Store_Tag_I)

	/* Initialize the data cache */
	li	a0,K0BASE
	move	a2,t2		# dcacheSize
	move	a3,t3		# dcacheLineSize
	move	a1,a2
	icacheop(a0,a1,a2,a3,Index_Store_Tag_D)

	li	a0,K0BASE
	move	a2,t2		# dcacheSize
	move	a3,t3		# dcacheLineSize
	move	a1,a2
	icacheopn(a0,a1,a2,a3,1lw,(dummy))

	/* 3: clear dcache tags */
	li	a0,K0BASE
	move	a2,t2		# dcacheSize
	move	a3,t3		# dcacheLineSize
	move	a1,a2
	icacheop(a0,a1,a2,a3,Index_Store_Tag_D)

	/* Enable secondary cache if originally enabled */
	mtc0	t6,C0_CONFIG
	HAZARD_CP_WRITE
	
	/* Unified I & D in S-Cache */
	
	blez	t4,99f
	li	a0,K0BASE
	move	a2,t4		# scacheSize
	move	a3,t5		# scacheLineSize
	move	a1,a2
	icacheopn(a0,a1,a2,a3,1lw1,(Index_Store_Tag_SD))
99:
	mtc0	v0,C0_SR
	HAZARD_CP_WRITE

	j	ra
	.end	cacheR5kReset

/******************************************************************************
*
* cacheR5kRomTextUpdate - cache text update like functionality from the bootApp
*
*	a0	i-cache size
*	a1	i-cache line size
*	a2	d-cache size
*	a3	d-cache line size
*
* RETURNS: N/A
*

* void cacheR5kRomTextUpdate ()

*/
	.ent	cacheR5kRomTextUpdate
FUNC_LABEL(cacheR5kRomTextUpdate)
	/* Save I-cache parameters */
	move	t0,a0
	move	t1,a1

	/* Check for primary data cache */
	blez	a2,99f

	/* Flush-invalidate primary data cache */
	li	a0,K0BASE
	move	a1,a2
	icacheop(a0,a1,a2,a3,Index_Writeback_Inv_D)
99:
	/* replace I-cache parameters */
	move	a2,t0
	move	a3,t1
	
	/* Check for primary instruction cache */
	blez	a0,99f
	
	/* Invalidate primary instruction cache */
	li	a0,K0BASE
	move	a1,a2
	icacheop(a0,a1,a2,a3,Index_Invalidate_I)
99:
	j	ra
	.end	cacheR5kRomTextUpdate

/******************************************************************************
*
* cacheR5kDCFlushInvalidateAll - flush entire R5000 data cache
*
* RETURNS: N/A
*

* void cacheR5kDCFlushInvalidateAll (void)

*/
	.ent	cacheR5kDCFlushInvalidateAll
FUNC_LABEL(cacheR5kDCFlushInvalidateAll)
	/* Check for primary data cache */
	lw	a2,cacheR5kDCacheSize
	blez	a2,1f

	/* Flush-invalidate primary data cache */
	lw	a3,cacheR5kDCacheLineSize
	li	a0,K0BASE
	move	a1,a2
	icacheop(a0,a1,a2,a3,Index_Writeback_Inv_D)
	
	/* Check for secondary cache */	
1:	lw	a2,cacheR5kSCacheSize
	blez	a2,99f

	/* Flush-invalidate secondary cache */
	mtc0	zero,C0_TAGLO
	mtc0	zero,C0_TAGHI
	HAZARD_CACHE_TAG
	
	lw	a3,cacheR5kSCacheLineSize
	li	a0,K0BASE
	move	a1,a2
	icacheop(a0,a1,a2,a3,Index_Store_Tag_SD)

99:	j	ra
	.end	cacheR5kDCFlushInvalidateAll

/******************************************************************************
*
* cacheR5kDCFlushInvalidate - flush R5000 data cache locations
*
* RETURNS: N/A
*

* void cacheR5kDCFlushInvalidate
*     (
*     baseAddr,		/@ virtual address @/
*     byteCount		/@ number of bytes to invalidate @/
*     )

*/
	.ent	cacheR5kDCFlushInvalidate
FUNC_LABEL(cacheR5kDCFlushInvalidate)
	/* Save parameters */
	move	t0,a0
	move	t1,a1

	/* Check for primary data cache */
	lw	a2,cacheR5kDCacheSize
	blez	a2,1f

	/* Flush-invalidate primary data cache */
	lw	a3,cacheR5kDCacheLineSize
	vcacheop(a0,a1,a2,a3,Hit_Writeback_Inv_D)

1:	/* Check for secondary cache */
	lw	a2,cacheR5kSCacheSize
	blez	a2,99f
	
	/* Flush-invalidate secondary cache */
	mtc0	zero,C0_TAGLO
	mtc0	zero,C0_TAGHI
	HAZARD_CACHE_TAG

	move	a0,t0
	move	a1,t1		
	lw	a3,cacheR5kSCacheLineSize
	icacheop(a0,a1,a2,a3,Index_Store_Tag_SD)

99:	j	ra
	.end	cacheR5kDCFlushInvalidate

/******************************************************************************
*
* cacheR5kICInvalidateAll - invalidate entire R5000 instruction cache
*
* RETURNS: N/A
*

* void cacheR5kICInvalidateAll (void)

*/
	.ent	cacheR5kICInvalidateAll
FUNC_LABEL(cacheR5kICInvalidateAll)
	/* Check for primary instruction cache */
	lw	a2,cacheR5kICacheSize
	blez	a2,1f

	/* Invalidate primary instruction cache */
	lw	a3,cacheR5kICacheLineSize
	li	a0,K0BASE
	move	a1,a2
	icacheop(a0,a1,a2,a3,Index_Invalidate_I)

1:	/* Check for secondary cache */	
	lw	a2,cacheR5kSCacheSize
	blez	a2,99f

	/* Invalidate secondary cache */
	mtc0	zero,C0_TAGLO
	mtc0	zero,C0_TAGHI
	HAZARD_CACHE_TAG
	
	lw	a3,cacheR5kSCacheLineSize
	li	a0,K0BASE
	move	a1,a2
	icacheop(a0,a1,a2,a3,Index_Store_Tag_SD)

99:	j	ra

	.end	cacheR5kICInvalidateAll

/******************************************************************************
*
* cacheR5kICInvalidate - invalidate R5000 instruction cache locations
*
* RETURNS: N/A
*

* void cacheR5kICInvalidate
*     (
*     baseAddr,		/@ virtual address @/
*     byteCount		/@ number of bytes to invalidate @/
*     )

*/
	.ent	cacheR5kICInvalidate
FUNC_LABEL(cacheR5kICInvalidate)
	/* Save parameters */
	move	t0,a0
	move	t1,a1
	
	/* Check for primary instruction cache */
	lw	a2,cacheR5kICacheSize
	blez	a2,1f

	/* Invalidate primary instruction cache */
	lw	a3,cacheR5kICacheLineSize
	vcacheop(a0,a1,a2,a3,Hit_Invalidate_I)

1:	/* Check for secondary cache */
	lw	a2,cacheR5kSCacheSize
	blez	a2,99f
	
	/* Invalidate secondary cache */
	mtc0	zero,C0_TAGLO
	mtc0	zero,C0_TAGHI
	HAZARD_CACHE_TAG

	move	a0,t0
	move	a1,t1
	lw	a3,cacheR5kSCacheLineSize
	icacheop(a0,a1,a2,a3,Index_Store_Tag_SD)

99:	j	ra
	.end	cacheR5kICInvalidate
	

/******************************************************************************
*
* cacheR5kVirtPageFlush - flush one page of virtual addresses from caches
*
* Change ASID, flush the appropriate cache lines from the D- and I-cache,
* and restore the original ASID.
*
* CAVEAT: This routine and the routines it calls MAY be running to clear
* cache for an ASID which is only partially mapped by the MMU. For that
* reason, the caller may want to lock interrupts.
*
* RETURNS: N/A
*
* void cacheR5kVirtPageFlush (UINT asid, void *vAddr, UINT pageSize);
*/
	.ent	cacheR5kVirtPageFlush
FUNC_LABEL(cacheR5kVirtPageFlush)
	/* Save parameters */
	move	t4,a0			/* ASID to flush */
	move	t0,a1			/* beginning VA */
	move	t1,a2			/* length */

	/*
	 * When we change ASIDs, our stack might get unmapped,
	 * so use the stack now to free up some registers for use:
	 *	t0 - virtual base address of page to flush
	 *	t1 - page size
	 *	t2 - original SR
	 *	t3 - original ASID
	 *	t4 - ASID to flush
	 */

	/* lock interrupts */

	mfc0	t2, C0_SR
	HAZARD_CP_READ
	li	t3, ~SR_INT_ENABLE
	and	t3, t2
	mtc0	t3, C0_SR
	HAZARD_INTERRUPT

	/* change the current ASID to context where page is mapped */

	mfc0	t3, C0_TLBHI		/* read current TLBHI */
	HAZARD_CP_READ
	and	t3, 0xff		/* extract ASID field */
	beq	t3, t4, 0f		/* branch if no need to change */
	mtc0	t4, C0_TLBHI		/* Store new EntryHi  */	
	HAZARD_TLB
0:
	/* clear the virtual addresses from D- and I-caches */
	
	lw	a2,cacheR5kDCacheSize
	blez	a2,1f

	/* Flush-invalidate primary data cache */
	move	a0, t0
	move	a1, t1
	lw	a3,cacheR5kDCacheLineSize
	vcacheop(a0,a1,a2,a3,Hit_Writeback_Inv_D)
1:
	lw	a2,cacheR5kICacheSize
	blez	a2,1f	

	/* Invalidate primary instruction cache */
	move	a0,t0
	move	a1,t1
	lw	a3,cacheR5kICacheLineSize
	vcacheop(a0,a1,a2,a3,Hit_Invalidate_I)
1:	
	/* restore the original ASID */

	mtc0	t3, C0_TLBHI		/* Restore old EntryHi  */	
	HAZARD_TLB

	mtc0	t2, C0_SR		/* restore interrupts */
	
	j	ra
	.end	cacheR5kVirtPageFlush

/******************************************************************************
*
* cacheR5kSync - sync region of memory through all caches
*
* RETURNS: N/A
*
* void cacheR5kSync (void *vAddr, UINT pageSize);
*/
	.ent	cacheR5kSync
FUNC_LABEL(cacheR5kSync)
	/* Save parameters */
	move	t0,a0			/* beginning VA */
	move	t1,a1			/* length */

	/* lock interrupts */

	mfc0	t2, C0_SR
	HAZARD_CP_READ
	li	t3, ~SR_INT_ENABLE
	and	t3, t2
	mtc0	t3, C0_SR
	HAZARD_INTERRUPT

	/*
	 * starting with primary caches, push the memory
	 * block out completely
	 */
	sync

	lw	a2,cacheR5kICacheSize
	blez	a2,1f	

	/* Invalidate primary instruction cache */
	move	a0,t0
	move	a1,t1
	lw	a3,cacheR5kICacheLineSize
	vcacheop(a0,a1,a2,a3,Hit_Invalidate_I)
1:
	lw	a2,cacheR5kDCacheSize
	blez	a2,1f

	/* Flush-invalidate primary data cache */
	move	a0, t0
	move	a1, t1
	lw	a3,cacheR5kDCacheLineSize
	vcacheop(a0,a1,a2,a3,Hit_Writeback_Inv_D)
1:	
	lw	a2,cacheR5kSCacheSize
	blez	a2,1f

	/* Invalidate secondary cache */
	mtc0	zero,C0_TAGLO
	mtc0	zero,C0_TAGHI
	HAZARD_CACHE_TAG

	move	a0,t0
	move	a1,t1
	lw	a3,cacheR5kSCacheLineSize
	icacheop(a0,a1,a2,a3,Index_Store_Tag_SD)
1:
	mtc0	t2, C0_SR		/* restore interrupts */
	
	j	ra
	.end	cacheR5kSync

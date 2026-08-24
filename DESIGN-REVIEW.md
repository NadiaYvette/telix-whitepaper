# Telix Design Review — Vulnerabilities to Critique

This document records the design positions in the Telix whitepaper that a
hostile or expert reviewer is most likely to attack. It is not part of the
whitepaper itself; it is a working note of the soft spots, intended to be
resolved either by defending the position in the paper or by changing the
design. Each item is stated as the *strongest form* of the objection a
reviewer would raise, followed by what it would take to answer it.

---

## 1. The framekernel boundary is asserted, not established

**The objection.** The whitepaper's central isolation claim is that thin,
performance-critical server layers can share a single kernel address space
protected only by Rust's type system, while everything else stays in
MMU-isolated processes. No prior system has demonstrated that a
*safe-language* boundary between mutually distrusting components inside one
address space is sound in the hostile, interrupt-driven, `unsafe`-pervasive
environment of a kernel. Asterinas made the whole system safe-language;
seL4 made everything MMU-isolated. Telix claims the middle point is
*viable* and *cheap* without evidence.

**The load-bearing fact.** The paper already admits this is "the least
validated layer" and offers a degradation path to a pure microkernel. But
the degradation claim itself is unverified: if the framekernel boundary is
unsound, the *rest* of the architecture (page clustering, CPS, capability
transports) is claimed not to depend on it — yet the external pager, the
LLFree allocator, and the shootdown protocol are all *specified* as living
inside the framekernel. Whether they can be moved out without redesign is
itself unproven.

**What would answer it.** Either (a) a small proof-of-concept
demonstrating the framekernel/pager boundary in Rust under the stated
threat model, or (b) a precise statement of which framekernel-resident
components are load-bearing for the safe-language argument and which are
there only for latency, with the latter demonstrated to be movable.

## 2. No empirical validation anywhere in the design

**The objection.** The paper proposes an unusually large set of
simultaneous innovations — morsel allocator, external pagers, M:N
stackless futures, framekernel, inverted page tables, capability
transports, personality servers, cluster transparency — and provides no
measurements, no prototype results, and only one provisional
empirical data point (256 KiB clustering "tolerable without mitigation",
attributed to "provisional empirical results" with no citation). Every
individual mechanism is plausible; the *combination* is unvalidated.

**The load-bearing fact.** Several claims are quantitative (TLB reach
expansion, sublinear metadata, fault latency reduction, migration cost
`O(1)`) and are currently asserted analytically. The distributional
argument for page clustering (the unimodal Z-attractor) is presented as
"empirical" but is, so far, a *prediction*, not a measurement.

**What would answer it.** Label the distributional claim as a hypothesis
to be tested; commit to a concrete evaluation plan (which workloads, which
hardware, which baseline kernels, which metrics); and avoid the word
"empirical" for anything not yet measured.

## 3. The verification-to-implementation gap

**The objection.** The verification chapter presents a four-layer stack
ending in RefinedRust proofs of kernel code. But RefinedRust has not been
applied to bare-metal kernel code: no `std`, raw MMIO, inline assembly
(`sfence.vma`, `mret`), a custom allocator, and interrupt-driven state
machines. The paper itself admits this ("not yet tested on bare-metal
kernel code") but then relies on it as the *completion* of the
verification story. The gap between "the hardware model is proven" and
"the kernel is proven" is the entire research problem, not a footnote.

**The load-bearing fact.** Tessera's hardware proofs are real and
impressive; the machine-interface Iris layer is described but is
*not yet built* (it is "a well-scoped engineering effort"). The claim
"both sides already speak Iris" is true but does not remove the need to
actually define `pte_token`/`tlb_flushed`/`iommu_mapping` and prove the
kernel sound against them.

**What would answer it.** Separate the *achieved* (Tessera hardware
theorems) from the *proposed* (RefinedRust kernel proofs) more sharply,
and commit to a first milestone that closes even one kernel function
end-to-end (e.g., `unmap_range`) as the existence proof.

## 4. Stackless-futures-everywhere is an extreme position

**The objection.** The design commits the *entire* system — kernel
executors, drivers, filesystems, network stacks, and user tasks — to
stackless `Future` state machines. This buys serializable migration
(Chapter on Clustering) at the cost of a programming model that the paper
itself repeatedly calls a "burden." The scheduler chapter's history of
revisions (cooperative-only → Carrier A → Carrier B) shows the design
kept discovering that stacklessness gives up preemption, and patching it
with stack carriers. A reviewer will ask whether the migration benefit —
which requires serializing *the anonymous state machine*, something Rust
does not currently support reflection over — is real enough to justify
the cost, or whether it is a speculative bet on a language feature.

**The load-bearing fact.** Rust does not provide a way to serialize an
arbitrary `Future`'s internal state. The clustering chapter asserts
"the state machine structure is serialized" without naming the mechanism
(serde derive? a custom runtime? compiler support?). Until the mechanism
exists, `O(1)` migration is aspirational.

**What would answer it.** Name the serialization mechanism and its
limitations (e.g., which futures are migratable), or soften the migration
claim to "bounded state, migratable futures only."

## 5. The page-clustering guarantee is real but narrow

**The objection.** The strongest, most rigorously-stated claim — "Z-sized
physical allocations never fail due to external fragmentation" — is
structurally correct (an extent allocator has no sub-Z unit to fragment
Z). But a reviewer will point out it is *almost tautological*: it is the
definition of "Z is the allocation unit." The interesting claims are the
consequences (guaranteed small superpages, TLB-reach expansion,
elimination of compaction), and those depend on the *demand distribution*,
the *replacement policy*, and the *availability of pinned frames* — none
of which the guarantee covers. The guarantee eliminates one failure mode;
it does not deliver superpages.

**The load-bearing fact.** The distributional argument (unimodal
Z-attractor) is the real payoff, and it is currently a hypothesis, not a
result (see §2).

**What would answer it.** Keep the guarantee precisely scoped (as it now
is), and state plainly that the *performance* benefit is a hypothesis to
be measured, not a theorem.

## 6. No security model / threat model

**The objection.** A paper that markets "formal verification for security
à la seL4" and "hardware-enforced isolation" never states: who is the
adversary, what are the trusted components, what is the TCB, and what
class of attacks (memory safety, privilege escalation, side-channel,
covert-channel, physical) is in or out of scope. "Security" is used
promiscuously to mean "memory safety," "isolation," and "formal
correctness" interchangeably. This is the single most likely
first-question from any security reviewer.

**What would answer it.** A threat-model section (see the security
chapter added alongside this document) that decomposes the TCB, names the
adversary model, and states the residual risks (notably side channels and
covert channels, which no amount of Rust safety addresses).

## 7. The cluster story is thin relative to its prominence

**The objection.** Clustering is a headline feature (PAN, SSI, NORMA
avoidance, transparent socket migration, process migration), but the
chapter is short and the mechanisms are sketched: "capability-indexed
CRDT namespace," "lease-based mutation," "socket state machines migrate."
The distributed-systems hard parts — CAP tradeoffs, consistency of the
CRDT namespace under partition, lease recovery, migration of *in-flight*
state under failure — are asserted, not designed. The whitepaper
hand-waves the one thing distributed-systems reviewers always probe:
failure semantics.

**What would answer it.** A failure model (what happens when a node
dies mid-lease, mid-migration, mid-CRDT-merge) and a statement of the
consistency guarantee actually offered (eventual? per-object linearizable?
lease-bounded?).

## 8. No comparison to the systems it claims to supersede

**The objection.** The paper cites seL4, Asterinas, Barrelfish, Mach, L4,
Singularity, Zircon, and OpenHarmony as influences, but never does the
comparative analysis a positioning paper needs: why is Telix *not* an
incremental extension of Theseus or Redox (both already Rust kernels) or
a configuration of seL4 with a userspace pager (which already exists)?
A reviewer will ask "what is actually new here, and why not build on X?"

**What would answer it.** A comparisons section (see the chapter added
alongside this document) that locates Telix in the design space against
seL4, Zircon, Redox, Theseus, RedLeaf, and Asterinas.

## 9. The M:N / scheduler-activation revival carries a burden of proof

**The objection.** Scheduler activations (Anderson et al., 1991) were
abandoned in practice because the upcall machinery and the kernel/user
scheduler coordination were found to be fragile and complex. Telix
revives the idea (as "streamlined, Nemesis/K42-style upcalls") on top of
stackless futures. The claim that stackless futures *solve* the
scheduler-activation trap (kernel-blindness, lost-wakeup, preemption)
needs to be demonstrated, not asserted. The scheduler chapter's own
evolution (adding stack carriers to recover preemption) is evidence the
problem is not fully solved by stacklessness alone.

**What would answer it.** A precise statement of how the classic
scheduler-activation failure modes (a blocking syscall stalling M-1
threads; preemption of a compute-bound thread) are each addressed, which
the two-execution-domain model now attempts but which has not been
validated.

## 10. Dependence on Rust's type system for *kernel* isolation is unexamined

**The objection.** The framekernel isolation argument rests on Rust
memory safety holding in kernel code. But kernel code is precisely where
the Rust model is most stressed: `unsafe` is pervasive (MMIO, raw page
tables, assembly), the aliasing model must be reconciled with
memory-mapped device registers and DMA, and the std-less allocator and
interrupt model are outside the language's normal guarantees. RustBelt
proved soundness for a *model* of Rust; it did not prove the kernel
programmer's `unsafe` blocks are correct. The verification story
(RefinedRust) is the only thing that would close this, and it is
proposed, not done (see §3).

**What would answer it.** Bound the `unsafe` surface, and state that
isolation claims are conditional on either RefinedRust proofs or CHERI
hardware, not on Rust alone.

---

## Summary of priority

| # | Vulnerability | Severity | Fix difficulty |
|---|--------------|----------|----------------|
| 6 | No threat model | High | Low (write it) |
| 8 | No comparisons | High | Low (write it) |
| 2 | No empirical validation | High | Medium (commit to a plan) |
| 1 | Framekernel boundary asserted | High | High (needs evidence) |
| 3 | Verification-implementation gap | High | High (needs a proof) |
| 4 | Stackless-futures extreme | Medium | Medium (name the mechanism) |
| 10 | Rust-for-isolation unexamined | Medium | Medium (bound `unsafe`) |
| 9 | M:N revival burden | Medium | Medium (address failure modes) |
| 5 | Clustering guarantee narrow | Medium | Low (rescore) |
| 7 | Cluster story thin | Medium | Medium (failure model) |

Items 6 and 8 are addressed by the two chapters added alongside this
document; the rest remain open and are candidates for author response.

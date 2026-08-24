# Telix Design Review — Vulnerabilities to Critique

This document records the design positions in the Telix whitepaper that a
hostile or expert reviewer is most likely to attack. It is not part of the
whitepaper itself; it is a working note of the soft spots, intended to be
resolved either by defending the position in the paper or by changing the
design. Each item is stated as the *strongest form* of the objection a
reviewer would raise, followed by what it would take to answer it.

## Changes since initial draft

- **#6 (no threat model): Addressed** by the Security chapter
  (`ch:security`, commit `f47d526`).  An adversary model, TCB
  decomposition, isolation primitives, the degradation path, and
  explicit side/covert-channel non-claims are now in the whitepaper.
  Severity: High → Low (remaining gap: whether the claims table
  survives a security reviewer's scrutiny).
- **#8 (no comparisons): Addressed** by the Comparison chapter
  (`ch:comparison`, commit `f47d526`).  A design-space table, seven
  contemporary systems, "why not build on X?" answers, and a list of
  five actually-novel claims are now in the whitepaper.
  Severity: High → Low (remaining gap: whether the five claims hold
  under expert review).
- **#2 (no empirical validation): Decided.** Correctness is the
  verification track's domain; empirical validation is about
  performance.  Three tiers: inherited (cite prior work), page
  clustering (Telix's core performance hypothesis), compositional
  (the combination burden).  Whitepaper relabelled the distribution
  argument "Predicted (Hypothesis)" (commit `ecb0929`, `460e3cb`).
- **#3 (verification-implementation gap): Decided.** Full framekernel
  core, manual Iris heap\_lang (not RefinedRust), assembly specs
  specialised from Sail, layer-by-layer delivery (commit `d8ed2e4`).
  The remaining work is engineering, not research.

**Open count: 6 of 10 remain** (#1, #4, #5, #7, #9, #10).

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

This issue is paired with **#10 (Rust-for-isolation unexamined)**, which
is the same problem from the language-safety side: the framekernel's
`unsafe` surface is unquantified, and the isolation claim is conditional
on either proofs or CHERI hardware.

### Detailed breakdown

#### 1a. What we know from prior work

- **Asterinas** proved that Rust safety can enforce isolation within a
  single kernel address space *when the whole system is in Rust and the
  `unsafe` surface is bounded and audited.*
- **RedLeaf** (OSDI 2020) proved that Rust safety can isolate *device
  drivers* within one address space without per-driver MMU domains.
- **seL4** proved that MMU-based isolation can be machine-checked
  end-to-end for a whole kernel.
- **RustBelt** (POPL 2018) proved that Rust's type system is sound in a
  formal model.

What prior work does *not* give us: a proof or even a demonstration that
a *hybrid* boundary (Rust-safe inside, MMU outside) is sound in the
hostile, interrupt-driven, `unsafe`-pervasive kernel environment.

#### 1b. What the framekernel boundary actually isolates

The framekernel contains these components (from the control-plane and
security chapters):

| Component | Why it's in the framekernel | Movable? |
|-----------|----------------------------|----------|
| Page-table manipulation | Latency-critical; every page fault touches this | Hard — every fault crosses a new MMU boundary if moved |
| Shared page-table management | Reference-counts, clones, and replicates shared PTE subtrees across address spaces; this is a deliberate violation of the usual "address spaces are disjoint" assumption (per ko03.bib, §Extent-Driven Page Table Sharing) and requires privileged access to the hardware page-table structures | Hard — sharing/replication manipulate hardware PTEs and must be atomic with respect to the shootdown protocol |
| TLB shootdown / IPI | Latency-critical; runs in interrupt context | Hard — IPI delivery is inherently kernel-side |
| IOMMU management | Binds DMA windows; must be privileged | Hard — IOMMU is a privileged hardware resource |
| LLFree allocator | Provisions physical frames on every allocation | Medium — allocator could be a separate server with a ring protocol |
| Scheduler management loop | Selects next future; runs in the executor | Medium — scheduler could be a separate server |

The list is not exhaustive: architectural features that violate
simplifying assumptions about the address space — notably shared page
tables — require correspondingly richer privileged operations in the
framekernel.  Shared-page-table management (reference counting,
clone-on-write for shared nodes, replication of hot nodes) is as
load-bearing as the basic PTE read/write path, because it manipulates
the same hardware structures and must be coordinated with the same
shootdown protocol.

#### 1c. The `unsafe` surface

The Rust-for-isolation concern (#10) is the same problem from the
other side. The framekernel's `unsafe` blocks are not yet audited or
counted. They include:

- MMIO reads/writes to device registers
- Page-table walks that dereference raw physical addresses
- Inline assembly (`sfence.vma`, `mret`, `csrw satp`)
- Interrupt entry/exit (saving/restoring registers)
- LLFree's in-band metadata within free frames

Each `unsafe` block is a point where the Rust type system's guarantees
are suspended and the programmer asserts correctness. The isolation
claim depends on the correctness of every one of these assertions.

#### 1d. What the author must decide

1. **Which components are load-bearing, and is the list exhaustive?**
   The page-table manipulator, shared-page-table manager, shootdown
   handler, and IOMMU manager cannot leave the framekernel — they
   are privileged hardware operations.  The author additionally
   notes that any architectural feature that violates simplifying
   assumptions (such as the shared-page-table plan, which violates
   the "address spaces are disjoint" assumption) may add further
   load-bearing components to the framekernel with correspondingly
   richer APIs.  Is there anything beyond shared page tables that
   falls into this category?

2. **Is the degradation claim scoped honestly?** The current
   whitepaper says "if the boundary is unsound, Telix degrades
   gracefully to a pure microkernel." But the privileged set
   (page-table, shared-PT, shootdown, IOMMU) cannot be degraded.
   Should the claim be narrowed to "the allocator and scheduler
   can be promoted to servers; the privileged set stays in the
   kernel and its isolation is hardware-enforced"?

3. **What is the `unsafe` surface, quantitatively?** Has anyone
   counted the `unsafe` blocks in the framekernel core? A number
   (e.g., "~200 `unsafe` blocks, each auditable by hand") is far
   more defensible than silence.

4. **Is the isolation claim conditional?** The current wording
   implies Rust safety is sufficient. A more honest formulation:
   "The framekernel's language-level isolation is conditional on
   either (a) RefinedRust/manual-Iris proofs of every `unsafe`
   block, or (b) CHERI hardware enforcing the same bounds in
   silicon. Until one of those is true, the design relies on MMU
   isolation for the privileged triad and on Rust safety as an
   additional, not a primary, boundary."

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

**Status (2026-08-24).** The author draws a crucial distinction:

- **Correctness** is the domain of formal verification (Tessera hardware
  proofs, manual Iris kernel proofs) and does not require empirical
  validation.  A machine-checked proof is its own validation.
- **Performance** is the domain of empirical evaluation: whether page
  clustering actually shifts the distribution and increases TLB reach,
  whether the framekernel boundary actually reduces context-switch cost,
  whether the combination of mechanisms delivers the promised
  throughput and latency.

The empirical validation burden is therefore about performance, not
correctness, and decomposes into three tiers:

1. **Inherited from prior publication.** Many individual mechanisms
   carry their own performance evidence: LLFree (Litz et al. on
   lock-free allocator latency), superpageblocks (van Riel's 40-patch
   series with production measurements), scheduler activations
   (Anderson et al. benchmarks), FlexSC/io\_uring (Soares & Axboe
   throughput results), page clustering (Dickins' 64 GiB x86 boot, the
   22-architecture ports).  These are *cited*, not re-validated.

2. **Page clustering (Telix's core performance hypothesis).** The
   Z-attractor distributional claim, the TLB-reach expansion argument,
   and the dense-spectra allocation behaviour are the genuinely
   unmeasured pieces.  These are the motivating performance hypotheses
   of the Telix project and are properly scoped as its core evaluation.

3. **Compositional performance (must validate).** The *combination* of
   mechanisms may exhibit emergent behaviours (contention, interference,
   pathological cascades) that no individual paper measured.  This is
   the performance burden any system combining novel components bears,
   and it belongs to Telix's evaluation scope.

**What was done (commit `ecb0929`).** The whitepaper's page-clustering
distribution section was relabelled "Predicted Effect (Hypothesis)," all
instances of "empirical" were replaced with "expected"/"predicted," the
256 KiB observation was re-anchored to the Dickins citation, and a
closing paragraph lists inherited validations and states the
compositional burden explicitly.

**What remains.** A concrete evaluation plan — which workloads, which
hardware, which baseline kernels, which metrics — is not yet in the
whitepaper.  That is the next step if this issue is to be fully closed.

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

### Detailed breakdown

This is the highest-cost-to-close item and the one where the design
choices are most consequential.  Here is every piece of it, stated
concretely enough to make a decision about scope.

#### 3a. What the Tessera hardware proofs actually give us

The Tessera proofs are already done and machine-checked:

| Theorem | File | What it proves |
|---------|------|----------------|
| PTE root-entry removal | `coherence.v` | Dropping a level-2 PTE faults the walk at level 2 |
| PTE leaf-entry removal | `coherence.v` | Same for level-0; invalidation at any radix level prevents translation |
| N-core broadcast under SC | `shootdown.v` | Sequential-consistency functional shootdown correctness |
| N-core broadcast under gpfsl/iRC11 | `shootdown_weak_broadcast.v` | The release/acquire protocol is sufficient without sequential consistency |
| IPI inbox model | `shootdown_weak_broadcast.v` (S2.3/S2.4) | Ghost-step correspondence: leader ack = `receive_ipi (deliver_ipi _ i)` |
| IOMMU coherence (VT-d) | `iommu_proofs.v` | IOTLB ⊆ mapping before/after invalidation |
| IOMMU coherence (SMMUv3) | `smmu_proofs.v` | Same for Arm SMMU with STE/CD/two-stage |
| IOMMU coherence (AMD-Vi) | `amdvi_proofs.v` | Same for AMD DTE/PASID cache |
| Device models (INTC, timer, UART, NIC, disk) | `intc_proofs.v`, `timer_proofs.v`, etc. | Test-vector-level properties |
| Upstream conformance bridge | `conformance.v` | Hand-transcribed walk = upstream sail-riscv `pt_walk` |
| Multi-arch replay | various | MIPS PageGrain 1KiB, LoongArch odd/even pairs, AArch64 block+contpte+LPA2 |

What these give us: a *machine model* with *proved invariants* about
coherence, shootdown, IOMMU integrity, and MMU conformance.  The proofs
say "if the kernel follows this protocol (invalidate PTE → local flush →
IPI → wait for acks → IOTLB invalidate), then coherence holds."

What they do *not* give us: any statement about actual kernel code.
The `bc_broadcast_spec` theorem is about an *abstract program* expressed
directly in the gpfsl language, not about a Rust function.

#### 3b. The pieces that need to be built

The gap has four discrete parts, ordered by increasing difficulty:

**B1. Machine interface Iris resources (~500–1,000 lines of Rocq).**
Define `pte_token`, `tlb_flushed`, `iommu_mapping`, `shared_subtree` as
Iris resources with accessor lemmas and soundness proofs against the
generated `machine.v`.  This is the bridge: the kernel holds
`pte_token(va, pa, perm)` iff the hardware model's radix walk from satp
through the actual page table gives that PTE at va; the kernel has
`tlb_flushed(va)` iff the gpfsl broadcast theorem says no core's TLB
contains va.

Status: *designed but not written*.  The verification chapter has the
signatures; the proofs against `machine.v` are straightforward (the
hardware invariants already exist, this is just repackaging them as Iris
resources).  This is the "well-scoped engineering effort" — genuinely
well-scoped, but also genuinely work (~3–4 weeks for someone fluent in
Iris).

**B2. Kernel Rust → Coq translation (~uncertain, depends on tool).**
RefinedRust takes Rust MIR and produces a Coq representation.  It has
been demonstrated on Rust libraries (`std::Vec`, `HashMap`, `Arc`) and on
verified OS components (the RefinedRust paper verified parts of the
Redox kernel's `unsafe` code).  It has *not* been demonstrated on:

- Code without `std` (Telix uses `#![no_std]`)
- Code with inline assembly (`sfence.vma`, `mret`)
- Code with MMIO (volatile reads/writes to device registers)
- Code using a custom allocator (LLFree instead of `std::alloc`)
- Code in an interrupt context (entry/exit not through `fn main()`)

The question: how much of RefinedRust's MIR→Coq pipeline works unchanged
in this environment, and how much needs new frontend support?  This is
the same category of problem as adapting RefinedRust to Redox, which the
paper's authors have expressed interest in but not yet published.

**B3. Proving the kernel satisfies the machine interface (~2,000–4,000
lines of Rocq).**  For each framekernel core function (PTE write, TLB
flush, IPI send, IPI receive, IOMMU map/unmap), prove an Iris triple
that the function respects the machine interface resources.  For example:

```
Lemma wp_unmap_range (va : vaddr) :
  {{{ pte_token va pa perm ∗ tlb_entry va }}}
    unmap_range va
  {{{ RET (); tlb_flushed va ∗ ¬ pte_token va pa perm }}}.
```

The proof composes the hardware theorems (`coherence_leaf` says PTE
invalidation works; `bc_broadcast_spec` says the IPI protocol works;
`iommu_shootdown_correct` says IOTLB invalidation works) with the
assertion that the Rust code *actually does those operations in the right
order*.  This is the part that is the kernel verification; it is
substantial but bounded (the framekernel core is ~3,000–5,000 lines of
Rust, and not all of it is protocol-relevant).

**B4. Assembly and MMIO soundness (~500 lines of Rocq).** Define axioms
or specifications for the privileged instructions and MMIO operations the
kernel uses: `sfence.vma`, `mret`, `csrw satp`, interrupt entry/exit,
volatile device reads/writes.  These are the primitives B3's proofs
"bottom out" on.  They cannot be proven in the same sense that pure Rust
code can (they are hardware operations), but they must be *specified*
with a semantics consistent with the Sail machine model, and their
specifications become the axioms of the kernel proof.

This is the same problem seL4 faced with its ARM/x86 assembly
specifications, and the same solution applies: write a trusted
specification ("this assembly sequence does X to the machine state"),
prove everything else, and audit the specification by hand.

#### 3c. Design decisions made (2026-08-24)

The author has made four concrete scope decisions:

1. **Scope: full framekernel core.** The target is the complete
   framekernel innermost layer — page-table manipulation, IPI, IOMMU,
   scheduler management loop, and LLFree allocator.  The rationale is
   that the verification exists to address the vulnerability class
   identified by Mythos et al., and a partial core is insufficient.
   "Everything needs to be verified."

2. **Toolchain: manual Iris heap_lang, not RefinedRust.**  The scope is
   already vast; adding the risk of adapting an untested-on-bare-metal
   MIR→Coq pipeline is not worth it.  The kernel spec will be written
   *manually* in Iris heap_lang, as seL4 did in Isabelle.  This is
   slower per function but eliminates all toolchain risk and the
   `#![no_std]`/assembly/MMIO compatibility problem entirely.

3. **Assembly specification: specialised from Sail.**  The privileged
   instructions (`sfence.vma`, `mret`, `csrw satp`, interrupt entry/exit)
   will not be independently axiomatised.  Their specifications will be
   *specialisations* of the existing Sail machine model's executable
   semantics — a derivative of the same model Tessera already generates
   to Rocq.  This keeps the assembly spec consistent with the hardware
   proofs by construction.

4. **Incremental delivery.** The verification will be built layer by
   layer rather than attempting the full core at once.  B1 (Iris
   resources against `machine.v`) is the first deliverable and is
   well-scoped; B3 (kernel-function proofs) proceeds function by
   function against those resources.  The full-core target is the
   endpoint, not the first publication.

**Consequence for §3 severity:** The gap remains High (it still needs
building), but the decisions above eliminate the three biggest sources
of uncertainty (toolchain risk, assembly-spec ambiguity, scope
creep).  What remains is engineering, not research.

#### 3d. The existence proof as a decision point (historical note)

Before the decisions above were made, a reviewer-facing alternative was
to declare a **minimum viable verification milestone** — one
end-to-end function, say `unmap_range` or `shootdown_broadcast` —
and make that the existence proof that the stack works.  The rest is
then "the same technique applied to more functions."

This decision is about reviewer psychology, not engineering: nobody
doubts that the hardware proofs are real; everyone doubts that the
kernel side is tractable.  One closed function is worth a thousand
"RefinedRust could be applied."  The author's decision to proceed
function-by-function (3c, item 4) absorbs this concern: the first
`unmap_range` proof is precisely that existence proof.

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
(manual Iris) is the only thing that would close this, and it is
proposed, not done (see §3).

**Status: merged into #1 §1c–1d above.** The `unsafe` surface audit,
the conditional-isolation formulation, and the privileged-triad
analysis are the same decisions. The author's answers to #1's four
questions determine the answer to #10 as well.

---

## Summary of priority

| # | Vulnerability | Severity | Status |
|---|--------------|----------|--------|
| 1 | Framekernel boundary asserted | High | **Open** (paired with #10) |
| 4 | Stackless-futures extreme | Medium | **Open** (paired with #9) |
| 5 | Clustering guarantee narrow | Medium | **Open** |
| 7 | Cluster story thin | Medium | **Open** |
| 9 | M:N revival burden | Medium | **Open** (paired with #4) |
| 10 | Rust-for-isolation unexamined | Medium | **Open** (paired with #1) |
| 2 | No empirical validation | — | **Decided** (correctness=verification, performance=empirical) |
| 3 | Verification-implementation gap | — | **Decided** (manual Iris, full core, Sail-specialised) |
| 6 | No threat model | — | **Addressed** (ch:security) |
| 8 | No comparisons | — | **Addressed** (ch:comparison) |

The six open items form three natural clusters:

- **#1 + #10** — the isolation story: can the framekernel boundary be
  defended, and is Rust-alone isolation conditional on proof/CHERI?
- **#4 + #9** — the execution model: can stackless futures carry the
  scheduler-activation revival, and is migration serializable?
- **#5 + #7** — the two "narrow but real" items: scope the clustering
  guarantee, and give the cluster story a failure model.

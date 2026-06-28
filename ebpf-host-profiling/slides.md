---
marp: true
theme: masters-research
size: 16:9
paginate: true
html: true
header: 'eBPF-Based Host-Level Behavioral Profiling for Blockchain Node Security'
footer: 'Master''s Research — 2026'
---

<!-- _class: lead -->

# eBPF-Based Host-Level Behavioral Profiling for Blockchain Node Security

## Detecting Infrastructure-Layer Attacks via Kernel-Level Monitoring

---

# Agenda

1. **Problem**: The unmonitored kernel layer
2. **Technology Concepts**: eBPF, Behavioral Fingerprinting, Provenance Graphs
3. **Two-Tier Detection Architecture**
4. **Attack Scenarios & Fingerprints**
5. **Research Design**
6. **References & Fact-Checking**

---

<!-- _class: divider -->

# The Problem Space

---

# What's Missing in Blockchain Node Security?

Existing monitoring focuses on:

| Layer | Approach | Key Papers |
|-------|----------|------------|
| Network traffic | Packet feature analysis + eBPF network capture | Bhumichai 2023/2024, Rehman 2025/2026, Su 2026 |
| Application logs | Log-based anomaly detection | — |
| Transaction data | On-chain anomaly detection | Cholevas 2024, Li 2025 |

**The gap:** Nobody monitors what happens at the **OS/kernel level** on the host running a blockchain node.

> A blockchain node is just a process — it makes syscalls, opens files, creates network connections. Attacks leave **host-level behavioral fingerprints**.

---

# Why Host-Level Fingerprinting?

A blockchain node is **extremely deterministic**:
- Same processes running (Geth, Prysm, validator)
- Same files accessed (chaindata, keystore, WAL)
- Same network patterns (peer connections, Engine API calls every ~12s)
- Same resource profile (CPU/memory within predictable bounds)

**This determinism is exploitable for security:**
- Any deviation from the "known-good" behavioral fingerprint is suspicious
- Unlike generic enterprise hosts, blockchain nodes have a *tight* baseline
- Simple policy-based detection can outperform complex ML

---

<!-- _class: divider -->

# Technology Stack Concepts

---

# What is eBPF?

**eBPF** (extended Berkeley Packet Filter) allows running sandboxed programs in the Linux kernel without modifying kernel source or loading kernel modules.

<div class="arch">
<div class="arch-title">User Space</div>
<div class="grid-2">
  <div class="box">Detection Engine</div>
  <div class="box">Provenance Graph Builder<br><span class="label">(NetworkX)</span></div>
</div>
</div>

<div class="diagram" style="justify-content:center">
  <div class="label" style="font-size:0.8em">▲ perf buffer / ring buffer ▲</div>
</div>

<div class="arch" style="border-color:var(--color-secondary)">
<div class="arch-title" style="color:var(--color-secondary); border-color:var(--color-secondary)">Kernel Space</div>
<div class="grid-2">
  <div class="box box-secondary">eBPF Programs<br><span class="label">(tracepoints, kprobes, LSM)</span></div>
  <div class="box box-secondary">eBPF Maps<br><span class="label">(aggregated counters, per-process state)</span></div>
</div>
</div>

---

# eBPF: Key Properties for Security Monitoring

**Why eBPF over traditional approaches (auditd, ptrace, kernel modules)?**

| Property | Benefit |
|----------|---------|
| **In-kernel execution** | Near-zero overhead — no context switches for data collection |
| **Verifier safety** | Programs are verified before loading — cannot crash the kernel |
| **In-kernel aggregation** | Compute features (counters, histograms) in kernel; send only summaries to userspace |
| **Dynamic attachment** | Attach/detach probes at runtime — no reboot, no recompile |
| **Multiple hook points** | Tracepoints, kprobes, uprobes, perf events, LSM hooks, XDP |
| **Maps for state** | Hash maps, ring buffers, per-CPU arrays — shared between probes |

**Overhead comparison:**
- auditd: 5-15% overhead (writes every event to disk)
- ptrace: 20-50% overhead (stops process on every syscall)
- **eBPF: <2% overhead** with in-kernel aggregation (Kim 2025, Orzechowski 2025, Park 2025)

---

# eBPF Attachment Points We Use

<div class="arch">
<div class="arch-title">Blockchain Node Process (Geth)</div>
<div class="grid-2">
  <div>
    <div class="box-group-label">Syscall Tracepoints</div>
    <div class="flow-item" style="margin:0.25em 0; font-size:0.85em"><code>connect()</code> → sys_enter_connect</div>
    <div class="flow-item" style="margin:0.25em 0; font-size:0.85em"><code>sendto()</code> → sys_enter_sendto</div>
    <div class="flow-item" style="margin:0.25em 0; font-size:0.85em"><code>open()</code> → sys_enter_openat</div>
    <div class="flow-item" style="margin:0.25em 0; font-size:0.85em"><code>read()</code> → sys_enter_read</div>
    <div class="flow-item" style="margin:0.25em 0; font-size:0.85em"><code>execve()</code> → sys_enter_execve</div>
    <div class="flow-item" style="margin:0.25em 0; font-size:0.85em"><code>mmap()</code> → sys_enter_mmap</div>
    <div class="flow-item" style="margin:0.25em 0; font-size:0.85em"><code>clone()</code> → sys_enter_clone</div>
  </div>
  <div>
    <div class="box-group-label">Hardware Performance Counters</div>
    <div class="box box-muted" style="text-align:left; font-size:0.85em; padding:0.8em">
      via <code>perf_event_open()</code><br><br>
      • Instructions retired<br>
      • Cache misses (L1, LLC)<br>
      • Branch mispredictions<br>
      • IPC (Instructions Per Cycle)
    </div>
  </div>
</div>
</div>

---

# Behavioral Fingerprinting: The Concept

**Fingerprinting** = creating a characteristic signature of a process's behavior at the kernel level.

**What makes a fingerprint?**

| Feature Category | Examples | Detection Power |
|-----------------|----------|-----------------|
| Syscall frequency vectors | Counts of each syscall per time window | Baseline deviation |
| N-gram sequences | Bigrams/trigrams of syscall orderings | Sequential pattern anomaly |
| Network socket behavior | Peer diversity, connection churn rate | Eclipse attack detection |
| File access patterns | Which paths, by which processes | Key exfiltration |
| HPC ratios | Cache miss rate, IPC, branch misprediction | Cryptojacking fingerprint |
| Resource deltas | CPU scheduling time changes, mmap rate | DoS / resource abuse |

> The key insight: blockchain nodes produce a **stable, repeatable fingerprint** — deviations signal attack.

---

# Hardware Performance Counter (HPC) Fingerprinting

**HPCs** are CPU registers that count microarchitectural events — accessible via `perf_event_open()` syscall, readable by eBPF.

**Why HPCs detect cryptojacking:**

| Metric | Normal Blockchain Node | Cryptojacking (RandomX) |
|--------|----------------------|-------------------------|
| IPC | Variable (I/O bound) | Very high (compute bound) |
| LLC miss rate | Moderate | Low (fits in cache by design) |
| Branch misprediction | Normal | Low (predictable loops) |
| L1D cache miss | Moderate | Very low (2MB scratchpad) |

<div class="box-group" style="font-size:0.8em; margin-top:0.5em">
<div class="box-group-label">Cryptojacking Fingerprint</div>
<strong>High IPC</strong> + <strong>Low cache misses</strong> + <strong>Low branch misprediction</strong><br>
= Compute-intensive, cache-friendly, predictable workload<br>
≠ Normal blockchain node behavior (I/O + network + crypto ops)
</div>

*Reference: Pott et al. 2023 — overcomes GPU-presence pitfalls in HPC detection*

---

# What is a Provenance Graph?

A **provenance graph** captures causal relationships between system entities observed via kernel monitoring:

<div class="arch" style="padding:1em">
<div class="grid-2" style="gap:2em">
  <div class="diagram-vertical" style="align-items:stretch">
    <div class="box" style="border-color:var(--color-primary)">geth <span class="label">(pid 1)</span></div>
    <div style="display:flex; gap:0.4em; justify-content:space-around; margin:0.4em 0">
      <div style="text-align:center"><div class="arrow-down">↓</div><div class="label">read</div></div>
      <div style="text-align:center"><div class="arrow-down">↓</div><div class="label">write</div></div>
      <div style="text-align:center"><div class="arrow-down">↓</div><div class="label">sendto</div></div>
    </div>
    <div style="display:flex; gap:0.4em">
      <div class="box box-muted" style="font-size:0.8em; flex:1">chaindata/</div>
      <div class="box box-muted" style="font-size:0.8em; flex:1">WAL/logs</div>
      <div class="box box-accent" style="font-size:0.8em; flex:1">Engine API<br>socket</div>
    </div>
  </div>
  <div class="diagram-vertical" style="align-items:stretch">
    <div class="box box-accent">prysm <span class="label">(pid 2)</span></div>
    <div style="text-align:center"><div class="arrow-down">↓</div><div class="label">connect</div></div>
    <div class="box box-muted" style="font-size:0.8em">peer:30303</div>
    <div style="margin-top:0.5em; text-align:center"><div class="arrow-down">↓</div><div class="label">recvfrom</div></div>
    <div class="box box-muted" style="font-size:0.8em">Engine API socket</div>
  </div>
</div>
</div>

**Nodes:** processes, files, network sockets — **Edges:** syscall interactions (labeled, timestamped)

---

# Provenance Graphs: Why Not GNNs?

Existing provenance-graph IDS (PROGRAPHER, MAGIC, Flash) use **Graph Neural Networks** for detection. We argue this is **overkill** for blockchain nodes:

| Aspect | GNN Approach | Our Invariant Approach |
|--------|-------------|----------------------|
| Training data needed | Large labeled dataset | Zero (baseline observation only) |
| Detection method | Learned embeddings | Policy/rule matching on graph structure |
| Interpretability | Black-box | "Process X accessed file Y" — fully explainable |
| False positives | Tunable but opaque | Near-zero (deterministic domain) |
| Inference overhead | GPU or expensive CPU | Simple graph comparison |
| Cold start | Requires training phase | Works after baseline capture (~hours) |

> **Key insight:** Blockchain nodes are so deterministic that structural policies on the provenance graph suffice — no ML needed for Tier 2.

---

<!-- _class: divider -->

# Two-Tier Detection Architecture

---

# Architecture Overview

<div class="arch" style="margin:0.3em 0">
<div class="arch-title">Tier 1: Real-Time (In-Kernel)</div>
<div class="diagram">
  <div class="box box-secondary" style="font-size:0.85em">eBPF Maps<br><span class="label">(counters, histograms)</span></div>
  <div class="arrow">→</div>
  <div class="box" style="font-size:0.85em">Feature Vectors<br><span class="label">(per window)</span></div>
  <div class="arrow">→</div>
  <div class="box box-accent" style="font-size:0.85em">LightGBM / IsoForest<br><span class="label">(anomaly score)</span></div>
</div>
<div class="label">Latency: milliseconds | Overhead: &lt;2%</div>
</div>

<div class="diagram" style="margin:0.3em 0">
  <div class="arrow-down" style="font-size:1.1em">↓ Alert triggers Tier 2</div>
</div>

<div class="arch" style="margin:0.3em 0; border-color:var(--color-accent)">
<div class="arch-title" style="color:var(--color-accent); border-color:var(--color-accent)">Tier 2: Structural (Periodic / Triggered)</div>
<div class="diagram">
  <div class="box" style="font-size:0.85em">eBPF Traces<br><span class="label">(audit log)</span></div>
  <div class="arrow">→</div>
  <div class="box box-secondary" style="font-size:0.85em">Provenance Graph<br><span class="label">(NetworkX)</span></div>
  <div class="arrow">→</div>
  <div class="box box-accent" style="font-size:0.85em">Invariant Check<br><span class="label">(policy match)</span></div>
</div>
<div class="label">Runs: every 5-10 min or on Tier 1 alert</div>
</div>

---

# Tier 1: Lightweight Real-Time Detection

**In-kernel feature extraction** — compute directly in eBPF maps:

```c
// eBPF map: per-process syscall frequency counter
struct {
    __uint(type, BPF_MAP_TYPE_PERCPU_HASH);
    __uint(max_entries, 1024);
    __type(key, struct proc_syscall_key);   // {pid, syscall_nr}
    __type(value, u64);                     // count
} syscall_freq SEC(".maps");

// eBPF map: connection diversity tracker
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 4096);
    __type(key, u32);                       // pid
    __type(value, struct conn_diversity);   // {unique_peers, churn_rate}
} conn_metrics SEC(".maps");
```

**Features extracted per window (e.g., 10 seconds):**
- Syscall frequency vector (top-N syscalls)
- Connection diversity (unique peers, new connections/s)
- HPC ratios (IPC, cache miss rate)
- Resource deltas (CPU time change, mmap count)

---

# Tier 2: Provenance Graph Invariant Detection

**Five structural invariants** for blockchain node stacks:

| # | Invariant | Violation Means |
|---|-----------|-----------------|
| 1 | **Process set**: only `{geth, prysm, validator, ...}` | New unknown process (malware, cryptojacker) |
| 2 | **File access policy**: only `validator` reads keystore | Key exfiltration attempt |
| 3 | **Network connectivity**: Engine API socket only from `{prysm, geth}` | Engine API injection |
| 4 | **Temporal cadence**: Engine API calls follow slot timing (~12s) | Timing manipulation |
| 5 | **Graph diff from baseline**: Jaccard distance on edge sets | Structural anomaly |

**Detection is graph comparison + policy checking — not ML inference.**

---

<!-- _class: divider -->

# Attack Scenarios & Fingerprints

---

# Attack 1: Eclipse Attack

**What:** Adversary monopolizes all peer connections, isolating the node

**Host-level fingerprint:**
- Abnormal `connect()`/`close()` churn from few source IPs
- Reduced peer diversity in socket table (collapse to small set)
- Sudden replacement of established long-lived connections

**Detection:**
- **Tier 1:** Connection diversity metric drops below threshold; connection rate spikes
- **Tier 2:** Provenance graph — peer connection edges collapse to few source nodes

<div class="grid-2" style="margin-top:0.5em; font-size:0.8em">
  <div class="box box-accent" style="text-align:left; padding:0.6em"><strong>Normal:</strong> geth → peer_A, peer_B, peer_C, ... peer_50<br><span class="label">(diverse)</span></div>
  <div class="box" style="text-align:left; padding:0.6em; border-color:#dc2626"><strong>Eclipse:</strong> geth → attacker_1, attacker_1, attacker_1...<br><span class="label">(collapsed)</span></div>
</div>

*References: Shi 2026, Rehman 2025/2026, Heo 2023 (NDSS)*

---

# Attack 2: Cryptojacking Co-location

**What:** Attacker runs crypto miner (XMRig) alongside the blockchain node

**Host-level fingerprint:**
- New process with high CPU affinity — detected via `execve()` monitoring
- Characteristic HPC pattern: high IPC + low cache misses (RandomX algorithm)
- CPU scheduling pressure on legitimate node processes
- Abnormal `clone()` calls (miner spawning threads)

**Detection:**
- **Tier 1 (primary):** HPC ratio anomaly — IPC/cache-miss signature doesn't match any known-good process
- **Tier 2:** New process node in provenance graph that wasn't in baseline

<div class="grid-2" style="margin-top:0.4em; font-size:0.75em">
  <div class="box box-accent" style="text-align:left; padding:0.5em"><strong>blockchain_node:</strong><br>IPC=0.8, LLC_miss=12%, branch=8%</div>
  <div class="box" style="text-align:left; padding:0.5em; border-color:#dc2626"><strong>xmrig_miner:</strong><br>IPC=2.1, LLC_miss=0.3%, branch=1.2%</div>
</div>

*References: Kim 2025, Orzechowski 2025, Park 2025, Pott 2023*

---

# Attack 3: Validator Key Exfiltration

**What:** Rogue process reads validator signing keys and exfiltrates them

**Host-level fingerprint:**
- Anomalous `open()`/`read()` on keystore paths from unexpected PID
- Followed by outbound `connect()`/`sendto()` carrying key-sized payload
- Possible `execve()` of data transfer tools (`curl`, `scp`, `nc`)

**Detection — Tier 2 (primary):** Provenance graph shows anomalous path:

<div class="diagram" style="margin:0.5em 0">
  <div class="box" style="border-color:#dc2626; font-size:0.85em">unknown_process</div>
  <div class="arrow">→</div>
  <div class="box box-muted" style="font-size:0.85em">keystore_file<br><span class="label">read</span></div>
  <div class="arrow">→</div>
  <div class="box" style="border-color:#dc2626; font-size:0.85em">network_socket<br><span class="label">sendto</span></div>
</div>

> This path **never exists** in the baseline graph.

*References: Bhudia 2023 (18 cites), Zhou 2024, Caroly 2024*

---

# Attack-to-Tier Detection Mapping

| Attack | Tier 1 (Statistical) | Tier 2 (Graph) | Primary Signal |
|--------|---------------------|----------------|----------------|
| Eclipse Attack | Connection diversity ↓ | Topology collapse | Connection pattern shift |
| Cryptojacking | HPC ratio anomaly | New process node | Microarchitectural fingerprint |
| Key Exfiltration | File access spike | process→file→network path | Structural graph anomaly |
| RPC DoS* | Resource consumption ↑ | process→DB edges ↑ | Resource exhaustion |
| Engine API Injection* | Timing deviation | Communication subgraph change | Temporal + structural |

*Stretch goals*

---

<!-- _class: divider -->

# Research Design

---

# Research Questions

| RQ | Question | Method |
|----|----------|--------|
| **RQ1** | What are characteristic host-level patterns of blockchain nodes (normal vs. attack)? | eBPF profiling + statistical analysis |
| **RQ2** | Can eBPF monitoring detect infrastructure-layer attacks with sufficient accuracy? | Attack simulation + precision/recall/F1 |
| **RQ3** | How does host-level compare to network-level detection? | Comparison with Su 2026, Bhumichai |

---

# Evaluation Plan

**Per-attack metrics:**
- Detection accuracy (precision, recall, F1)
- Time-to-detection (seconds from attack start)
- False positive rate under normal operation

**Overhead metrics:**
- eBPF collection cost (CPU%, memory)
- Graph construction cost (time, memory)
- Invariant checking cost (time per check)

**Comparisons:**
- Tier 1 alone vs. Tier 2 alone vs. combined
- Our approach vs. Su 2026 (network-only eBPF)
- Invariant-based vs. hypothetical GNN approach (accuracy vs. overhead tradeoff)
- Ablation: which features are necessary per attack type?

---

# Timeline (8 Months)

| Period | Activity |
|--------|----------|
| Months 1-2 | Literature review, eBPF tooling setup, node deployment, trace collection |
| Month 3 | Tier 1: in-kernel feature extraction + lightweight classifier |
| Month 4 | Attack simulation + labeled data collection |
| Month 5 | Tier 2: provenance graph construction + invariant detection |
| Month 6 | Full evaluation (both tiers, ablation, comparison) |
| Months 7-8 | Thesis writing + additional experiments |

---

<!-- _class: divider -->

# References & Fact-Checking

---

<!-- _class: references -->

# References: Blockchain Node Security (1/2)

| # | Reference | Claim Used | Fact-Check |
|---|-----------|-----------|------------|
| 1 | Su et al. 2026 — "Anomaly detection for blockchain nodes based on eBPF and fine-tuning large language model" | Only existing eBPF + blockchain node paper; network-level only | **Verified**: Uses eBPF for network traffic capture only; detection via LLM fine-tuning (RAG + CoT + DoRA) on network data transformed to text; no host-level behavioral profiling |
| 2 | Rehman et al. 2025 — "Eclipse attacks in blockchain networks: detection, prevention, and future directions" | Eclipse attack testbed methodology; network traffic features | **Verified**: Survey paper covering detection via network-layer features (peer connection analysis); no kernel-level approach |
| 3 | Shi et al. 2026 — "Eclipse Attacks on Ethereum's Peer-to-Peer Network" (ACM) | Latest eclipse vectors on post-Merge Ethereum | **Verified**: Published in ACM; documents eclipse vectors specific to PoS Ethereum's peer management |
| 4 | Heo et al. 2023 — "Partitioning Ethereum without Eclipsing It" (NDSS, 37 cites) | Network partitioning as alternative to eclipse | **Verified**: NDSS publication; shows partitioning is possible without full eclipse; uses routing-level manipulation |

---

<!-- _class: references -->

# References: Blockchain Node Security (2/2)

| # | Reference | Claim Used | Fact-Check |
|---|-----------|-----------|------------|
| 5 | Bhudia et al. 2023 — "Game theoretic modelling of ransom/extortion on Ethereum validators" (18 cites) | Validator key compromise enables ransom/slashing threats | **Verified**: Models economic impact of key compromise; slashing risk creates ransom leverage |
| 6 | Zhou et al. 2024 — "Towards understanding crypto-asset risks on Ethereum caused by key leakage" (ACM) | Real-world key leakage analysis on Ethereum | **Verified**: ACM publication; empirically measures leaked keys on the internet and resulting asset theft |
| 7 | Caroly et al. 2024 — "Securing Blockchain Wallet Files Using eBPF" | eBPF for wallet/key file access monitoring | **Verified**: Uses eBPF LSM hooks to monitor keystore file access; closest to our key exfiltration detection |
| 8 | Seidenberger & Maiti 2025 — "Initial Evidence of Pervasive Reconnaissance Targeting Ethereum Node Infrastructure" (ACM) | Active reconnaissance/scanning threat to nodes | **Verified**: Documents systematic scanning of Ethereum node ports in the wild |

---

<!-- _class: references -->

# References: eBPF Security Monitoring

| # | Reference | Claim Used | Fact-Check |
|---|-----------|-----------|------------|
| 9 | Kim et al. 2025 — "Detecting cryptojacking containers using eBPF-based security runtime and ML" | eBPF + ML detects cryptojacking with <2% overhead | **Verified**: Demonstrates eBPF resource monitoring + ML classifier; reports minimal performance impact on container workloads |
| 10 | Orzechowski et al. 2025 — "Cryptojacking Detection Using eBPF and Machine Learning Techniques" | eBPF resource features sufficient for cryptojacking detection | **Verified**: Uses eBPF-collected CPU/memory metrics as ML features; achieves >95% accuracy |
| 11 | Park et al. 2025 — "CryptoGuard: Lightweight Hybrid Detection" | eBPF + syscall monitoring for cryptojacking | **Verified**: Combines syscall analysis with resource monitoring; lightweight design suitable for production |
| 12 | Satpathy et al. 2025 — "Towards Generating Robust Provenance Graph for Attack Investigation over Distributed Microservice Architecture" | eBPF → provenance graph methodology for microservices | **Verified**: Closest methodological reference; builds provenance graphs from eBPF traces in K8s environment |

---

<!-- _class: references -->

# References: Provenance Graphs & HPCs

| # | Reference | Claim Used | Fact-Check |
|---|-----------|-----------|------------|
| 13 | Yang et al. 2023 — "PROGRAPHER" (USENIX Security, 160 cites) | Foundational provenance graph IDS | **Verified**: USENIX Security; uses graph embeddings for anomaly detection on audit logs |
| 14 | Jia et al. 2024 — "MAGIC" (USENIX Security, 158 cites) | GNN approach for APT detection on provenance graphs | **Verified**: Masked graph learning; represents heavyweight ML baseline we argue against |
| 15 | Rehman et al. 2024 — "FLASH: A Comprehensive Approach to Intrusion Detection via Provenance Graph Representation Learning" (181 cites) | Provenance-based IDS via graph representation learning | **Verified**: Large-scale provenance IDS; our comparison baseline for overhead analysis |
| 16 | Goyal et al. 2023 — "Evading provenance-based ML detectors with adversarial system actions" (USENIX Security, 111 cites) | Graph-based IDS have adversarial robustness limitations | **Verified**: USENIX Security '23; demonstrates evasion attacks; relevant limitation we acknowledge |
| 17 | Pott et al. 2023 — "Overcoming pitfalls of HPC-based cryptojacking detection in presence of GPUs" | HPC fingerprinting methodology for cryptojacking | **Verified**: Addresses GPU noise in HPC readings; methodology reference for our Tier 1 HPC features |
| 18 | Da Silva et al. 2026 — "On the precision of dynamic program fingerprints based on performance counters" | Program fingerprinting via HPCs is precise | **Verified**: Demonstrates HPCs can uniquely fingerprint program execution behavior |

---

<!-- _class: references -->

# Key Fact-Check Summary

| Claim | Status | Notes |
|-------|--------|-------|
| No existing work does host-level behavioral profiling of blockchain nodes | **Supported** | Su 2026 is closest but network-only; Caroly 2024 protects wallet files only |
| eBPF overhead is <2% with in-kernel aggregation | **Supported** | Kim 2025, Orzechowski 2025 both report <2% on container workloads; Park 2025 reports 0.06% CPU overhead |
| Blockchain nodes are highly deterministic (stable behavioral fingerprint) | **Plausible** | Logical argument from blockchain protocol design; needs empirical validation (our contribution) |
| GNNs are unnecessary for deterministic systems | **Novel claim** | Our hypothesis; no prior work directly compares invariant-based vs. GNN on blockchain nodes |
| HPCs can fingerprint cryptojacking workloads | **Verified** | Pott 2023, Da Silva 2026, multiple papers confirm distinctive HPC signatures |
| Provenance graphs from eBPF are feasible at scale | **Verified** | Satpathy 2025 demonstrates in microservice environment; windowed approach manages graph size |
| Eclipse attacks leave kernel-visible connection patterns | **Plausible** | Logical from attack mechanics; no prior work has measured this from kernel perspective (our contribution) |

---

# Positioning vs. State of the Art

| Paradigm | Our Contribution |
|----------|-----------------|
| Statistical + ML (Joraviya, Aldribi) | We add blockchain-domain features + graph structure |
| N-gram syscalls (Javan, Surendran) | We combine with HPC + provenance context |
| LSTM/Transformer (Transcall, LogEncoder) | We argue lightweight models suffice for deterministic domains |
| Provenance + GNN (PROGRAPHER, MAGIC, Flash) | We replace GNN with invariant-based detection (exploiting domain determinism) |
| eBPF profiling (Wüstrich, Alton) | We apply to novel domain (blockchain) with graph extension |
| HPCs (Da Silva, Pott) | We integrate HPCs into multi-signal Tier 1 alongside syscall features |

---

<!-- _class: lead -->

# Questions?

## Key Insight: Blockchain nodes are so deterministic that simple structural invariants on provenance graphs outperform heavyweight ML — and eBPF captures it all at <2% overhead.

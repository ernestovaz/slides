---
marp: true
theme: masters-research
size: 16:9
paginate: true
html: true
header: 'WASM Service Mesh Filters for Blockchain API Security'
footer: 'Master''s Research — 2026'
---

<!-- _class: lead -->

# Blockchain-Aware Service Mesh Security

## WASM Envoy Filters for Detecting and Mitigating Attacks on Ethereum Node APIs

---

# Agenda

1. **Problem**: Unprotected Ethereum API surfaces
2. **Context**: Ethereum node architecture & why K8s
3. **Technology Stack**: Envoy, Service Mesh, WASM Filters
4. **Proposed Solution**: Blockchain-semantic-aware L7 inspection
5. **Research Design & Novelty**
6. **References**

---

<!-- _class: divider -->

# The Problem Space

---

# Ethereum Node API Attack Surface

Blockchain nodes expose **critical API surfaces** with no semantic protection:

- **JSON-RPC** — Expensive calls (`eth_getLogs`, `debug_traceCall`) exhaust resources
- **Engine API** — Controls block production; compromising it undermines chain integrity
- **Beacon API** — Validator key extraction, state query flooding

**Current state:**
- Self-hosted nodes: typically **unprotected**
- RPC providers (Infura/Alchemy): **generic rate limiting** only
- **No existing solution** understands blockchain API semantics

---

# Why the API Layer (Not P2P)?

| Layer | Protocol | Inspectable at Sidecar? |
|-------|----------|------------------------|
| Execution P2P | devp2p/RLPx (AES-256-CTR) | **No** — encrypted |
| Consensus P2P | libp2p/Noise (Noise XX) | **No** — encrypted |
| **JSON-RPC API** | HTTP/JSON-RPC | **Yes** — plaintext or TLS-terminated |
| **Engine API** | HTTP + JWT | **Yes** — body is plaintext |
| **Beacon API** | HTTP REST | **Yes** — plaintext or TLS-terminated |

> P2P is encrypted by design. The API layer is where undefended, documented attacks exist.

---

<!-- _class: divider -->

# Ethereum Node Architecture & Kubernetes

---

# Post-Merge Ethereum: Two Clients, One Node

Since The Merge (Sept 2022), an Ethereum node = **Execution Client + Consensus Client**:

<div class="grid-2">
  <div class="nested">
    <div class="nested-label">Execution Layer (EL)</div>
    <div class="box" style="font-size:0.8em">Geth / Nethermind / Besu / Reth</div>
    <div style="font-size:0.75em; margin-top:0.3em">
      - Executes transactions (EVM)<br>
      - Manages mempool & state<br>
      - Exposes JSON-RPC (port 8545)<br>
      - P2P via devp2p (port 30303)
    </div>
  </div>
  <div class="nested">
    <div class="nested-label">Consensus Layer (CL)</div>
    <div class="box" style="font-size:0.8em">Prysm / Lighthouse / Teku / Nimbus</div>
    <div style="font-size:0.75em; margin-top:0.3em">
      - Runs Proof-of-Stake consensus<br>
      - Manages validators & attestations<br>
      - Exposes Beacon API (port 5052)<br>
      - P2P via libp2p (port 9000)
    </div>
  </div>
</div>

**Engine API** (port 8551): CL tells EL which blocks to build — the critical bridge between them.

---

# Why Kubernetes for Blockchain Nodes?

Ethereum's multi-process architecture is a **natural fit** for K8s:

| Requirement | K8s Solution |
|-------------|-------------|
| EL + CL + Validator coordination | Pod with multiple containers |
| Persistent chain data (~1TB) | PersistentVolumeClaims (SSD-backed) |
| Auto-restart on crash | Pod lifecycle management |
| Client diversity (Geth + Nethermind mix) | Heterogeneous deployments via labels |
| Service mesh security (our work) | Istio sidecar injection |

**Who runs blockchain on K8s:**
- RPC providers (Infura, Alchemy, QuickNode) — thousands of nodes
- Staking operators (Lido, Figment, Chorus One) — hundreds of validators
- L2 sequencers (Optimism, Arbitrum, Base)
- Enterprise chains (Hyperledger Fabric — K8s is the default deployment)

---

<!-- _class: divider -->

# Technology Stack

---

# Envoy Proxy & Filter Chains

**Envoy**: high-performance L7 proxy, designed as a programmable data plane.

<div class="arch">
<div class="arch-title">Envoy Proxy</div>
<div class="diagram">
  <div class="box">Incoming<br>Request</div>
  <div class="arrow">→</div>
  <div class="flow">
    <div class="flow-item">Filter #1</div>
    <div class="arrow">→</div>
    <div class="flow-item">Filter #2</div>
    <div class="arrow">→</div>
    <div class="flow-item">Filter #N</div>
  </div>
  <div class="arrow">→</div>
  <div class="box box-accent">Upstream<br>Service</div>
</div>
</div>

- Filters are **chained** — each can inspect, modify, or reject the request
- Filters can be native C++ or **WASM modules** (our approach)
- Filter decision: `Continue`, `StopIteration`, or `DirectResponse` (reject)
- Managed by Istio control plane — config distributed automatically

---

# Service Mesh: Istio + Envoy Sidecars

<div class="arch">
<div class="arch-title">Kubernetes Cluster</div>
<div class="grid-3">
  <div class="nested">
    <div class="nested-label">Pod: Geth</div>
    <div class="box" style="font-size:0.85em">Geth Process</div>
    <div class="box box-accent" style="font-size:0.75em; margin-top:0.4em">Envoy Sidecar</div>
  </div>
  <div class="nested">
    <div class="nested-label">Pod: Prysm</div>
    <div class="box" style="font-size:0.85em">Prysm Process</div>
    <div class="box box-accent" style="font-size:0.75em; margin-top:0.4em">Envoy Sidecar</div>
  </div>
  <div class="nested">
    <div class="nested-label">Pod: Validator</div>
    <div class="box" style="font-size:0.85em">Validator Process</div>
    <div class="box box-accent" style="font-size:0.75em; margin-top:0.4em">Envoy Sidecar</div>
  </div>
</div>
<div style="text-align:center; margin-top:0.6em">
  <div class="box box-secondary" style="display:inline-block">Istio Control Plane</div>
</div>
</div>

- **Sidecar pattern**: Envoy injected alongside each pod, intercepts all traffic transparently
- All inter-service communication flows through the sidecar — **natural inspection point**
- P2P traffic bypasses the mesh (encrypted, latency-sensitive)

---

# WASM in Envoy: Why It Matters

**WebAssembly** lets us extend Envoy without recompiling it:

- **Sandboxed** — filter crash doesn't take down the proxy
- **Near-native performance** — compiled from Rust via Proxy-WASM SDK
- **Hot-reloadable** — deploy new filter logic without proxy restart
- **Proxy-WASM ABI** — standard interface: `on_request_body()`, `send_http_response()`, `get/set_shared_data()`

Deployed as a **Kubernetes resource** (EnvoyFilter CRD):

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: blockchain-rpc-filter
  namespace: ethereum
spec:
  workloadSelector:
    labels:
      app: geth
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: SIDECAR_INBOUND
    patch:
      operation: INSERT_BEFORE
      value:
        name: blockchain_rpc_filter
        typed_config:
          "@type": type.googleapis.com/udpa.type.v1.TypedStruct
          type_url: type.googleapis.com/envoy.extensions.filters.http.wasm.v3.Wasm
          value:
            config:
              vm_config:
                runtime: envoy.wasm.runtime.v8
                code:
                  local:
                    filename: /etc/wasm/rpc_filter.wasm
```

---

<!-- _class: divider -->

# Proposed Solution

---

# WASM Filter Architecture

<div class="diagram" style="gap:1.2em">
  <div class="box">External<br>Client</div>
  <div class="arrow">→</div>
  <div class="arch" style="flex:1">
    <div class="arch-title">Envoy Sidecar — WASM Filter Chain</div>
    <div class="diagram-vertical">
      <div class="flow-item" style="width:100%; border-color:var(--color-primary)">1. RPC Method Filter <span class="label">(allowlist / block)</span></div>
      <div class="arrow-down">↓</div>
      <div class="flow-item" style="width:100%; border-color:var(--color-secondary)">2. Anomaly Detector <span class="label">(pattern tracking)</span></div>
      <div class="arrow-down">↓</div>
      <div class="flow-item" style="width:100%; border-color:var(--color-accent)">3. Engine API Monitor <span class="label">(sequence validation)</span></div>
    </div>
  </div>
  <div class="arrow">→</div>
  <div class="box box-accent">Geth<br>Node</div>
</div>

Three filters, each addressing a distinct threat class — chained for defense-in-depth.

---

# Filter 1: JSON-RPC Method Filter

**Blockchain-semantic access control** — not generic rate limiting.

```rust
fn on_http_request_body(&mut self, body_size: usize, _eof: bool) -> Action {
    if let Some(body) = self.get_http_request_body(0, body_size) {
        let rpc: JsonRpcRequest = serde_json::from_slice(&body)?;

        // Block dangerous namespaces entirely
        if rpc.method.starts_with("debug_") || rpc.method.starts_with("personal_") {
            self.send_http_response(403, vec![], Some(b"Blocked"));
            return Action::Pause;
        }

        // Cost-based rate limiting for expensive methods
        if rpc.method == "eth_getLogs" {
            let range = extract_block_range(&rpc.params);
            if range > MAX_BLOCK_RANGE {
                self.send_http_response(429, vec![], Some(b"Range too large"));
                return Action::Pause;
            }
        }
    }
    Action::Continue
}
```

---

# Filter 2: RPC Anomaly Detector

**Detect probing and abuse patterns** via per-source behavioral analysis.

**Detection targets:**
- **Deanonymization probing** (Wang et al. 2025): sequential block scanning, address enumeration
- **Batch RPC abuse**: unbounded batch sizes exploiting JSON-RPC batch semantics
- **Method distribution anomalies**: sudden shift in API usage pattern

**Technique:**
- Per-IP sliding window of method calls (WASM shared data)
- Method distribution entropy — low entropy signals probing
- Sequential parameter detection (incrementing addresses, block numbers)
- Match against known attack signatures → alert or block

---

# Filter 3: Engine API Integrity Monitor

**Validate consensus-to-execution communication** — first work to monitor this interface.

<div class="diagram-vertical" style="margin:0.5em 0">
  <div class="box box-secondary">Consensus Client (Prysm)</div>
  <div class="arrow-down">↓</div>
  <div class="box-group" style="text-align:left; font-size:0.8em; padding:0.8em 1.2em">
    <code>engine_forkchoiceUpdatedV3(head, safe, finalized)</code><br>
    <code>engine_newPayloadV3(execution_payload)</code><br>
    <code>engine_getPayloadV3(payload_id)</code>
  </div>
  <div class="arrow-down">↓</div>
  <div class="box box-accent">Execution Client (Geth)</div>
</div>

**Validations:** expected method sequence per slot (~12s), no unauthorized callers, payload timing aligned with slot/epoch cadence, fork-choice references valid block hashes.

---

<!-- _class: divider -->

# Research Design & Novelty

---

# Research Questions

| RQ | Question | Method |
|----|----------|--------|
| **RQ1** | Can WASM filters detect known blockchain API attack patterns? | Attack simulation + precision/recall/F1 |
| **RQ2** | What is the performance overhead of blockchain-aware L7 inspection? | Latency benchmarks (p50/p95/p99), throughput |
| **RQ3** | What API patterns characterize normal vs. malicious behavior? | Traffic analysis + policy expressiveness |

---

# Evaluation Design

**Comparison baselines:**

| Setup | Description |
|-------|-------------|
| No protection | Direct access to node RPC |
| Generic rate limiting | Envoy built-in rate limit (not blockchain-aware) |
| Nginx JSON-RPC filter | Basic method blocking |
| **Our WASM filters** | Blockchain-semantic-aware inspection |

**Metrics:** Precision/Recall/F1 per attack type, p50/p95/p99 latency, max RPS, WASM memory/CPU footprint.

---

# Testbed Architecture

<div class="arch">
<div class="arch-title">Kubernetes Cluster (kind / minikube / cloud)</div>
<div class="grid-3" style="margin-bottom:0.8em">
  <div class="nested">
    <div class="nested-label">Geth Pod</div>
    <div class="box" style="font-size:0.8em">Execution Client</div>
    <div class="box box-accent" style="font-size:0.7em; margin-top:0.3em">+ Sidecar + WASM Filters</div>
  </div>
  <div class="nested">
    <div class="nested-label">Prysm Pod</div>
    <div class="box" style="font-size:0.8em">Consensus Client</div>
    <div class="box box-accent" style="font-size:0.7em; margin-top:0.3em">+ Sidecar + WASM Filters</div>
  </div>
  <div class="nested">
    <div class="nested-label">Attack Generator</div>
    <div class="box box-secondary" style="font-size:0.7em">RPC DoS</div>
    <div class="box box-secondary" style="font-size:0.7em; margin-top:0.2em">Deanonymization</div>
    <div class="box box-secondary" style="font-size:0.7em; margin-top:0.2em">Engine API Inject</div>
  </div>
</div>
<div class="grid-2">
  <div class="box box-muted" style="font-size:0.8em">Prometheus + Grafana<br><span class="label">latency, throughput, alerts</span></div>
  <div class="box box-muted" style="font-size:0.8em">Istio Control Plane<br><span class="label">config, certs, policy</span></div>
</div>
</div>

---

# What's New: Novelty Positioning

| Contribution | Why It's Novel |
|-------------|---------------|
| **Blockchain-semantic L7 inspection** | Existing work identifies API vulnerabilities but proposes no proxy-level defense |
| **Engine API integrity monitoring** | No prior work monitors the consensus↔execution interface |
| **WASM Envoy filter for blockchain** | Existing WASM filters (Koney, Coraza) are generic — not protocol-aware |
| **Service mesh native deployment** | Current node protection is ad-hoc (firewall rules, nginx configs) |
| **Self-hosted node protection** | RPC providers protect only their own endpoints |

**Gap we fill:** Attacks are documented → defenses are not. We bridge that gap at the data plane.

---

# Timeline (8 Months)

| Period | Activity |
|--------|----------|
| Months 1-2 | Literature review; API surface mapping; threat model |
| Months 3-4 | WASM filter development (Rust/Proxy-WASM); K8s testbed setup |
| Months 5-6 | Attack simulation + baseline traffic generation |
| Month 7 | Evaluation (detection + performance + comparison) |
| Month 8 | Thesis writing |

---

# References

| # | Reference | Relevance |
|---|-----------|-----------|
| 1 | Wang et al. 2025 — "Time Tells All: Deanonymization of Blockchain RPC Users" | RPC timing deanonymization attack (key threat) |
| 2 | Zhong et al. 2026 — "Is My RPC Response Reliable?" | RPC bugs, Engine API execution model |
| 3 | Ma et al. 2026 — "When Specifications Meet Reality" | API inconsistencies across 11 clients |
| 4 | Kim & Hwang 2023 — "Etherdiffer" | RPC differential testing methodology |
| 5 | Meadows et al. 2023 — "Sidecar-based path-aware security" | Envoy sidecar as enforcement point |
| 6 | Chandramouli & Hales 2024 (NIST SP) | NIST validation of WASM Envoy filters |
| 7 | Kahlhofer et al. 2025 — "Koney" | WASM filter K8s methodology (closest parallel) |

---

<!-- _class: lead -->

# Questions?

## The API layer is plaintext at the sidecar — and nobody is inspecting it with blockchain semantics.

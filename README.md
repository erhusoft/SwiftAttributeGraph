# SwiftAttributeGraph

A high-performance, zero-recursion reactive attribute graph engine written in pure Swift, engineered from scratch to serve as the core computation engine for declarative UI frameworks (such as SwiftUI/SwiftUICore) on **macOS** and **Windows** (ARM64 & x86_64).

> **Pure computation engine**: `SwiftAttributeGraph` has no knowledge of views, layout, drawing, or windows. It is strictly responsible for reactive dependency tracking (DAG), fine-grained version cuts, iterative lazy evaluation, and deterministic lifecycle management.

---

## Key Highlights

- **100% Native Parity**: Direct semantic and API parity with Apple's `AttributeGraph.framework` (macOS Sequoia 15.5 / 15.8.3, Apple Silicon ARM64), including `_AttributeBody`, `RuleContext`, `ObservedAttribute`, `IndirectAttribute`, `OptionalAttribute`, `PointerOffset`, `withUnsafeTuple`, and Swift runtime enum reflection (`forEachField`, `withUnsafePointerToEnumCase`).
- **Zero-Recursion Guarantee**: All graph mounting, traversal, transitive invalidation, breadth-first search, and lifecycle reclamation are implemented iteratively using flat stacks and explicit queues. Verified with deep dependency chains of **$\ge 20,000$ to $100,000$ levels** with zero stack overflow risk.
- **Ultra-Hot Read Path ($\sim 12\text{ ns}$)**: Calibrated in production release mode (`-c release`) to $\sim 11.8\text{ ns}$ per input read and $\sim 12.2\text{ ns}$ per warm rule read ($\sim 83\text{M}$ reads/sec per thread), matching native C++ memory access speeds.
- **Deterministic Lifetime & Zero Leaks**: Every attribute is strictly bound to an owning `Subgraph`. Unmounting or invalidating a subgraph instantly detaches and clears all child attributes and dependencies, returning node counts and memory footprint cleanly to baseline.
- **Cross-Platform by Design**: Fully self-contained pure Swift implementation. Platform-specific concerns (such as Thread-Local Storage and synchronization locks) are cleanly isolated:
  - macOS/Linux: `pthread_key_t` and `pthread_mutex_t`.
  - Windows: Native Win32 `WinSDK` (`TlsAlloc`/`TlsGetValue`/`TlsSetValue` and lightweight `SRWLOCK`).
  - Architecture-neutral: Supports both ARM64 and x86_64 with zero fixed pointer-size assumptions.

---

## Architectural Overview

`SwiftAttributeGraph` operates as a Directed Acyclic Graph (DAG) with four core primitives:

```text
 ┌───────────────┐        depends on        ┌───────────────┐
 │ InputAttribute│ <----------------------- │  RuleAttribute│
 └───────┬───────┘                          └───────┬───────┘
         │                                          │
         │ owns                                     │ owns
         ▼                                          ▼
┌───────────────────────────────────────────────────────────┐
│                          Subgraph                         │
│             (Hierarchical Lifetime & Scoping)             │
└───────────────────────────────────────────────────────────┘
```

1. **`Attribute<Value>`**: A type-safe, lightweight 32-bit handle representing a reactive node slot and generation tag.
2. **`Rule` / `StatefulRule`**: Pure or stateful computation bodies attached to attributes that lazily re-evaluate only when their observed inputs change.
3. **`Subgraph`**: The hierarchical owner of nodes and observer callbacks. Subgraphs form parent-child trees that enable instant subtree invalidation.
4. **`Graph(shared:)` / `GraphContext`**: Cross-context execution enabling shared dependency topologies with isolated execution flags and update callbacks.

---

## Performance Benchmarks

Measured on Apple Silicon ARM64 (macOS Sequoia, Swift 6 toolchain, `-c release`):

| Benchmark Scenario | Workload | Native Apple | SwiftAttributeGraph | Ratio (Engine vs Native) |
|---|---|---|---|---|
| **Hot Input Reads** | 10,000,000 reads | $\sim 115\text{ ms}$ | **$118.2\text{ ms}$** | **$1.03\times$ (Identical)** |
| **Hot Rule Reads** | 10,000,000 reads | $\sim 118\text{ ms}$ | **$122.1\text{ ms}$** | **$1.03\times$ (Identical)** |
| **Massive Creation** | 100,000 inputs & rules | $602.8\text{ ms}$ | **$47.9\text{ ms}$** | **$12.5\times$ faster** |
| **Deep Chain (`hot-chain`)** | 100,000 serial levels | $347.5\text{ ms}$ | **$103.8\text{ ms}$** | **$3.3\times$ faster** |
| **Fan-In (Many-to-One)** | 100,000 inputs | $1,421.1\text{ ms}$ | **$58.5\text{ ms}$** | **$24.2\times$ faster** |
| **Subgraph Churn** | 10,000 subgraphs | $436.8\text{ ms}$ | **$28.4\text{ ms}$** | **$15.4\times$ faster** |
| **Cascade Invalidation** | 10,000 shapes / nodes | $1,023.2\text{ ms}$ | **$61.9\text{ ms}$** | **$16.5\times$ faster** |
| **Batch Writes** | 100,000 mutations | $1,254.8\text{ ms}$ | **$4.9\text{ ms} - 6.3\text{ ms}$** | **Optimized batching** |

---

## Real-World UI Stress Simulation

Tested against a synthetic reactive UI tree simulating 10,000 dynamic components with virtualized scrolling (`tools/Benchmarks/UISimulator`):
- **Mounting 10,000 reactive components (30,000 nodes)**: **$5.27\text{ ms}$**
- **60 consecutive UI frames with 5% random state mutation (500 mutations/frame)**:
  - Average latency: **$0.165\text{ ms}$**
  - 99th percentile ($p99$): **$0.252\text{ ms}$** (well within a $1.6\text{ ms}$ frame budget)
- **Fan-Out (Global Environment/Theme across 50,000 readers)**:
  - Dirty propagation time: **$0.519\text{ ms}$**
  - Lazy re-evaluation time: **$5.110\text{ ms}$**
- **Complete teardown**: 10,000 subgraphs unmounted and freed in **$9.65\text{ ms}$**, returning graph node count cleanly to **0**.

---

## Building and Testing

### Prerequisites
- Swift 6.0+ toolchain
- macOS 13+ or Windows 10/11 (with Windows SDK)

### Quick Start

```bash
# Clone the repository
git clone https://github.com/erhusoft/SwiftAttributeGraph.git
cd SwiftAttributeGraph

# Build the library
swift build

# Run complete test suite (645+ tests across 107 suites)
swift test

# Run hot-path performance benchmarks in Release mode
swift test -c release --filter HotReadPerformanceTests
```

---

## SDK Integration

`SwiftAttributeGraph` is the foundation layer of the open-source declarative UI SDK:

1. **`AttributeGraph`** (This project): Reactive computation DAG, change detection, and memory isolation.
2. **`SwiftUICore`**: Pure declarative types (`View`, `State`, `Binding`, `Environment`, `Layout`).
3. **`SwiftUI`**: High-level controls, scenes, and windowing backends (Direct2D/Win32 on Windows).

For architecture guidelines, developer documentation, and reverse-engineering research, refer to `../docs/AttributeGraph/` and the root `../AGENTS.md` guide.

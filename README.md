# SwiftAttributeGraph

A high-performance, zero-recursion reactive attribute graph engine written in pure Swift, engineered from scratch to serve as the core computation engine for declarative UI frameworks (such as SwiftUI/SwiftUICore) on **macOS** and **Windows** (ARM64 & x86_64).

> **Pure computation engine**: `SwiftAttributeGraph` has no knowledge of views, layout, drawing, or windows. It is strictly responsible for reactive dependency tracking (DAG), fine-grained version cuts, iterative lazy evaluation, and deterministic lifecycle management.

---

## Key Highlights

- **Native parity, measured and reported**: behavior is compared with Apple's `AttributeGraph.framework` (macOS 15.8.3, Apple Silicon) by running the same scenarios against both and diffing the output. The result, per area and with the known differences, is in **[COVERAGE.md](COVERAGE.md)**. The API surface follows the native Swift interface: `_AttributeBody`, `Rule`, `StatefulRule`, `RuleContext`, `ObservedAttribute`, `IndirectAttribute`, `OptionalAttribute`, `WeakAttribute`, `PointerOffset`, `withUnsafeTuple`, cached values, output values, the main-thread handler, and Swift runtime enum reflection (`forEachField`, `withUnsafePointerToEnumCase`).
- **Zero-Recursion Guarantee**: All graph mounting, traversal, transitive invalidation, breadth-first search, and lifecycle reclamation are implemented iteratively using flat stacks and explicit queues. Verified with deep dependency chains of **$\ge 20,000$ to $100,000$ levels** with zero stack overflow risk.
- **Ultra-Hot Read Path ($\sim 12\text{ ns}$)**: Calibrated in production release mode (`-c release`) to $\sim 11.8\text{ ns}$ per input read and $\sim 12.2\text{ ns}$ per warm rule read ($\sim 83\text{M}$ reads/sec per thread), matching native C++ memory access speeds.
- **Deterministic Lifetime & Zero Leaks**: Every attribute is strictly bound to an owning `Subgraph`. Unmounting or invalidating a subgraph instantly detaches and clears all child attributes and dependencies, returning node counts and memory footprint cleanly to baseline.
- **Cross-Platform by Design**: Fully self-contained pure Swift implementation. Platform-specific concerns (such as Thread-Local Storage and synchronization locks) are isolated:
  - macOS/Linux: `pthread_key_t` and `pthread_mutex_t`.
  - Windows: Win32 `WinSDK` (`TlsAlloc`/`TlsGetValue`/`TlsSetValue` and `SRWLOCK`).
  - Architecture-neutral: no fixed pointer-size assumptions.
  - **Verification status:** the checks described in this repository (test suite, native comparison, fuzzer) were run on **macOS arm64**. The Windows code paths are written but are not covered by those checks.

---

## Status

| | |
|---|---|
| Native parity (oracle of 211 scenarios) | **All 211 identical** (debug and release, 3 repeats each) |
| Differential fuzzer against the native framework | 0 differences in 55,000 random subgraph hierarchies |
| Public API of the native Swift interface | Compile audit: 177 of the 188 function and property references of the native interface resolve; the other 11 are debug, profiling, tracing and tree recording, and `Graph.typeIndex`, which are out of scope. Every public declaration is documented. See [COVERAGE.md](COVERAGE.md) |
| Unit tests | 825 (`swift test`), including stack-depth and performance tests |
| Still open or never measured | Listed in [COVERAGE.md](COVERAGE.md): creation with no current subgraph, deferral of invalidations during `forEach` and main-thread handlers, `Metadata.forEachField` outside structs, the effect of the `cachedValue` options, multi-thread main-thread handling, Windows |

Parity is claimed per behaviour and per evidence level, not for the framework as a whole. Read [COVERAGE.md](COVERAGE.md) before relying on a
specific API matching Apple's.

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

## Comprehensive Benchmark Suites

`SwiftAttributeGraph` includes a comprehensive suite of performance benchmarks covering every critical execution path. All metrics below are measured on Apple Silicon ARM64 under `-c release` (Swift 6 toolchain, median of 5 warm runs). They come from earlier measurement runs and were **not re-run** for the latest revision; run the commands under *Running the Benchmarks* to reproduce them on your machine.

### 1. Comparative Engine Benchmarks (Native Apple vs SwiftAttributeGraph)

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

### 2. Specialized Production Benchmarks

The engine features dedicated benchmark suites located in `Tests/SwiftAttributeGraphTests/Performance/`:

#### A. Batch Writes Performance (`BatchWritesPerformanceTests`)
- **100,000 sequential writes with dependents**: **$6.29\text{ ms}$** ($\sim 15.9\text{M}$ writes/sec, $63\text{ ns}$ per mutation with propagation).
- **50,000 batched writes under `withoutUpdate`**: **$4.88\text{ ms}$** ($\sim 10.2\text{M}$ writes/sec).

#### B. Memory Footprint & Density (`MemoryFootprintPerformanceTests`)
- **100,000 reactive nodes across 10,000 subgraphs**: **$14.16\text{ MB}$ Mach Resident Memory (RSS)**.
- **Unit density**: **$\sim 148.4\text{ bytes/node}$** (including typed node value, node table entry, and dependency edge list).
- **Reclamation**: Calling `subgraph.invalidate()` reclaims **100% of nodes**, returning `nodeCount` and live storage cleanly to **0**.

#### C. Indirect Dynamic Redirection (`IndirectRedirectPerformanceTests`)
- **100,000 dynamic redirects (`setSource`) across 10,000 active indirect attributes**: **$55.73\text{ ms}$**.
- **Unit latency**: **$\sim 0.56\ \mu\text{s}$ per redirection** ($\sim 1.79\text{M}$ redirects/sec).

#### D. Multi-Threaded Scalability (`MultiThreadContextPerformanceTests`)
- **800,000 concurrent evaluations across 8 worker threads (`TaskGroup`)**: **$51.75\text{ ms}$**.
- **Aggregate throughput**: **$\sim 15.46\text{M}$ evaluations/sec**.
- **Thread-Local Storage (TLS)**: 0 lock contention during evaluation passes.

#### E. Dynamic Edge Pruning (`DynamicEdgePruningPerformanceTests`)
- **250,000 dynamic branch switch & edge-relinking operations (`if/else` simulation)**: **$42.21\text{ ms}$**.
- **Unit latency**: **$\sim 0.17\ \mu\text{s}$ per edge** ($\sim 5.92\text{M}$ dynamic edge mutations/sec, $O(1)$ edge removal).

---

### 3. Real-World UI Stress Simulation (`tools/Benchmarks/UISimulator`)

A stress test simulating a complex, real-world reactive UI application with 10,000 dynamic components and virtualized scrolling:

- **Component Tree Mounting**: 10,000 components ($30,000$ active reactive attributes) mounted in **$5.27\text{ ms}$**.
- **60-Frame Steady State Animation**:
  - Each frame performs 500 random state mutations across the tree.
  - Mean frame computation latency: **$0.165\text{ ms}$**.
  - 99th percentile frame latency ($p99$): **$0.252\text{ ms}$** (comfortably below the $1.6\text{ ms}$ 120 FPS UI budget).
- **Global Theme / Fan-Out Invalidation**:
  - 1 root environment change broadcast to 50,000 reading rules.
  - Dirty notification propagation: **$0.519\text{ ms}$**.
  - Complete lazy update pass: **$5.110\text{ ms}$**.
- **Unmounting & Teardown**: 10,000 subgraphs destroyed in **$9.65\text{ ms}$**, returning graph node count cleanly to **0**.

---

## Running the Benchmarks

All benchmark targets can be executed directly using the Swift toolchain:

```bash
# 1. Run ultra-hot read microbenchmarks (10M warm reads)
swift test -c release --filter HotReadPerformanceTests

# 2. Run memory footprint and RSS density benchmark
swift test -c release --filter MemoryFootprintPerformanceTests

# 3. Run high-throughput batch writes benchmark
swift test -c release --filter BatchWritesPerformanceTests

# 4. Run multi-threaded concurrency benchmark (8 threads)
swift test -c release --filter MultiThreadContextPerformanceTests

# 5. Run dynamic edge pruning benchmark
swift test -c release --filter DynamicEdgePruningPerformanceTests

# 6. Run the standalone Real-World UI Stress Benchmark (from tools/)
cd ../tools/Benchmarks
swift run -c release StressBenchmark
```

---

## Testing

```bash
swift build
swift test                                                      # full suite (debug)
swift test -c release -Xswiftc -enable-testing --filter Depth   # stack-depth contract in release
swift test -c release -Xswiftc -enable-testing --filter Performance
```

Requirements: Swift 6 toolchain, macOS 13 or later (see `Package.swift`). The native comparison needs a Mac and a probe that links Apple's
private framework, so it is a development tool and is not part of this package; its method and results are summarised in
[COVERAGE.md](COVERAGE.md).

---

## SDK Integration

`SwiftAttributeGraph` is the foundation layer of the declarative UI SDK:

1. **`AttributeGraph`** (This project): Reactive computation DAG, change detection, and memory isolation.
2. **`SwiftUICore`**: Pure declarative types (`View`, `State`, `Binding`, `Environment`, `Layout`).
3. **`SwiftUI`**: High-level controls, scenes, and windowing backends (Direct2D/Win32 on Windows).

---

## License

Licensed under the [Apache License, Version 2.0](LICENSE). Copyright 2026 Jonathan Stasky and the SwiftAttributeGraph project authors.

You may use, modify and redistribute this software, including in commercial products, provided that you keep the copyright
notices and the [NOTICE](NOTICE) file, state the changes you made to modified files, and include a copy of the license. Contributions
are welcome under the same license with a `Signed-off-by` line; see [CONTRIBUTING.md](CONTRIBUTING.md).

This project is independent of Apple Inc. Apple, macOS, Swift, SwiftUI and AttributeGraph are trademarks of Apple Inc.

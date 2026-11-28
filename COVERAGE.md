# API coverage and native parity

This document says what `SwiftAttributeGraph` implements, how closely each part behaves like Apple's `AttributeGraph.framework`, and what is
still open or was never measured. It is a status report, not a promise: where parity was not measured it says so.

- **Reference:** the `AttributeGraph.framework` that ships with **macOS 15.8.3** (build 24H241, Apple Silicon). It is the only reference used for
  measurements. APIs that exist only in a newer SDK are out of scope (see [Out of scope](#out-of-scope)).
- **Last verified:** 2026-11-27, on macOS arm64.

## How parity is established

The engine is written from scratch. Its behaviour is compared with the native framework by a **differential oracle**: a small probe program is
compiled twice, once against Apple's framework and once against this package, and the same scenario runs on both sides. Each scenario prints one
line per observation, and the lines are compared. Scenarios are run in debug and release, three times each, in separate processes (a native
abort is not a finding until the probe itself is ruled out as its cause).

Every row below carries one of these evidence levels:

| Level | Meaning |
|---|---|
| **O** | *Oracle-identical.* The same scenario ran on the native framework and on the engine, with identical output. |
| **M** | *Measured natively, verified by unit tests.* The behaviour was measured on the native framework, and the engine's unit tests encode the measured values. The probe could not run the scenario on the engine's side because it uses Apple-only API spellings the engine does not have (for example `Subgraph.apply` or `Attribute(body:value:flags:update:)`). A test written by hand can fix a wrongly copied value, so **M is weaker than O**. |
| **S** | *Specified, not measured.* Implemented from the public headers and the Swift interface, covered by unit tests, never compared with the native framework. |

## Summary

| Measure | Result |
|---|---|
| Oracle scenarios (211) | **All 211 identical**; stable over 3 repeats, debug and release |
| Differential fuzzer of the whole graph (subgraphs, attributes, rules, flags, invalidations, deferrals; 2 contexts) | **0 differences in 20,000 sequences of 40 operations** (debug and release); 1 in the next 50,000 (seed 76354); 1 in 5,000 sequences of 80 operations (seed 4863, an order of `forEach`); four defective older engines are detected in 32 to 46 % of the sequences. See the fuzzer notes below |
| Engine unit tests | 832 tests, including performance and stack-depth tests |
| Public declarations of the native Swift interface | **Compile audit:** 177 of 188 function and property references resolve against the engine. The other 11 are out of scope (see [Out of scope](#out-of-scope)) |

How the API count was made: a Swift file with one reference per function and property of the native Swift interface (with its argument labels) is
compiled against the engine. An error saying the member does not exist is a gap; any other error (a generic parameter that cannot be inferred, an
instance member used on its type) means the name resolves. Counting names in the sources does not work for `init`, `subscript` and common names such
as `description`, and an earlier version of this page used it and claimed 251 of 252; that figure was wrong. Initializers and subscripts are not covered by this compile audit: initializers were checked one by one when the creation API was added (not re-run since), and the `cov79-a-*` oracle scenarios cover the subscripts. A reference that resolves says nothing
about behaviour: the evidence levels below are the statement about behaviour.

## Fuzzer notes

The full-graph fuzzer (`GraphFuzzer.swift` of the probe, run by Gemini and audited here) generates deterministic sequences from a seed, runs them on native and on the engine, and compares the whole trace; an abort counts as the same result when it happens in the same operation. It keeps away from the behaviours accepted as differences (reading an attribute of an invalidated subgraph, writing an attribute that was given an input). What it does not generate: indirect and offset attributes, values other than integers, resumable rules, cancellation, reflection, and the cached values. Seeds 1995, 24432 and 62457 were isolated and fixed (an input read from outside a rule is not updated through its `addInput` edges). Two kinds still differ: the `forEach` order of seeds 4863 and 37437 (difference 12), and nothing else is known to differ after the last fix (seeds 76354 and 127117, see the row on pending invalidations).

## Parity by area

| Area | Implemented | Evidence | Notes |
|---|---|---|---|
| **Subgraph lifetime, hierarchy and invalidation order** (create, link, unlink, release of the last handle, shared children, children in other contexts, tags, parents, observers) | Yes | **O** | Hundreds of observations in the scenarios plus the fuzzer. Releasing the last handle invalidates the subgraph, as natively. Invalidations a rule asks for are delivered where native delivers them: not when the read ends, but in the next explicit update, invalidation, `forEach`, end of a deferral or invalidation of a context, most recent request first. |
| **Graph contexts** (shared contexts, context ids, update and invalidation callbacks, needs-update state) | Yes | **O** | |
| **Reads, writes, dirty and pending state, version cuts, prefetch, transactions, deadline, cooperative cancellation, diamonds** | Yes | **O** | |
| **Cold dependency chains** (first evaluation of a deep chain) | Yes | **O**, plus engine depth tests | The engine adds a stack-budget guard and resumable rules, which have no native counterpart (see [Engine-only features](#engine-only-features)). |
| **Indirect, offset, weak, optional and erased attributes** | Yes | **O** | Includes `unsafeCast(to:)`, dynamic member lookup on `WeakAttribute` and `OptionalAttribute`, and the casts of `AnyOptionalAttribute` and `AnyWeakAttribute`. |
| **Comparison** (`compareValues`, `ComparisonMode`, `ComparisonOptions`) | Yes | **O** | The cold path of the native comparison (first call, layouts built asynchronously, compares bytes) is deliberately not reproduced. |
| **`Rule`, `StatefulRule`, `RuleContext`, `AnyRuleContext`, `Map`, `Focus`, `External`, `ObservedAttribute`, `_AttributeBody`** | Yes | **O** and **M** | Stateful reads, `changedValue`, `valueAndFlags`, `RuleContext(attribute:)`. `RuleContext.hasChanged` is covered by unit tests only (level **S**). The body defaults are **M** (see the next row). |
| **`AttributeTypeFlags` and the defaults of `flags`, `comparisonMode`, `_hasDestroySelf`** | Yes | **M** | Bits follow the native header. A plain body, a rule and a stateful rule default to flags `mainThread` and mode `equatableUnlessPOD`; `External` to no flags and `equatableAlways`; `Map` and `Focus` to no flags. Nothing in the engine reads these values. |
| **`Rule.cachedValue`, `cachedValueIfExists`, `_cachedValue`** | Yes | **M** | Key is the rule type plus `==`; one cache per subgraph; the `owner` picks the subgraph; changed inputs re-evaluate. Aging matches native: an entry is parked with age 1, each *pass* (an invalidation, `update(_:flags:)` or the end of a deferral of invalidations) adds 1, it is freed at 255, and a new key takes over the oldest parked entry of age 2 or more. |
| **`Graph.withMainThreadHandler`, `mainUpdates`** | Yes | **M** | A dirty rule read from the top goes through the handler once; the handler is off while its closure runs; a clean rule never calls it. Handlers nest. |
| **`Graph.outputValue`, `setOutputValue`** | Yes | **M** | Nil before the first write, previous value on a later run, last write wins, equal values cut propagation, a rule's `return` replaces what was written. |
| **`AnyAttribute.valueType`, `_bodyType`, `_bodyPointer`, `indirectDependency`** | Yes | **M** | Indirect and offset attributes stop the program where native does. |
| **`Attribute.unsafeOffset(at:as:)`, `AnyAttribute.unsafeOffset(at:)`** | Yes | **M** | The erased variant makes a typeless attribute and materialises the typed one when it is cast, once per type. |
| **Tuples** (`TupleType`, `UnsafeTuple`, `UnsafeMutableTuple`, `withUnsafeTuple`) | Yes | **O** | Real Swift layout (alignment per element, no trailing padding); destruction releases the elements. |
| **`Metadata.forEachField`, `withUnsafePointerToEnumCase`** | Yes | **O** for structs | See [Not measured](#not-measured-or-pending) for classes and enums. |
| **Creation API** (`Attribute(value:)`, `Attribute(type:)`, `Attribute(_:)` for `Rule` and `StatefulRule`, `Attribute(identifier:)`, `WeakAttribute(base:)`) | Yes | **M** | Takes the graph from the current subgraph and stops the program without one, as native does (`attempting to create attribute with no subgraph`). |
| **`Rule` and `StatefulRule` members** (`attribute`, `context`, `initialValue`, and for stateful rules `value`, `hasValue`, `updateValue()`), **`Subgraph.forEach`**, **`mutateBody` and `addInput(_:options:token:)` on `Attribute` and `AnyAttribute`**, `AnyAttribute.current`, `description` of `AnyAttribute` and `AnyWeakAttribute`, `OptionalAttribute.changedValue(options:)` | Yes | **O** | Round `api17` and its follow-up: the same scenarios ran on both sides with identical output, except the `valueState` raw numbers (native 83 and 88, engine 1 and 8: a different encoding, not compared). `StatefulRule.initialValue` is not visible inside `updateValue()`, as natively (`hasValue` is false on the first run and reading `value` stops the program), and `mutateBody(as: External<Value>.self)` runs on a value attribute. After these three differences were found the engine was changed and covered by unit tests; those scenarios were not re-run on both sides (**M**). `addInput` options and token showed no effect on the number of evaluations; the order of the inputs was not measured. |
| **`Subgraph.intersects(flags:)` and the cut of `forEach`** | Yes | **O** | Native reads a summary of flags per subgraph that only grows: it includes the descendants, it is not reduced by clearing a flag, unlinking a child or the death of a child, and a child that waits to be invalidated still answers `true` while one that was invalidated answers `false` (its parents keep the bit). `forEach` leaves at once when the summary does not intersect and otherwise delivers the pending invalidations at its end even if it visits nothing. Measured in `ver6c` to `ver9g`, implemented, and re-run on both sides in `ver6c` to `ver10f` (30 scenarios, debug and release, 3 repeats, identical). `Subgraph.update(flags:)` does not reduce the summary. A shared child unlinked from one parent leaves that parent's summary. A subgraph invalidated for real answers `false` and visits nothing. |
| **Pending invalidations and `isValid`** | Yes | **M** | Found by the full-graph fuzzer. While an invalidation waits (inside a rule, a `forEach` callback, `withoutSubgraphInvalidation` or `withMainThreadHandler`), only the requested subgraph reads as invalid; its children stay valid until delivery (`ver14b1a` to `ver14b1d`). Dropping the handle of a pending subgraph delivers nothing; dropping the handle of one of its children delivers the pending request (`ver14b2`). Implemented from those measurements, not re-run on both sides. |
| **Writing an attribute that has an input** | Yes | **M** | Native stops in `value_set` when a value attribute was given an input with `addInput` and is then written (`ver14b3b`); the engine now stops too. Adding the input alone, and writing the source of a rule, are fine in both (`ver14b3a` to `ver14b3d`). |
| **`Subgraph.forEach` and the order of visit** | Yes | **M** | Measured in `ver15a` and `ver15b`: a flag mask matches when it shares at least one bit with the attribute's flags, in `intersects`, `forEach` and `update` alike (same on both sides). Native visits the attributes of a subgraph in the reverse of the order their flags were set (not of their creation); the engine now does. Native keeps the attributes of a subgraph in pages of 12 (the same for `Int`, `String` and rules; `ver19b`) and visits the newest page first, then each page in the reverse of the order the flags were set; the engine counts 12 per subgraph by creation order, which is exact for plain attributes (indirect and offset attributes may take space natively that the engine does not count). Setting the flags of an attribute that already has some, or changing them, keeps its place; clearing them and setting them again moves it to the front (`ver16a`, same on both sides). `forEach` does not go down into a child that lives in another context, nor into what is below it, although `intersects` counts it (`ver16`, seed 5022, and the decompiled `Subgraph::apply` of 15.8.3, which pushes the children only of the subgraphs it processes). |
| **`Subgraph.update(flags:)` delivery** | Yes | **M** | Native delivers the pending invalidations after each subgraph the walk processes, not only at the end (decompiled `Subgraph::update` of 15.8.3; fuzzer seed 4083). Implemented; the update walk of the engine is still not the stack walk of native, and the context rule of `forEach` was not checked for `update`. |
| **`addInput` on inputs and on existing edges** | Yes | **M** | Found by the full-graph fuzzer (seeds 1419, 19905, 1995, 24432, 62457). An input that was given an edge is not brought up to date when it is read from outside a rule (its sources are not evaluated), so writing it afterwards stops the program (`ver14b3b`, `ver19a3`); read from inside a rule it is brought up to date and its edges are dropped (`ver19a4`, `ver19a12`, seed 12182). Adding an edge that already exists moves nothing, so the rule still runs again after its input changed. Implemented from the fuzzer traces and the matrix `ver19a`; `ver20a`, `ver20b` not re-run on both sides. |
| **Pending invalidation and the inputs of a rule** | Yes | **M** | Native does not bring up to date an input whose subgraph waits to be invalidated when it checks the inputs of a rule: it counts it as changed and runs the rule (decompiled `UpdateStack::update` of 15.8.3; fuzzer seeds 76354 and 127117 matched with it). The first version skipped every such input and broke 11 sequences that gave the right value before (seed 1258: the value was stale); it now skips only an input that has no value yet, which fixes both families on the seeds compared with the previous engine. No isolated scenario tells the two cases apart yet. |
| **Writing a rule or an input** | Yes | **M** | Native `value_set` stops (`can only set initial value of computed attributes`) only when the attribute has at least one input edge and already has a value (decompiled 15.8.3; matrix A of the oracle, 16 cells). So an input that was given an edge cannot be written, a rule that has not run can be given a value and still runs on its next read (its result replaces the value), and a rule that read something cannot be written. The engine used to stop on every write to a rule. Not re-run on both sides. |
| **`Subgraph.apply(_:)`** | Yes | **M** | Makes the subgraph current and delivers no pending invalidation when it ends (`fup-c`). Invalidations asked for inside a rule wait for the next `forEach`, update or invalidation. |
| **`Attribute.value` read outside a rule** | Yes | **O** | Evaluates, caches and records no dependency. Two scenarios abort natively and differ (see below). |
| **`visitBody`, `mutateBody`, `breadthFirstSearch`** | Yes | **O** | |
| **Documentation** | Yes | n/a | Every public declaration (519 at the time of writing) has a `///` comment. |

## Known differences from the native framework

These are behaviours where the engine is known to differ. They are intentional unless marked *open*.

| # | Difference | Status |
|---|---|---|
| 1 | **Creating an attribute with no current subgraph** aborts natively (`attempting to create attribute with no subgraph`). The Apple spellings (`Attribute(value:)` and the others) abort too, but the graph-level methods (`Graph.makeInput` and similar) still create the attribute. | *Open* for the graph-level methods. |
| 2 | **Reading an attribute whose subgraph was invalidated, outside a rule,** crashes natively (a segmentation fault, effectively undefined behaviour). The engine stops with a message. | Intentional. |
| 3 | **`Graph.outputValue` and `setOutputValue` outside an update** crash natively with no message. The engine stops with `no attribute updating`. | Intentional. |
| 4 | **`cachedValueIfExists` on a subgraph that never cached a rule of that type** crashes natively (the native code calls a missing closure). The engine returns `nil`. | Intentional. |
| 5 | **A handler for `withMainThreadHandler` that runs its closure twice** crashes natively. The engine does not guard against it. A handler that never runs it stops the program in both. | Intentional. |
| 6 | **Recycling a cache entry** reuses the node natively; the engine frees it and makes a fresh one. Values and the number of evaluations agree; only the attribute identity differs. | Intentional, observable only through identifiers. |
| 8 | **`Rule.attribute`, `Rule.context`, `StatefulRule.attribute` and `StatefulRule.context` read outside a rule** return a meaningless identifier natively (`#4235821056` in the runs, no abort). The engine stops with a message. | Intentional. |
| 7 | **Casting an erased offset attribute** returns another identifier than the erased attribute. Natively the identifier was not compared. | Not measured. |
| 9 | **Reading, from a live rule, an attribute whose subgraph was invalidated** stops the program in the engine. Native stops, crashes (`SIGBUS`, `SIGSEGV`) or reports a false cycle in nine scenarios built for it (`ver17a0` to `ver17a9`), and returns `0` only for a rule with no inputs; the fuzzer found sequences where it returns `0` or the previous value. What it does depends on what is left in the freed slot: undefined behaviour. | Intentional. |
| 10 | **Order of the notices when pending invalidations and handle drops mix in a tree with shared children** (`ver15c2` to `ver15c5`, `ver16c1` to `ver16c4`). Cause found for the diamond (`ver16c2`): the engine rearranged the children at the moment of the request, and native only does it when it delivers it (`invalidate_and_delete_` and `invalidate_now` of 15.8.3). Fixed and covered by a unit test; the other three cases have not been re-run on both sides. | *Open* until re-run. |
| 11 | **Writing an attribute that was given an input with `addInput`**: native stops with `can only set initial value of computed attributes`, except in two sequences (`ver19a4`, `ver19a12`: the source changed and the attribute was read from inside another rule before). The engine stops in all of them. The condition natively depends on internal node fields not decoded; the case is rare (nothing writes an attribute it gave an input). `ver19a8` (the source is a rule that never ran, then `mutateBody`, a read from a rule and the write) still differs: native stops, the engine writes. | Accepted. |
| 12 | **Order of `forEach` in two fuzzer sequences (seeds 4863 and 37437)**: native visits two or three flagged attributes of a subgroup in another order than the engine (`a9, a5, a1` against `a5, a1, a9`). Narrowed down in `ver22a` and `ver22b`: in the sequence of seed 37437 the order changes only if a rule that depends on others is read before the flags are set (removing that single read gives the order of the engine); the mix of types, dead subgraphs, deferral scopes, clearing flags and the order of creation do not matter. This fits with native placing the value of a rule in the same page when it first runs, which moves the page limit; the engine does not model that. | Accepted: the order is the same when no rule ran before; every attribute is still visited once. |

## Not measured or pending

- **Deferral of invalidations while a main-thread handler is installed:** measured and re-run on both sides (`ver11a`, `ver12a`, `ver13b1` to `ver13b4`,
  level **O**): everything asked for inside the body of `withMainThreadHandler`, also inside a nested `withoutSubgraphInvalidation` or a nested handler,
  waits and is not delivered when the body ends. An external invalidation, `update(flags:)` and `forEach` deliver it; reading a trivial rule does not.
- **Where `Subgraph.update`, `withoutInvalidating` and a context invalidation deliver** is known from the native code; only `forEach` was measured on
  both sides.
- **`Metadata.forEachField`:** measured and re-run on both sides (`ver11d`, `ver12d`, `ver13b6`, `ver13b7`, level **O**) for structs, classes, enums (payload
  cases numbered by position, no-payload cases skipped, generic, nested and indirect payloads), tuples, closure and existential fields. Not found: a
  field type that makes the walk stop, so `continueAfterUnknownField` has no observed effect.
- **`Rule.cachedValue` options.** The five option bits showed no observable effect on values or evaluation counts in any scenario, so the engine
  accepts and ignores them. Whether they matter in other situations (for example while an update is running, on edge flags) is unknown.
  A hash collision with a different body pointer in `_cachedValue` was not measured either.
- **Main-thread handling beyond the single-thread case.** The Swift API only creates main-thread rules, so a rule without the main-thread bit
  was never measured, and the handler was never measured dispatching to another thread.
- **`AnyAttribute._bodyPointer` of an input.** Only "a valid pointer" is established, because the body of an input stores nothing.
- **Some abort messages** were read from the native framework's logic and not observed in a run (the message for `indirectDependency` on a direct
  attribute, and for an offset read out of range). The engine stops in both cases.
- **Direct oracle runs of the newer APIs.** Cached values, the main-thread handler, output values, `AnyAttribute` introspection and the flag defaults
  are at evidence level **M**. Running them on both sides needs adapter code for the Apple-only API spellings; until then the unit tests are the
  engine side of the comparison.
- **Independence of `flags` and `comparisonMode` in one direction.** Overriding `flags` leaves the mode alone (measured); overriding the mode to a
  value other than the default and checking `flags` was not (the probe overrode it with the default).
- **Windows.** The Windows code paths (thread-local storage and locks through `WinSDK`) are written, but everything on this page was verified on
  macOS arm64 only.
- **Part of the probe source was lost.** The probe's scenario files for the first rounds of the newer APIs were overwritten by later rounds, so
  those scenarios cannot be re-run as they were. Their measured lines are preserved as comments in the unit tests.

## Engine-only features

These have no native counterpart, so no parity claim is made: resumable rules (`makeResumableRule`), the stack-budget guard for nested closure
updates, and the performance work behind the benchmarks in the README. They are covered by the engine's own depth and performance tests.

## Out of scope

- **Debug, tracing, profiling, archiving and tree recording** (`startProfiling`, `archiveJSON`, `beginTreeElement` and similar).
- **`Graph.typeIndex`**, the profiling functions (`startProfiling`, `stopProfiling`, `resetProfile`), `archiveJSON` and the tree-recording functions are the 11 references of the compile audit that do not resolve. `Graph.typeIndex` and 22 other symbols that appear in the Swift interface and header set used for the probe but **do not exist in
  macOS 15.8.3**. The interface came from a newer SDK. Each was checked against the system library of the reference machine. The C functions are
  `AGGraphCreateIndirectAttribute3`, `AGGraphSetIndirectAttribute2`, `AGGraphExternalMallocZone`, `AGGraphVMRegionMallocZone`,
  `AGMallocZoneGetCurrentSwiftMetadata`, `AGOverrideEqualityForTypeDescriptor` and `AGSubgraphMove`; the Swift ones include the `_External` type.
  The engine keeps a `_External` type from that interface; it is harmless.

## Reproducing the comparison

The probe is a small Swift package with two build modes: one links Apple's framework, the other links this package. The scenario names, the
number of runs and the comparison rules are as described above. A scenario is accepted only if it changes one factor with respect to its reference
scenario and the engine and the native outputs agree in debug and release over three runs. The probe itself is a development tool and is not part
of this package.

The engine's own checks run with:

```bash
swift test                                              # full suite, debug
swift test -c release -Xswiftc -enable-testing --filter Depth   # stack-depth contract in release
```

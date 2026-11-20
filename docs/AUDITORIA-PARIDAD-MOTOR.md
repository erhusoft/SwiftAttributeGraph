## Estado al 2026-11-19

- **Escenarios medidos contra Apple (`NativeProbe/run.py`):** **132** trazas directas coinciden en las 6 pasadas (`debug` 1..3 y `release` 1..3, `EXIT=0`).
- **Cobertura SwiftUICore (`SWIFTUICORE_CRUCE_CORE_MOTOR_V2.md`):** de **116** funciones importadas de `AttributeGraph` (**66** aplican al motor), quedan cerradas además `GetCounter`, `GetAttributeGraph`, `SubgraphGetCurrent`, `GetCurrentAttribute` y `CurrentAttributeWasModified`.
- **Referencia de rendimiento actual:** `633e3de` / `7991c61` (sustituye a `678abb0`).
- **Nota `[?]`:** las 41 pruebas de `AGProbeParityTests` se marcan como `[?]` (origen no verificado en esta tanda).
- **Abiertos:** contextos completos (dependencias y callback de invalidación), `WithMainThreadHandler` y `WithUpdate`, duplicado y `tag` de `AddChild2`, `Create2` con atributo, Windows.

# Auditoría de Paridad del Motor (`SwiftAttributeGraph` vs `AttributeGraph.framework`)

- **Rama auditada:** `codex/native-adaptations-integration` en `/Users/erhusoft/NativeAttributeGraphBackendProbe/sag_integration_worktree`
- **Oráculo vivo:** `NativeProbe/run.py` (**132/132** escenarios coinciden en `debug` y `release` (3 repeticiones por configuración, debug y release)).
- **Nota sobre `AGProbeParityTests`:** Los 41 tests iniciales introducidos en `109b947` (`test(Parity): add 41 AGProbe parity scenarios against Apple AttributeGraph`) no conservan en el repositorio el binario o registro nativo original que los generó (`[?]`); en cambio, los escenarios `oracle1..oracle12` y las **132 trazas** de `NativeProbe` (`fab8eda`, `68e6eb3` y posteriores) sí se ejecutan directamente contra `AttributeGraph.framework` mediante `NativeProbe/run.py`.

## Matriz de Paridad

| Mecanismo | Nativo `[O]` / `[?]` (dirección y fase) | Nuestro archivo y símbolo | Escenarios de `NativeProbe` (82 totales) | Estado | Siguiente paso |
|---|---|---|---|---|---|
| **Indirectos: creación, redirección, reset** | `[O]` `AGGraphCreateIndirectAttribute`, `AGGraphSetIndirectAttribute`, `AGGraphResetIndirectAttribute` (`PHASE5_INDIRECT_NODES.md`) | `Graph.swift` (`makeIndirect`, `setSource`, `resetSource`), `Graph+IndirectResolution.swift` (`resolveIndirect`) | `indirect-rule-and-redirect`, `indirect-set-same-value`, `indirect-reset-source-multi-redirect`, `indirect-chain-and-intermediate-death`, `indirect-dependency-cut-and-redirect`, `indirect-source-invalidated`, `indirect-original-dies-while-redirected` | **Paridad medida** | — |
| **Atributos offset / rango (`keyPath`)** | `[O]` `AGAttribute` offset / `AGGraphCreateOffsetAttribute` (`PHASE5_INDIRECT_NODES.md`) | `Graph+OffsetAttribute.swift` (`makeOffsetIndirect`, `makeOffsetFieldAttribute`), `Graph+EdgePartialCompare.swift` | `offset-range-inside-outside`, `offset-sticky-inside-then-outside`, `offset-mixed-chain`, `offset-whole-value`, `focus-keypath-cut` | **Paridad medida** | Probar `setSource`/`resetSource` sobre offset-campo `[?]` |
| **Escritura sobre indirecto / offset** | `[O]` `AGGraphSetValue` aborta con `SIGABRT` (exit `134`) en indirecto normal (`probe_write_indirect`) y en offset (`probe_write_offset`); fuente normal exit `0` | `Graph+Update.swift` (`setValue(_:for:)`: rechaza offset-campo con `precondition`, reenvía indirecto normal al origen) | Medido en `native-scratch` (`probe_write_indirect`, `probe_write_offset`, `probe_write_source`) | **Diferencia conocida** (indirecto normal: nativo aborta, nuestro motor reenvía; tests `IndirectTests` / `IndirectPerformanceTests` dependen de ello) | Mantener diferencia documentada |
| **Comparación de arista directa** | `[O]` `LayoutDescriptor::compare` / `value_set_internal` (`PHASE4_UPDATE_EVALUATION.md`) | `Graph+Update.swift`, `ValueComparator.swift` | `direct-edge-equal-and-different-write` | **Paridad medida** | — |
| **Subgraph DAG (`addChild`)** | `[O]` `AGSubgraphAddChild` (`AGSubgraph.h`, `PHASE13_GRAPH150_AND_INVALIDATION.md`) | `SubgraphTable.swift`, `Graph+Invalidation.swift` (`addChild`, `invalidate`) | `subgraph-dag-add-child` (mismo contexto) | **Paridad medida** (mismo contexto); `[?]` distinto contexto en mismo `Graph` (`GraphContext` sin init público en `native-interfaces`) | Investigar vía C/ObjC o mantener `[?]` |
| **Cancelación cooperativa** | `[O]` `_AGGraphCancelUpdate` (`0x1b1a6e668`), `UpdateStack::cancel` (`0x1b1a4ed88`), `update_attribute` (`0x1b1a4edf0`, `PHASE4_UPDATE_EVALUATION.md` §4–§6) | `Graph+Update.swift` (`cancelUpdate`, cierre sin limpiar `dirty` y conservando valor devuelto), `NodeBox.swift` | `cooperative-cancel`, `cooperative-cancel-consumer`, `cooperative-cancel-nested`, `cooperative-cancel-first-eval` | **Paridad medida** | — |
| **Context `setNeedsUpdate` / `call_update`** | `[O]` `Context::set_needs_update` (`0x0000F218`), `AG::Graph::call_update` (`0x00010130`, `ATTRIBUTEGRAPH_END_TO_END_MAP.md` §3) | `GraphContext.swift` (`setNeedsUpdate`), `Graph+NodeCache.swift`, `Graph+Update.swift` | `context-update-callback`, `context-update-callback-on-write` | **Paridad medida** | — |
| **Atributos débiles (`WeakAttribute`)** | `[O]` `AGCreateWeakAttribute`, `AGWeakAttributeGetAttribute` (`PHASE10_WEAK_ATTRS_AND_BIT3_MAP.md`) | `WeakAttribute.swift` | `weak-attribute-in-rule`, `random-subgraph-weak-indirect-oracle` | **Paridad medida** | — |
| **`anyInputsChanged` (bit `0x10`)** | `[O]` `AGGraphAnyInputsChanged` (`0x0002A7BC`) -> `AG::Graph::any_inputs_changed` (`0x0001341C`, `PHASE6_NODE7_AND_INPUT_OPTIONS.md`) | `Graph+Update.swift`, `RuleContext.swift` (`anyInputsChanged(excluding:)`) | `any-inputs-changed` | **Paridad medida** | — |
| **`invalidateValue` y `isDirty` de subgrafo** | `[O]` `AGGraphInvalidateValue` (`0x0002970C`) -> `value_mark` (`0x00012B54`), `AGSubgraphIsDirty` (`0x1b1a66b64`, `PHASE14_SUBGRAPH_FLAGS_INVALIDATION_TRACES.md`) | `SubgraphTable.swift`, `Graph.swift`, `Graph+Update.swift` | `subgraph-flags-forEach-and-update`, `invalidate-value-and-subgraph-dirty` | **Paridad medida** | — |
| **`NodeCache` (`cache_fetch` / `cache_collect`)** | `[O]` `PHASE12_SUBGRAPH_TREE_NODECACHE.md` | `SubgraphNodeCache.swift`, `Graph+NodeCache.swift` | — | **Funcional sin oráculo** | Verificar exposición en `native-interfaces` |
| **Ciclos (`_updateDefault`)** | `[?]` `AG::Graph::UpdateStack::push_slow` (`PHASE4_UPDATE_EVALUATION.md`) | `Graph+Update.swift` | — | **Funcional sin oráculo** | Medir con `AGGraphSetUpdate` / regla cíclica |
| **Observadores de subgrafo** | `[O]` `AGSubgraphAddObserver` (`AGSubgraph.h`) | `SubgraphTable.swift`, `Graph+Invalidation.swift` | Cubierto en `NativeProbe` (`fab8eda`) | **Paridad medida** | — |
| **`AGProbeParityTests` (41 tests iniciales)** | `[?]` Origen histórico sin traza nativa en repo (`109b947`) | `Tests/SwiftAttributeGraphTests/Parity/AGProbeParityTests.swift` | Cubiertos por tests equivalentes en `NativeProbe` (`fab8eda`, `68e6eb3`) | **Histórico `[?]`** | Referenciar `NativeProbe` como fuente viva |
| **`AGGraphGetCounter`** | `[O]` `AGGraph.h:90`, 14 selectores (`AGGraphCounterQueryType.h`); valores medidos en aislado (`gc1..gc5`, `nc1..nc5` en `native-scratch`) | `Graph+Counters.swift` (`Graph.counter(for:)`, `CounterQueryType`) | `get-counter`, `get-counter-context` | **Paridad medida en los 14 selectores** (`nodes` y `createdNodes` ya sin indirectos, commit `53ee547`; `contextID`, `graphID`, `threadUpdating`, `contextThreadUpdating`, `needsUpdate`, `contextNeedsUpdate` y `mainThreadUpdates`, commit `af13f33`, escenario `95c9644`); contextos compartidos (`AGGraphCreateShared`): **modelo mínimo implementado** (`makeSharedContext()`; `makeContext()` ahora consume número de contexto; `contextID`, `contextNeedsUpdate` y `contextThreadUpdating` por contexto vía `GraphContext.counter(for:)`; escenarios `shared-context-*`, incl. `shared-context-input-read`); `[?]` fuera del modelo: dependencias entre contextos, `AGGraphSetInvalidationCallback`, `SetContext`/`GetContext` y `WithMainThreadHandler`; `mainThreadUpdates` no mira el hilo (nativo = `updates` también en un `Thread` secundario) | Medir dependencias entre contextos y el callback de invalidación entre contextos si el core los necesita; buscar un caso donde `mainThreadUpdates` difiera de `updates` |
| **`AGGraphGetAttributeGraph` / `AGSubgraphGetGraph`** | `[O]` `AGAttribute.h:142`, `AGSubgraph.h:57`; devuelven el mismo objeto con que se creó; con atributo/subgrafo muertos aborta (`exit 134`) | `Graph+OwnerLookup.swift` (`Attribute.graph`, `AnyAttribute.graph`, `Subgraph.graph`, `Graph.graph(of:)`), `GraphRegistry.swift` | `get-attribute-graph` | **Paridad medida** (identidad con dos grafos); `Graph.graph(of:)` devuelve `nil` donde el nativo aborta | — |
| **`AGSubgraphGetCurrent` / `AGSubgraphSetCurrent`** | `[O]` `AGSubgraph.h:37,41`; `nil` fuera, el subgrafo dentro de `apply`, restaura al anidar, `nil` al invalidar el actual, una regla no lo cambia | `Subgraph+Current.swift` (`Subgraph.current`), `ThreadLocalGraph.swift` (`ThreadLocalSubgraph`) | `get-subgraph-current` | **Paridad medida** salvo `Subgraph.current = nil` (el grafo sigue creando en el último subgrafo fijado `[?]`) | `AGSubgraphGetCurrentGraphContext` sin medir |
| **Profundidad de cadena fría** (primera lectura de N reglas closure encadenadas, sin calentar) | `[O]` nativo: SIGSEGV por desbordamiento de pila (`EXC_BAD_ACCESS` en `Graph::value_ref`) desde ≈ 8.700 niveles en 8 MB y ≈ 500 en 512 KB; `update_attribute` re-entra por el cuerpo de la regla (`0x1b1a566a4`/`0x1b1a56e58`) `[?]` interpretación | `Graph+Update` / `ResumableRule` (`makeResumableRule`) | `cold-chain-depth` (N=500; ambos agarran); sondas aisladas `native-scratch/depth` | **Ambos desbordan** en frío con closures: nativo ≈ 8.700, nuestro motor ≈ 5.600 (release, 8 MB; debug ≈ 800); con `ResumableRule` 500.000 niveles OK; calentar evita el fallo en ambos | Documentar el límite; test de frío closure N≈4.000; reducir bytes/nivel (ver `PROFUNDIDAD_FRIA_NATIVO_VS_MOTOR.md`) |
- **`any-inputs-changed-offset-edge`, `any-inputs-changed-first-eval-before-read`, `any-inputs-changed-first-eval-after-read`, `any-inputs-changed-second-eval-after-write` (`[O]`, `93/93` trazas coinciden, `PASS debug/release run 1..3`):**
  - Motor alineado en `1b262d8`: `anyInputChanged` devuelve `false` cuando no hay aristas cambiadas (primera evaluación antes de leer) y `recordRead` marca `changed: true` en aristas nuevas.
- **`subgraph-add-child-secondary-parent` (`[O]`, `93/93` trazas coinciden, `PASS debug/release run 1..3`):**
  - `AGSubgraphAddChild2(p2, child, 1)`: al invalidar el padre primario `p1`, `child` muere inmediatamente (`valid=[true, false, false]`).
- **`subgraph-create2` (`[O]`, `93/93` trazas coinciden) y `AGSubgraphSetIndex` (`[?]`):**
  - `AGSubgraphCreate2` (`Subgraph(graph:attribute:)`) coincide (`valid=[true, false]`); `AGSubgraphSetIndex` está en `.tbd` pero no expuesto en `AGSubgraph.h` / `.swiftinterface`.
- **`weak-read-after-child-invalidate`, `weak-multiple-on-same-child`, `weak-combiner-three-children-invalidate-middle` (`[O]`, `93/93` trazas coinciden, `PASS debug/release run 1..3`):**
  - Tras invalidar el subgrafo del hijo, el débil devuelve `nil` y el lector/combinador **no** se reevalúa por dependencia (`values=[6, 6]|runs=1`).
- **`subgraph-add-child-secondary-parent-reverse` (`[O]`, `94/94` trazas coinciden, `PASS debug/release run 1..3`):**
  - Hijo creado bajo `p1`, `AGSubgraphAddChild2(p2, child, 1)`: al invalidar primero `p2` (secundario), `child` también muere (`valid=[true, false, false]`).
- **`AGGraphClearUpdate` / `AGGraphSetUpdate` (`clear-set-update`, `[?]` en propio):**
  - Nativo: `token1NonNil=true|token2Nil=false|values=[11, 11, 22]|runs=2` (no crea arista tras `clearUpdate`, sí tras `setUpdate`). Nuestro motor solo expone `withoutUpdate(_:)` por *closure*, sin token.
- **`AGGraphSetInvalidationCallback` + `SetContext` / `GetContext` (`[?]` en propio):**
  - Nativo medido: `context_match=true`; `onInvalidation` no se dispara en escrituras/invalidaciones sin consumidores dependientes. Nuestro motor no expone `context` ni `onInvalidation`.
- **`AGGraphGetValue` (opciones 2/4), `AGGraphGetInputValue`, `AGCompareValues` (`0x103`/`0x102`) (`[?]`):**
  - No expuestos directamente en `native-interfaces` ni en el motor propio.
- **`clear-set-update` y `clear-set-update-nested-reverse` (`[O]`, `96/96` trazas coinciden, `PASS debug/release run 1..3`):**
  - `Graph.clearUpdate()` / `Graph.setUpdate(_:)` (`aedd6a4`, `0889714`): token opaco no nulo, lecturas sin aristas mientras está limpio, restauración anidada en orden inverso (`values=[21, 21, 42]|runs=2`).
- **`clear-set-update-outside-rule` (Diferencia conocida) y creación de atributo entre `clearUpdate`/`setUpdate` (Funcional sin oráculo):**
  - Fuera de regla: nativo `tokenNonNil=false`, propio `tokenNonNil=true`.
  - Crear atributo entre `clearUpdate` y `setUpdate`: nativo aborta (`exit 133`, `attempting to create attribute with no subgraph`), propio crea el atributo (`creatingAttributeBetweenClearAndSetUpdateSucceedsInOwnEngine`).
- **`AGGraphGetValue` (opciones 2 y 4), `AGGraphGetInputValue` y `AGCompareValues` (`0x103`/`0x102`) (Medido en nativo con `@_silgen_name`, No implementado en propio):**
  - `AGGraphGetValue` opt 4: `values=[10, 10]|runs=1` (sin dependencia); opt 2: `values=[20, 30]|runs=2` (con dependencia).
  - `AGGraphGetInputValue`: registra dependencia contra el lector explícito (`runs=2`).
  - `AGCompareValues` (`0x103`/`0x102`): `Int` `true/false`, `NaN` `true`, `-0.0` `false`, `String` `true/false`, `Array` `false/false`, `Optional` `true/false`.
- **`AGCompareValues` frío vs caliente (`0x103`) y síncrono (`0x303`/`0x302`) (`[O]` medido en nativo, `probe_compare_values_warm.swift`):**
  - `0x103` (sin `0x200`): `custom_eq` y `str_nfc_nfd` cambian de `false` (frío, bytes) a `true` (caliente, `Equatable`).
  - `0x303` vs `0x302` (con `0x200` síncrono): `custom_eq` (`true`/`false`), `double_nan` (`false`/`true`), `double_neg0` (`true`/`false`), `str_nfc_nfd` (`true`/`true`), `eq_class_diff` (`true`/`true`), `plain_class_diff` (`false`/`false`), `closure` (`false`/`false`), `array_eq` (`true`/`true`), `opt_some_nil_vs_nil` (`false`/`false`), `pod` (`true`/`true`), `local_custom_eq` (`true`/`false`).
- **`AGGraphSetInvalidationCallback` con contexto compartido (`[O]` medido en nativo, `probe_invalidation_cb_shared.swift`):**
  - Con `g1 = Graph()` y `g2 = Graph(shared: g1)`: `shared_before_read|events=[]`, `shared_after_read_write1|r=1048|r2=1080|events=[536]` (se dispara con el atributo de `g1` que cruza a `g2`), `shared_after_write2|events=[]`, `single_context_after_read_write|events=[]`.
- **`compare-values-302-scalars`, `compare-values-302-collections`, `compare-values-302-refs` (`[O]`, `99/99` trazas coinciden en `debug`):**
  - `AGCompareValues` (`0x302`) frente a `Comparison.equatableUnlessPOD`: coinciden en `Int`, `POD`, `Double.nan`, `0.0` vs `-0.0`, `String` NFC/NFD, `Array`, `Optional`, `EqClass`, `PlainClass`, `closure` y `CustomEq` (`04b5b96`).
- **`compare-values-302-edges` (Diferencia conocida, fuera de `SCENARIOS`):**
  - Nativo `0x302`: `res=[true, false, true, true, false, true, true, true]`; propio `equatableUnlessPOD`: `res=[true, false, false, true, false, true, true, true]` (difiere en `PaddedPOD(Int8, Int64)`: el nativo ignora el padding y `equatableUnlessPOD` usa `bitwiseEqual`).
- **`compare-values-302-edges` (`[O]`, `99/99` trazas coinciden en `debug` y `release`, `689581a`):**
  - `equatableUnlessPOD` usa `ComparisonPlan` (`mode: .view`) para tipos POD, ignorando el padding (`PaddedPOD`, `NestedPOD`) y coincidiendo con `AGCompareValues(..., 0x302)` en las 6 pasadas.
  - Nota: solo el modo **caliente** (`0x302` / `0x303` o `0x103` tras construir el layout) es estable; el comportamiento en frío (`0x103` sin `0x200`) depende del estado previo del proceso (ej. `double_neg0` dio `false` en una corrida y `true` en otra).
- **`get-input-value-explicit-reader` (`[O]`, `100/100` trazas coinciden en `debug` y `release`, `c20302a`):**
  - `Graph.inputValue(of:for:)` registra la dependencia contra el lector explícito (`v1=5|v2=1|runs=2`).
  - Medición nativa ampliada (`probe_get_input_value_full.swift`): duplicados `vals=[5, 5]|runs=3`; con lector input (no regla) `v=10|readerVal=99`.
- **`get-input-value-dup-prune` y `get-input-value-non-rule-reader` (Diferencia conocida, fuera de `SCENARIOS`, `c943a1a`):**
  - Nativo: `vals=[5, 5]|runs=3` (arista no se poda) y `v=10|readerVal=99` (no aborta si el lector es un input).
  - Propio: poda aristas no leídas en la siguiente evaluación y hace `SIGTRAP` si el lector es un input.
- **`get-input-value-dup-prune` y `get-input-value-non-rule-reader` (`[O]`, `102/102` trazas coinciden en `debug` y `release`):**
  - `InputEdge.keepForNextPrune` conserva una evaluación adicional la arista registrada por `Graph.inputValue(of:for:)` (`vals=[5, 5]|runs=3`), y `NodeState.isRule` evita registrar aristas sobre lectores que no son reglas (`v=10|readerVal=99`).
- **`AGGraphGetValue` (opciones 2, 4 y 6) (`[O]` medido en nativo, `probe_getvalue_and_current.swift`):**
  - `opt 4` fuera de regla: `10`; `opt 6` (`2 | 4`) dentro de regla: `values=[10, 10]|runs=1` (sin dependencia).
- **`AGGraphGetCurrentAttribute` y `AGGraphCurrentAttributeWasModified` (`[O]` medido en nativo, `probe_getvalue_and_current.swift`):**
  - Fuera de regla y tras `ClearUpdate`: `2` (`AGAttributeNil`); dentro de regla y regla anidada: coincide con el atributo en evaluación; `CurrentAttributeWasModified` antes de escribir: `false`.
- **Nota sobre `GetInputValue` (`0ef4fc3`):** la conducta (`vals=[5, 5]|runs=3`) coincide con el oráculo en las 6 pasadas (`102/102`); el mecanismo interno del bit `0x10` en `AGGraphGetInputValue` es `[?]` (hipótesis no verificada directamente en el binario).
- **`get-value-opt4`, `get-value-opt2`, `get-value-opt6` (`[O]`, `107/107` trazas coinciden en `debug` y `release`, `8e97c5b`, `aaba90c`, `5af2052`):**
  - `Graph.value(of:options:)` con `Graph.ReadOptions` (`.dependency` = bit 2, `.noDependency` = bit 4). Salida literal nativa = propia: `get-value-opt4|outside=[10, 11]|inside=[10, 10]|runs=1|priorEdge=[10, 110, 110]|runs=[2, 2]|sameRun=[20, 40]|runs=2`; `opt2`: `inside=[10, 20]|runs=2|priorEdge=[10, 110, 120]|runs=[2, 3]`; `opt6` idéntica a `opt4`.
  - `[O]` opción 2 se comporta igual que 0 (crea la arista); opción 4 y 6 no crean arista, y 4 gana sobre 2; una lectura normal previa en la misma evaluación conserva la arista; una arista de una evaluación anterior se poda si la siguiente solo lee con opción 4/6; fuera de regla todas devuelven el valor actual sin arista. `[?]` el significado del bit 2 más allá de coincidir con el valor por defecto; el bit `changed` del par devuelto fuera de regla fue `false` en nativo y no se modela. Tests: `ReadOptionsTests` (`Tests/SwiftAttributeGraphTests/Unit`).
- **`get-current-attribute` (`[O]`, `107/107` trazas coinciden en `debug` y `release`, `762d6ae`):**
  - `Graph.currentAttribute`: `outside=nil|simple=["self", "self"]|nested=["outerBefore=self", "inner=self", "outerAfter=self", "cleared=nil", "restored=self"]|stateful=["self"]|after=nil` (igual en nativo y propio). `[?]` regla reanudable: sin equivalente nativo, no medida.
- **`current-attribute-was-modified` (`[O]` solo el valor `false`, `107/107`, `de3beee`; la condición que lo vuelve `true` es `[?]`):**
  - `Graph.currentAttributeWasModified` devuelve siempre `false`; nativo dio `false` en: fuera de regla, regla simple, regla con estado antes y después de escribir (valor distinto o igual, por el contexto o por `AGGraphSetOutputValue`), regla con estado que no escribe y regla externa tras escribir la interna. Escribir un atributo-regla desde fuera aborta nativamente (`can only set initial value of computed attributes`), y `AGGraphSetValue`/`AGGraphInvalidateValue` sobre el atributo actual abortaron, así que no se halló un caso `true`: no hay paridad declarada para ese valor.
- **`get-counter` (`[O]`, `110/110` trazas coinciden en `debug` y `release`, motor `fc449ab`, escenario `1817511`):**
  - `Graph.counter(for:)` con `Graph.CounterQueryType` (14 selectores). Valores nativos medidos en proceso aislado (macOS 15.8.3, `AGGraphGetCounter`), selector × situación (N=nodes, T=transactions, U=updates, C=changes, CN=createdNodes, S=subgraphs, CS=createdSubgraphs):
    - (a) grafo nuevo: todos `0` salvo `contextID=2`, `graphID=1` (segundo grafo del proceso: `4` y `3`); con un `Subgraph`: `S=1`, `CS=1`.
    - (b) 5 inputs + 1 regla en un subgrafo: `N=6 T=0 U=0 C=5 CN=6 S=1 CS=1` (la regla sin valor no cuenta como cambio).
    - (c) primera lectura de la regla: `T=1 U=1 C=6`; tras una escritura: `C=7` (`T`, `U` sin cambio); lectura que reevalúa: `T=2 U=2 C=8`; lectura limpia: `T=3 U=2 C=8` (una lectura limpia de una regla es transacción, no actualización).
    - (d) tras invalidar el subgrafo: `N=0 S=0`, `T=3 U=2 C=8 CN=6 CS=1` (los acumulados no bajan).
    - Dentro de una actualización: `threadUpdating=1`, `contextThreadUpdating=1` (`0` fuera); tras `setNeedsUpdate`: `needsUpdate=1`, `contextNeedsUpdate=1` (vuelven a `0` en la siguiente lectura de una regla); `mainThreadUpdates` = `updates` en todas las sondas (hilo principal).
  - Reglas de conteo medidas `[O]` y reproducidas: `transactions` sube con cada lectura de una regla fuera de toda actualización (limpia o no, también por un indirecto, también bajo `withoutUpdate`), no con la lectura de un input ni dentro de una regla; `updates` sube 1 por lectura que encuentra una regla sucia más 1 por cada atributo sin valor que se evalúa por primera vez dentro de otra actualización (cadena de 4 reglas: `+4` en la primera lectura, `+1` al reevaluarla entera; diamante: `+3`); un indirecto es transparente (`+1` en total); `changes` cuenta la creación de cada input, cada escritura distinta y cada resultado de regla distinto del anterior (el primero cuenta); una escritura igual o una regla que da el mismo valor no cuentan.
  - `[O]` (`nc4`, `nc5`, escenario `65ecd1a`, `111/111` trazas): nativo no cuenta atributos indirectos en `nodes`/`createdNodes` (regla + indirecto = `1`; tampoco sobre un input, sobre otro indirecto, ni `attribute[keyPath:]`, `WeakAttribute` u `OptionalAttribute`; tras invalidar el padre `N=0` y `CN` se queda en `2`). Motor `53ee547`: `NodeTable` cuenta aparte los nodos indirectos vivos y creados y `counter(for:)` los resta; `nodeCount` sigue contando todas las ranuras (los tests de invalidación de subgrafos siguen en verde). Diferencia resuelta.
  - `[O]` `get-counter-context` (nativo = propio, `111/111`): los identificadores salen de un contador de proceso que empieza en 1 y no se reutiliza: grafo = `n`, contexto = `n+1`; 4 grafos seguidos `1/2, 3/4, 5/6, 7/8`; tras liberarlos `9/10, 11/12`; crear subgrafos y atributos no consume. El escenario compara los valores relativos al primer grafo (`0,1`, `2,3`, ... `18,19`) porque los absolutos dependen de los grafos que el proceso haya creado antes. `threadUpdating`/`contextThreadUpdating`: `1` dentro de una regla y de una regla anidada, `0` fuera y bajo `withoutUpdate` fuera de regla, y `0` en otro grafo mientras corre una regla del primero. `needsUpdate`/`contextNeedsUpdate`: `1` tras `setNeedsUpdate`, un segundo `setNeedsUpdate` no suma, leer un input o escribir no lo baja, la siguiente lectura de una regla (limpia o sucia, también por un indirecto) lo baja; levantado dentro de una regla sigue en `1` al terminar. Una escritura sola no lo levanta.
  - `[O]` `AGGraphCreateShared` (`Graph(shared:)`, `nc1`): `Graph(shared: nil)` crea un grafo nuevo (`19/20`); `Graph(shared: k1)` devuelve otro objeto con el mismo `graphID` (`13`) y un `contextID` nuevo (`21`, un número del mismo contador). El motor lo reproduce con `Graph.makeSharedContext()` (modelo mínimo, ver abajo).
  - `[?]` `mainThreadUpdates`: igual a `updates` en todas las sondas, también con el grafo usado desde un `Thread` de Foundation (`isMain=false`, `mtu=1,2`); el motor devuelve `updates` sin mirar el hilo. `[O]` la variante por contexto de `needsUpdate` con contextos compartidos (tras `setNeedsUpdate` en el grafo, el compartido da `needsUpdate=1`, `contextNeedsUpdate=0`) ya la modela el motor.
  - `[O]` selectores que usa el core (desensamblado de `SwiftUICore`, 194 llamadas a `0x1e7a553c4`, `mov w1, #imm` antes de la llamada; escaneo hacia atrás sin revisión manual sitio a sitio): `contextID` (4) en 170 sitios, `transactions` (1) en 8, `contextThreadUpdating` (6) en 8, `threadUpdating` (7) en 5, `mainThreadUpdates` (10) en 3. `asyncTransaction` (`0x1e767a4e4`) usa el selector 6 y `beginNextUpdate` (`0x1e7a3ceb8`) el 10. Esos cuatro selectores ya están implementados (`af13f33`); `contextID`/`graphID` en nativo valen `2k`/`2k-1` para el k-ésimo grafo creado en el proceso (medido con dos grafos); con `Graph(shared:)` el compartido toma el siguiente número `[O]`. `[?]` sin implementar: `contextID`, `graphID`, `contextThreadUpdating`, `threadUpdating`, `contextNeedsUpdate`, `needsUpdate`, `mainThreadUpdates`.
  - `[O]` contextos compartidos, modelo mínimo (implementado: `Graph.makeSharedContext()`, `Graph.defaultContext`, `GraphContext.contextID/graphID/counter(for:)`, `Graph.graphContext(of:)`; escenarios `shared-context-ids`, `shared-context-needs-update`, `shared-context-update-callback`, `shared-context-subgraphs`, nativo = propio en las 6 pasadas). Medido en nativo (macOS 15.8.3, `nc6b.swift`): el `AGGraphRef` es el contexto: `Subgraph(graph: g2)` pertenece al contexto `g2` (`sg.graph === g2`, `attribute.graph === g2`) y un `Graph(shared:)` tiene el mismo `graphID` y un `contextID` con el siguiente número del contador de proceso (relativo: grafo `0,1`, compartido `0,2`, otro grafo `3,4`, su compartido `3,5`, otro compartido del primero `0,6`; un compartido liberado no devuelve el número: el siguiente grafo es `8,9`). `needsUpdate` es del grafo y `contextNeedsUpdate` del contexto: tras `setNeedsUpdate` en el original `1,1 | 1,0`; leer una regla de CUALQUIER contexto baja todos; leer un input no baja nada. El callback que corre al leer una regla es el del contexto que levantó la bandera, no el del que contiene la regla (`setNeedsUpdate` en c1 y leer la regla de c2: `calls=1,0`; con las dos banderas, `2,2`). `threadUpdating` vale `1` para todos los contextos del grafo y `contextThreadUpdating` solo para el de la regla en marcha (`1110 / 1011`). Invalidar el subgrafo de un contexto no toca el otro; `nodes`/`subgraphs` son del grafo (`4/4,3/3` -> `2/2,2/2`).
  - `[?]` FUERA del modelo mínimo, sin implementar ni declarar paridad: (1) dependencias entre atributos de contextos distintos del mismo grafo (el motor las permite porque comparte la tabla; nativo las permitió en `probe_invalidation_cb_shared`, pero no se midió su semántica de invalidación ni de `needsUpdate`); (2) `AGGraphSetInvalidationCallback` entre contextos (nativo dispara el callback de `g2` con un atributo de `g1`, `events=[536]`); (3) `AGGraphSetContext`/`GetContext`; (4) `WithMainThreadHandler`; (5) el contexto de `AGSubgraphGetCurrentGraphContext` (la API Swift de nativo aborta con exit 139 en `Subgraph.currentGraphContext` dentro de `apply` y en `Graph.graphContext`); (6) soltar un contexto compartido: el motor invalida sus subgrafos (`GraphContext.deinit`), nativo no se midió; (7) lectura de una regla anidada de otro contexto: `contextThreadUpdating` mira la regla más interna.
  - `[O]` resuelta (commits `5466663` motor, `f5e3542` escenario `shared-context-input-read`, ya en `SCENARIOS`, 116/116 trazas iguales en las 6 pasadas): con las banderas de dos contextos levantadas, leer un INPUT no dispara los callbacks (`afterInput=0,0`) y leer una regla de nivel superior dispara los de todos los contextos (`afterRule=1,1`), igual que nativo; antes el motor drenaba al leer cualquier atributo. Un indirecto cuenta como el nodo al que resuelve [?: no medido en nativo]. Prueba vertical `PRUEBA_VERTICAL_MOTOR.md` (commit `73e44e8`): 7 tests del patrón del core con la API pública; descubrió un aborto de `Graph.inputValue(of:for:)` fuera de regla cuando la fuente tiene índice menor que la última arista del lector (`recordRead(of:by:)` usa `evaluatingNode`), SIN corregir.
  - `[O]` fallo corregido (commits `01e90f9` motor, `7ce6183` tests): `recordRead` al insertar una arista en medio registraba `evaluatingNode` (noNode fuera de regla) y perdía `keepForNextPrune`; `Graph.inputValue(of:for:)` abortaba con `Index out of range`. Las dos ramas comparten ahora el alta. Sin oráculo propio para la inserción en medio `[?]`.
  - `[O]` `addChild` ya no es O(profundidad) para un hijo sin hijos (`d105920` motor, `5d715a4` test; release 20.000 enlaces: 1421 ms -> 4,2 ms; nativo 52,6 ms medido en probe aislado). El desensamblado nativo (PHASE12) no hace recorrido de ancestros ni comprueba ciclos; el rechazo de ciclos es propio `[?]` y con hijo que ya tiene hijos la comprobación sigue siendo O(profundidad) `[?]`.
  - `[O]` regresión de `20,000 indirects, write + read` (4,6 -> 5,35 ms) acotada por bisección a `5466663` (un `resolveIndirect` extra por lectura) y corregida en `43b09d7` (4,6-4,8 ms); sin cambio de comportamiento observable.
  - Rendimiento (`-c release`, `PerformanceTests` + `IndirectPerformanceTests`, 19 tests, 48 cifras): motor `65ecd1a` frente a `f1d8f99`, razón mediana 0.99, máxima 1.03, ninguna sobre 1.10 (sin regresión). Mediciones previas: sin cambio medible (razón 0.98 a 1.05, ruido) con contadores, etiqueta de grafo y subgrafo actual frente al estado `d416e65`; frente a `de3beee` no medido `[?]`.
- **`get-attribute-graph` (`AGGraphGetAttributeGraph` y `AGSubgraphGetGraph`) (`[O]`, `110/110` trazas coinciden, motor `f7d2701`, escenario `d416e65`):**
  - Salida literal nativa = propia: `get-attribute-graph|attributes=[true, true, false, false, true, true, false]|erased=[true, true, false]|subgraphs=[true, true, true, true, true, false, false]|same=[true, false, true, false, true]` (dos grafos vivos con el mismo índice de ranura; comparación por identidad de objeto `===`).
  - Nativo `[O]`: devuelve el mismo objeto `Graph` con que se creó; `Subgraph(graph:attribute:)` (`create2`) también; sobre un atributo o subgrafo muerto aborta (`SIGABRT`, `exit 134`; medido para `attribute.graph`, `attribute.subgraph` y `subgraph.graph`). Propio: `Attribute.graph`/`AnyAttribute.graph`/`Subgraph.graph` abortan por `precondition` y `Graph.graph(of:)` devuelve `nil`.
  - Mecanismo: cada grafo recibe una etiqueta de 16 bits (registro global con candado, etiquetas nuevas en orden y reciclaje de las liberadas solo al agotarse las 65535) en los bits altos de la generación de los `AttributeID` y `SubgraphID`; una ranura que agota los 16 bits de reutilización se retira en vez de dar la vuelta. Límite: con más de 65535 grafos vivos el grafo sin etiqueta no se encuentra desde sus handles `[?]` (no probado). Rama Windows (`SRWLOCK`, segunda ranura TLS) sin compilar en esta máquina `[?]`.
  - `[?]` `create2`: el motor propio no tiene `Subgraph(graph:attribute:)`; el adaptador propio de `subgraph-create2` sigue ignorando el atributo y no se usó en este escenario.
- **`get-subgraph-current` (`AGSubgraphGetCurrent` y `AGSubgraphSetCurrent`) (`[O]`, `110/110` trazas coinciden, motor `89bcba2`, escenario `f1d8f99`):**
  - `Subgraph.current` (getter y setter, por hilo). Salida literal nativa = propia: `get-subgraph-current|["outside=nil", "apply=s1", "otherGraph=s2", "nested=s1b", "restored2=s2", "restored1=s1", "after=nil", "set=s1b", "applyInsideSet=s2", "afterApplyInsideSet=s1b", "setNil=nil", "invalidatedCurrent=nil", "invalidatedInApply=nil", "afterInvalidatedApply=nil", "nestedInvalidated=nil", "outerAfterInnerInvalidated=other", "afterRuleRead=s2", "rule=[\"inRule=s2\", \"applyInRule=other\", \"afterApplyInRule=s2\"]", "end=nil"]`. El adaptador propio llama a `Graph.withCurrent` y a `Subgraph.current` reales, sin emulación.
  - `[O]` nativo: `nil` fuera de todo; el subgrafo dentro de `apply`; al anidar (también entre dos grafos) se restaura el anterior; `SetCurrent` persiste y `apply` dentro lo restaura; invalidar el subgrafo actual (dentro o fuera de `apply`) lo deja en `nil`; una regla **no** cambia el actual: ve el del lector (`nil` si se lee fuera de todo `apply`, `s2` si se lee dentro de `apply(s2)`) y un `apply` dentro de la regla se restaura al salir. Un primer borrador del motor ponía `nil` dentro de las reglas por una sonda aislada mal leída; el escenario lo detectó y se corrigió antes de integrarlo.
  - `[?]` `Subgraph.current = nil` solo borra lo que informa el getter: el grafo sigue creando atributos en el último subgrafo fijado (nativo: crear sin subgrafo actual aborta, `exit 133`, ya medido para `clearUpdate`). `AGSubgraphGetCurrentGraphContext` sin medir.
- **Corrección de rendimiento en `GraphRegistry` (`7991c61`):** `Unmanaged<Graph>` en lugar de `weak var graph` evita la *side table* ARC en `Graph`, recuperando los tiempos de `633e3de` (`117/117` trazas en `NativeProbe`, `EXIT=0`).
- **`AGSubgraphCreate2`, `AGSubgraphAddChild2(tag: 0)` y `AGSubgraphSetIndex`/`GetIndex` (`[O]` medido en nativo, `probe_create2_addchild2_index.swift`):**
  - `create2_attr|validBefore=true|validAfterParent=true` (el subgrafo creado con `attribute` no muere al invalidar el padre de `attribute`).
  - `addchild2_tag0_inv_p2|childValid=false` (con `tag: 0`, invalidar `p2` también invalida `child`).
  - `subgraph_index|before=0|after=7` (`AGSubgraphGetIndex` / `AGSubgraphSetIndex`).
- **`AGGraphCurrentAttributeWasModified` (`[?]` en propio):**
  - Medido en nativo (`probe_was_modified.swift`): `was_modified_in_rule|mod=false|stateIn=87|stateAfter=88`.
- **`current-attribute-was-modified-invalidate` (`[O]`, `118/118` trazas coinciden en `debug` y `release`, `608b846`):**
  - Nativo y propio coinciden al evaluar tras cambio de entrada (`false`), `invalidateValue` propio (`true`), segunda evaluación sin invalidar (`false`) e `invalidateValue` de otra regla (`true` en la invalidada, `false` en la lectora).
- **`subgraph-add-child-owner` (`[O]`, `119/119` trazas coinciden en `debug` y `release`):**
  - Regla medida: un subgrafo con múltiples padres añadidos vía `addChild`/`addChild2` (`tag: 0` o `tag: 1`) muere en cuanto se invalida **cualquiera** de sus padres vivos; `Subgraph(graph:)` sin `parent:` no hereda `Subgraph.current` como padre; duplicar `addChild2` con el mismo padre aborta (`exit 134`).
- **Escrituras durante la evaluación de una regla (`[O]`, 132/132, rehecho de `c87bef5`):**
  - `invalidateValue` desde una regla que registra lecturas aborta en nativo (exit 134, sin mensaje en stderr) y en el propio (`precondition` «setting value during update», exit 133); sonda aislada `native-scratch/redo` (`Probe write-in-rule-invalidate-value`), fuera de `SCENARIOS`. Dentro de `withoutUpdate` se acepta: `write-in-rule-invalidate-value-without-update`. `mutateBody(invalidating: true)` desde una regla se acepta y el lector en pila queda sucio (`NodeState.staysDirty`, `1 << 12`): `write-in-rule-mutate-body-invalidating`.
  - Diferencia `[O]` no corregida: si el objetivo no tiene lectores (ninguna regla lo lee), nativo acepta la invalidación directa dentro de una regla y el propio aborta.
- **`isDirty(flags:)` acumulado (`[O]`, rehecho de `13155a7`):** `update(flags:)` repite el recorrido hasta que una pasada no actualiza nada y limpia las marcas al final; 11 trazas `is-dirty-*` coinciden con nativo. Las marcas extra en recálculos de indirectos no hicieron falta (ninguna traza las exigió) `[?]`.


## Mapa de escenarios (`NativeProbe/run.py`, 132)

| Escenario | Mecanismo | Mención en matriz |
|---|---|---|
| `dynamic` | Ramas dinámicas y poda | no |
| `cut` | Propagación, diamantes y reglas | sí |
| `lazy` | Propagación, diamantes y reglas | no |
| `lifetime` | Invalidación y ciclo de vida | no |
| `diamond-source-forward` | Propagación, diamantes y reglas | no |
| `diamond-source-reverse` | Propagación, diamantes y reglas | no |
| `diamond-multiple-forward` | Propagación, diamantes y reglas | no |
| `diamond-multiple-reverse` | Propagación, diamantes y reglas | no |
| `stateful-no-write-cut` | Propagación, diamantes y reglas | no |
| `stateful-unread-input` | Propagación, diamantes y reglas | no |
| `stateful-has-value-and-revert` | Propagación, diamantes y reglas | no |
| `selector-input-order` | Propagación, diamantes y reglas | no |
| `invalidate-in-rule` | Invalidación y ciclo de vida | no |
| `weak-attribute-in-rule` | Atributos débiles | sí |
| `indirect-rule-and-redirect` | Indirectos | sí |
| `focus-keypath-cut` | Propagación, diamantes y reglas | sí |
| `slot-reuse-input-order` | Invalidación y ciclo de vida | no |
| `duplicate-writes-before-read` | Propagación, diamantes y reglas | no |
| `double-read-and-prune` | Ramas dinámicas y poda | no |
| `indirect-source-invalidated` | Indirectos | sí |
| `random-graph-oracle-trace` | Aleatorios / Oráculos | no |
| `random-graph-oracle-trace` | Aleatorios / Oráculos | no |
| `random-graph-oracle-trace` | Aleatorios / Oráculos | no |
| `random-graph-oracle-trace` | Aleatorios / Oráculos | no |
| `random-graph-oracle-trace` | Aleatorios / Oráculos | no |
| `random-graph-oracle-trace` | Aleatorios / Oráculos | no |
| `random-graph-oracle` | Aleatorios / Oráculos | no |
| `random-subgraph-weak-indirect-oracle-trace` | Aleatorios / Oráculos | no |
| `random-subgraph-weak-indirect-oracle-trace` | Aleatorios / Oráculos | no |
| `random-subgraph-weak-indirect-oracle-trace` | Aleatorios / Oráculos | no |
| `random-subgraph-weak-indirect-oracle-trace` | Aleatorios / Oráculos | no |
| `random-subgraph-weak-indirect-oracle-trace` | Aleatorios / Oráculos | no |
| `random-subgraph-weak-indirect-oracle-trace` | Aleatorios / Oráculos | no |
| `random-subgraph-weak-indirect-oracle` | Aleatorios / Oráculos | sí |
| `map-and-property-wrappers` | Propagación, diamantes y reglas | no |
| `without-update-read` | Propagación, diamantes y reglas | no |
| `mutate-body-and-invalidate-value` | Invalidación y ciclo de vida | no |
| `indirect-dependency-cut-and-redirect` | Indirectos | sí |
| `subgraph-flags-forEach-and-update` | Subgrafos | sí |
| `has-value-validate-update-value` | Propagación, diamantes y reglas | no |
| `without-subgraph-invalidation-and-ancestor` | Subgrafos | no |
| `breadth-first-search` | Propagación, diamantes y reglas | no |
| `attribute-keypath-dynamic-member` | Ramas dinámicas y poda | no |
| `branch-switch-and-invalidate-before-read` | Invalidación y ciclo de vida | no |
| `indirect-original-dies-while-redirected` | Indirectos | sí |
| `stateful-dependency-pruned-without-write` | Propagación, diamantes y reglas | no |
| `initial-value-no-first-write` | Propagación, diamantes y reglas | no |
| `nested-special-scopes` | Propagación, diamantes y reglas | no |
| `reentrant-subgraph-invalidation` | Subgrafos | no |
| `weak-attribute-slot-reuse` | Atributos débiles | no |
| `indirect-reset-source-multi-redirect` | Indirectos | sí |
| `indirect-chain-and-intermediate-death` | Indirectos | sí |
| `changed-value-after-skipped-and-indirect` | Indirectos | no |
| `multi-observer-tree-order-and-cancel` | Propagación, diamantes y reglas | no |
| `cc-create-input-in-rule-scoped` | Propagación, diamantes y reglas | no |
| `cc-create-rule-in-rule-scoped` | Propagación, diamantes y reglas | no |
| `cc-create-rule-every-run-scoped` | Propagación, diamantes y reglas | no |
| `cc-create-rule-during-update-flags-scoped` | Propagación, diamantes y reglas | no |
| `cc-caller-invalidated-after-input` | Invalidación y ciclo de vida | no |
| `cc-caller-invalidated-after-rule` | Invalidación y ciclo de vida | no |
| `cc-caller-falling-input` | Propagación, diamantes y reglas | no |
| `cc-create-placement-caller-scope` | Propagación, diamantes y reglas | no |
| `cc-create-placement-explicit-owner` | Propagación, diamantes y reglas | no |
| `cc-closure-recreated-plain` | Propagación, diamantes y reglas | no |
| `cc-closure-stable-plain` | Propagación, diamantes y reglas | no |
| `cc-closure-captured-state-plain` | Propagación, diamantes y reglas | no |
| `cc-closure-thin-plain` | Propagación, diamantes y reglas | no |
| `cc-closure-stable-equatable` | Propagación, diamantes y reglas | no |
| `cc-closure-captured-state-equatable` | Propagación, diamantes y reglas | no |
| `offset-range-inside-outside` | Offsets | sí |
| `offset-sticky-inside-then-outside` | Offsets | sí |
| `offset-mixed-chain` | Offsets | sí |
| `indirect-set-same-value` | Indirectos | sí |
| `direct-edge-equal-and-different-write` | Comparación | sí |
| `offset-whole-value` | Offsets | sí |
| `subgraph-dag-add-child` | Subgrafos | sí |
| `context-update-callback` | Contexto, contadores y lecturas | sí |
| `cooperative-cancel` | Cancelación | sí |
| `cooperative-cancel-consumer` | Cancelación | sí |
| `cooperative-cancel-nested` | Cancelación | sí |
| `cooperative-cancel-first-eval` | Cancelación | sí |
| `context-update-callback-on-write` | Contexto, contadores y lecturas | sí |
| `invalidate-value-and-subgraph-dirty` | Subgrafos | sí |
| `any-inputs-changed` | Contexto, contadores y lecturas | sí |
| `any-inputs-changed-offset-edge` | Offsets | sí |
| `any-inputs-changed-first-eval-before-read` | Contexto, contadores y lecturas | sí |
| `any-inputs-changed-first-eval-after-read` | Contexto, contadores y lecturas | sí |
| `any-inputs-changed-second-eval-after-write` | Contexto, contadores y lecturas | sí |
| `subgraph-add-child-secondary-parent` | Subgrafos | sí |
| `subgraph-create2` | Subgrafos | sí |
| `weak-read-after-child-invalidate` | Atributos débiles | sí |
| `weak-multiple-on-same-child` | Atributos débiles | sí |
| `weak-combiner-three-children-invalidate-middle` | Atributos débiles | sí |
| `subgraph-add-child-secondary-parent-reverse` | Subgrafos | sí |
| `clear-set-update` | Contexto, contadores y lecturas | sí |
| `clear-set-update-nested-reverse` | Contexto, contadores y lecturas | sí |
| `compare-values-302-scalars` | Comparación | sí |
| `compare-values-302-collections` | Comparación | sí |
| `compare-values-302-edges` | Comparación | sí |
| `get-input-value-explicit-reader` | Contexto, contadores y lecturas | sí |
| `get-input-value-dup-prune` | Contexto, contadores y lecturas | sí |
| `get-input-value-non-rule-reader` | Contexto, contadores y lecturas | sí |
| `current-attribute-was-modified-invalidate` | Invalidación y ciclo de vida | sí |
| `subgraph-add-child-owner` | Subgrafos | sí |
| `get-value-opt4` | Contexto, contadores y lecturas | sí |
| `get-value-opt2` | Contexto, contadores y lecturas | sí |
| `get-value-opt6` | Contexto, contadores y lecturas | sí |
| `get-current-attribute` | Contexto, contadores y lecturas | sí |
| `current-attribute-was-modified` | Propagación, diamantes y reglas | sí |
| `get-counter` | Contexto, contadores y lecturas | sí |
| `get-counter-context` | Contexto, contadores y lecturas | sí |
| `get-attribute-graph` | Contexto, contadores y lecturas | sí |
| `get-subgraph-current` | Subgrafos | sí |
| `shared-context-ids` | Contexto, contadores y lecturas | sí |
| `shared-context-needs-update` | Contexto, contadores y lecturas | sí |
| `shared-context-update-callback` | Contexto, contadores y lecturas | sí |
| `shared-context-subgraphs` | Subgrafos | sí |
| `shared-context-input-read` | Contexto, contadores y lecturas | sí |
| `cold-chain-depth` | Profundidad | sí |
| `write-in-rule-invalidate-value-without-update` | Escrituras en reglas | sí |
| `write-in-rule-mutate-body-invalidating` | Escrituras en reglas | sí |
| `is-dirty-dirtied-during-update-b-first` | Subgrafos | sí |
| `is-dirty-dirtied-during-update-b-last` | Subgrafos | sí |
| `is-dirty-invalidated-subgraph-with-marks` | Subgrafos | sí |
| `is-dirty-flags-before-and-after-read` | Subgrafos | sí |
| `is-dirty-child-versus-parent-update` | Subgrafos | sí |
| `is-dirty-write-then-read` | Subgrafos | sí |
| `is-dirty-invalidate-value-then-read` | Subgrafos | sí |
| `is-dirty-same-and-different-value` | Subgrafos | sí |
| `is-dirty-partial-and-full-update` | Subgrafos | sí |
| `is-dirty-flags-changed-while-dirty` | Subgrafos | sí |
| `is-dirty-descendant-subgraph` | Subgrafos | sí |

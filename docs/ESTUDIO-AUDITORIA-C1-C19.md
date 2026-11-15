# Auditoría directa C1–C19 contra AttributeGraph nativo

Fecha: 2026-11-14. Mac M1 arm64, macOS 15.7.9 (24G830), Swift 6.2.4 de Xcode; SDK macOS 26.2. Solo núcleo (`AttributeGraph.framework` del sistema frente a `SwiftAttributeGraph`), sin SwiftUI ni ShellUI.

## 1. Objetivo y método

Responder empíricamente las preguntas abiertas **C1–C19** de [FUNDAMENTOS.md](FUNDAMENTOS.md) §6 observando directamente el `AttributeGraph.framework` instalado en macOS (`/System/Library/PrivateFrameworks/AttributeGraph.framework/Versions/A/AttributeGraph`) mediante:
1. **Sondas directas de API** (`Rule`, `StatefulRule`, `RuleContext`, `Subgraph`, `WeakAttribute`, `IndirectAttribute`, `breadthFirstSearch(options: .searchInputs)`).
2. **Trazas de ciclo de vida internas (`AGTrace` / `AGGraphAddTrace`)**, registrando los callbacks `begin_update_stack`, `end_update_stack`, `begin_update_attribute`, `end_update_attribute`, `add_edge`, `remove_edge`, `set_edge_pending`, `set_dirty`, `set_pending` y `set_source`.
3. **Banco comparativo aislado (`NativeProbe`)**, ampliado de 8 a **15 escenarios** compartidos compilados contra el framework nativo y contra `SwiftAttributeGraph`, verificados en 3 pares de procesos debug y 3 pares release.

---

## 2. Hallazgos detallados en `AttributeGraph` nativo

### 2.1 Reglas con estado (`StatefulRule` y `RuleContext` — C1, C2, C3)

- **C1 (corte cuando no se escribe `value`):**
  - En una `StatefulRule` con `initialValue == nil`, si tras la primera evaluación (`ctx.value = 10`) la regla vuelve a ejecutarse pero **no asigna `ctx.value`** (p. ej. porque `v <= 20`), su versión no sube y la regla aguas abajo (`output = stateful * 2`) **se omite**.
  - Traza medida (`stateful-no-write-cut` con entradas `[10, 15, 25, 18]`): `values=[20, 20, 50, 50]`, `statefulRuns=[1, 2, 3, 4]`, `outputRuns=[1, 1, 2, 2]`.
- **C2 (entradas no leídas o podadas):**
  - Mutar una entrada que la `StatefulRule` no leyó en su última evaluación no marca sucia ni ejecuta la regla. Al cambiar un selector de rama (`true -> false`), la arista hacia la rama anterior se poda inmediatamente y escrituras posteriores en la rama retirada no ejecutan la regla (`stateful-unread-input`: `values=[1, 1, 200, 200]`, `runs=[1, 1, 2, 2]`).
- **C3 (`hasValue` y mutación revertida antes de leer):**
  - En la primera evaluación sin `initialValue`, `hasValue == false`.
  - Si una entrada directa se escribe `5 -> 6 -> 5` antes de leer la `StatefulRule`, el bit sucio e `InputEdge.pending` ya se propagaron en la primera escritura (`5 -> 6`), por lo que al leer la regla **sí se ejecuta** una segunda vez: ve `hasValue == true`, su valor previo (`50`) sigue intacto y `changedValue(of: input)` devuelve `(value: 5, changed: true)` (`stateful-has-value-and-revert`).

### 2.2 Poda inmediata en selectores (`AGTrace` — C4 y C19)

En un selector `S ? A : B`, al cambiar `S` de `true` a `false` y leer la regla (`#1036`), los eventos de `AGTrace` fueron exactamente:

```text
set_dirty(#1036, 1)
set_pending(#1036, 1)
set_edge_pending(#1036, idx=1024, 1)
begin_update_stack(#1036)
begin_update_attribute(#1036)
add_edge(#1036 <- #1032)
remove_edge(#1036, idx=1028)
end_update_attribute(#1036, changed=1)
set_dirty(#1036, 0)
set_pending(#1036, 0)
end_update_stack(0)
```

`remove_edge(#1036, idx=1028)` ocurre de forma **inmediata** justo antes de `end_update_attribute`, confirmando que Apple poda por marca y barrido al cerrar la evaluación de la regla.

### 2.3 Hallazgo 1 (Divergencia corregida en Pieza 1 — C5 y C17): Orden de aristas por `AttributeID` creciente y actualización de todas las entradas sucias

1. **Orden interno de `inputs` (C17):**
   - Creamos tres entradas `E1 (#1024)`, `E2 (#1028)`, `E3 (#1032)` y una regla que las leyó en el orden no monótono `E2`, luego `E3`, luego `E1`.
   - Al consultar `breadthFirstSearch(options: .searchInputs)`, `AttributeGraph` recorrió las entradas en el orden **`[#1024, #1028, #1032]`** (`E1, E2, E3`).
   - Es decir, `AttributeGraph` almacena las aristas de entrada de cada nodo **ordenadas por `AttributeID` creciente**, con independencia del orden en que la regla las leyó.
2. **Verificación de entradas sucias antes de ejecutar una regla (C5):**
   - En `selector-input-order`, una entrada `raw` alimenta dos reglas intermedias: `A = raw % 2` (que no cambia al pasar `raw` de `1` a `3`) y `B = raw + 10` (que sí cambia de `11` a `13`). La regla final `C` lee `flag ? (A + B) : (B + A)`.
   - Trazas de `AGTrace` al cambiar `raw = 3` y leer `C (#1044)` cuando `C` había leído `B (#1040)` antes que `A (#1036)`:
     ```text
     begin_update_stack(#1044)
     begin_update_attribute(#1036)
     end_update_attribute(#1036, changed=0)
     begin_update_attribute(#1040)
     set_edge_pending(#1044, idx=1040, 1)
     end_update_attribute(#1040, changed=1)
     begin_update_attribute(#1044)
     ```
   - Y cuando `A` también cambiaba (`A = raw + 1`, `B = raw + 10`), `AGTrace` mostró que `AttributeGraph` **actualizó tanto `#1036` como `#1040` antes de iniciar `begin_update_attribute(#1044)`**: no detiene el bucle de verificación en la primera entrada cambiada.
   - **Divergencia previa en `SwiftAttributeGraph`:** nuestro motor guardaba `inputs` en orden de lectura y, para `Rule` sin estado, hacía `break` en la primera entrada cuya versión hubiera cambiado (dejando el resto de entradas sucias para actualizarse de forma recursiva dentro de `read()`). Además, `pruneEdges` reordenaba las aristas con swap-remove.
   - **Corrección (`611b35c`):** `inputs[node]` se mantiene ordenado por `source` (`AttributeID`) creciente con inserción/búsqueda binaria O(log k) y vía rápida O(1) cuando se lee en orden creciente; `pruneEdges` compacta con marca y barrido O(k); y `update()` verifica todas las entradas sucias previas antes de ejecutar cualquier regla.
   - **Impacto en rendimiento:** el test release `aRuleWithTwentyThousandInputsLosingHalf` pasó de `76,83 ms` a **`4,85 ms` (15,8× más rápido)** y la batería funcional completa en debug bajó de `31,02 s` a **`1,56 s`**.

### 2.4 Hallazgo 2 (Divergencia corregida en Pieza 2 — C9, C10 y C15): `Subgraph.invalidate()`, `isValid` y `WeakAttribute`

1. **Invalidación desde dentro de una regla en ejecución (C9):**
   - Cuando una regla llama a `child.invalidate()` durante su propia evaluación:
     - `child.isValid` pasa a **`false` inmediatamente** dentro de la misma regla (`validDuringInvalidate == false`).
     - Los atributos de `child` siguen vivos y legibles durante el resto del `update` (`childInput.value == 42` y `WeakAttribute(childInput).value == Optional(42)`).
     - Al terminar el `update`, los nodos de `child` quedan destruidos (`WeakAttribute(childInput).value == nil`, `WeakAttribute(childInput).attribute == nil`).
   - Detalle importante del modelo nativo de subgrafos descubierto con `NativeProbe`: en `AttributeGraph` de Apple, `Subgraph.addChild(child)` vincula `child` en el árbol de subgrafos **solo si el subgrafo padre es válido y no es nulo**, y `Subgraph.apply` restaura `Subgraph.current` al salir.
2. **Invalidar un subgrafo NO ensucia a los lectores externos (C9 / C15):**
   - Cuando un atributo `childIn (#1048)` en un subgrafo hijo es leído por una regla externa `reader (#912)` y después se llama a `child.invalidate()`, `AGTrace` emite únicamente:
     ```text
     remove_edge(#912, idx=1048)
     ```
   - **No** se emite `set_dirty(#912, 1)` ni `set_pending(#912, 1)`. El estado de `reader` tras `child.invalidate()` permanece limpio (`valueState == 88`, el mismo que antes de invalidar) y `reader` conserva su último valor cacheado (`20`) sin re-ejecutarse hasta que otra entrada viva (`tick`) lo ensucie; en esa siguiente ejecución, `WeakAttribute(childIn).value` y `changedValue` devuelven `nil` (`weak-attribute-in-rule`).
   - **Divergencia previa en `SwiftAttributeGraph`:** `perform(_:)` en `Graph+Invalidation.swift` marcaba `dirty | pending` a todos los dependientes externos al desprender sus aristas, y no existían `WeakAttribute<Value>` ni `graph.isValid(_ subgraph:)`.
   - **Corrección (`91cbc51`):** se implementaron `WeakAttribute<Value>` y `graph.isValid(_ subgraph:)`, y `perform(_:)` desprende las aristas hacia dependientes externos sin marcarlos `dirty | pending`.

### 2.5 Hallazgo 3 (Divergencia corregida en Pieza 3 — M6 y C18): `IndirectAttribute` hacia reglas, `setSource` y arista única

En `AttributeGraph` nativo (`IndirectAttribute<Value>`):
1. **Apuntar a reglas:** `IndirectAttribute(source:)` acepta tanto atributos de valor como reglas (`Rule` / `StatefulRule`).
2. **Arista única:** cuando una regla `R (#752)` lee un `IndirectAttribute` `ind (#705)` que apunta a `a (#1024)`, `AGTrace` registra una sola arista en el lector:
   ```text
   add_edge(#752 <- #705)
   ```
3. **Redirección (`ind.source = newSource`):**
   - Asignar el mismo `source` (`ind.source = a`) no emite eventos en `AGTrace` ni ensucia a `R`.
   - Redirigir a otro atributo `b (#1028)` —aunque `b` tenga exactamente el mismo valor `10` que `a`— emite en `AGTrace`:
     ```text
     set_source(#705, #1028)
     set_edge_pending(#752, idx=705, 1)
     set_dirty(#752, 1)
     set_pending(#752, 1)
     ```
     lo que hace que `R` se reevalúe en la siguiente lectura (`runs: 1 -> 2`), desconectado ya de `a` y conectado a `b`.
- **Corrección (`74fad4c`):** `makeIndirect(_:)` permite apuntar a reglas, se añadieron `graph.source(of:)` y `graph.setSource(_:for:)` con detección de ciclos, y cada indirecto mantiene su arista `indirect <- source` mientras los lectores registran una única arista `reader <- indirect`.

### 2.6 Limpieza de peso muerto en `NodeTable` (Pieza 4 — `7a81131`)

La auditoría del código fuente detectó que `NodeTable.lastVerified: [UInt32]` se reservaba, inicializaba y escribía en cada escritura y actualización (`NodeTable.swift`, `Graph+Update.swift`, `Graph+ResumableUpdate.swift`), pero **no se leía en ningún lugar del motor**. Se eliminó por completo, ahorrando 4 bytes por ranura y escrituras innecesarias en el camino caliente.

---

## 3. Resultados del banco `NativeProbe` (15 escenarios)

Todos los artefactos reproducibles están guardados en `NativeProbe/Results/audit-c1-c19-macos-15.7.9/`:

| # | Escenario (`NativeProbe`) | Preguntas cubiertas | Resultado (`native` vs `own`, debug × 3 y release × 3) |
|---|---|---|---|
| 1 | `dynamic` | C4 | Idéntico |
| 2 | `cut` | C11 | Idéntico |
| 3 | `lazy` | C3, C6 | Idéntico |
| 4 | `lifetime` | C9, C15 | Idéntico |
| 5 | `diamond-source-forward` | C5, C7, C8 | Idéntico |
| 6 | `diamond-source-reverse` | C5, C7, C8 | Idéntico |
| 7 | `diamond-multiple-forward` | C5, C6, C7 | Idéntico |
| 8 | `diamond-multiple-reverse` | C5, C6, C7 | Idéntico |
| 9 | `stateful-no-write-cut` | C1 | Idéntico (`values=[20, 20, 50, 50]`, `sRuns=[1, 2, 3, 4]`, `oRuns=[1, 1, 2, 2]`) |
| 10 | `stateful-unread-input` | C2, C4 | Idéntico (`values=[1, 1, 200, 200]`, `runs=[1, 1, 2, 2]`) |
| 11 | `stateful-has-value-and-revert` | C3 | Idéntico (`runs=2`, `hasValue=[false, true]`, `prev=[50]`, `changed=[true, true]`) |
| 12 | `selector-input-order` | C5, C17 | Idéntico (`ab=[2, 2, 2]`, `ba=[2, 2, 2]`) |
| 13 | `invalidate-in-rule` | C9, C15 | Idéntico (`v1=42`, `v2=43`, `validDuring=false`, `weakDuring=Optional(42)`, `validAfter=false`, `weakAfter=nil`) |
| 14 | `weak-attribute-in-rule` | C9, C10, C15 | Idéntico (`reader=[10, 20, 20, -1]`, `stateful=[110, 120, 120, -999]`, `runsBeforeTick=[2, 2]`, `runsAfterTick=[3, 3]`) |
| 15 | `indirect-rule-and-redirect` | M6, C18 | Idéntico (`values=[11, 11, 11, 11, 26, 22, 25]`, `runs=[1, 1, 2, 2, 3, 4, 5]`) |
| 16 | `focus-keypath-cut` | M6, C14 | Idéntico (`values=[20, 20, 50, 50]`, `runs=[1, 1, 2, 2]`) |
| 17 | `slot-reuse-input-order` | C20 | Idéntico (`v1=111`, `v2=122`, `joinRuns=2`, `evalOrder=["second", "reused"]`) |
| 18 | `duplicate-writes-before-read` | C21 | Idéntico (`v=[15, 15]`, `u=[24, 24]`, `runs=[3, 3]`) |
| 19 | `double-read-and-prune` | C22 | Idéntico (`values=[120, 140, 100, 100]`, `runs=[1, 2, 3, 3]`) |
| 20 | `indirect-source-invalidated` | C23 | Idéntico (`values=[78, 78, 100]`, `runs=[1, 1, 2]`) |
| 21 | `random-graph-oracle` | C24 | Idéntico (`runs=[95, 108, 105, 100, 95, 107]`, checksums idénticos en las 6 semillas) |

---

## 4. Hallazgos de C20–C24

1. **C20 (Asignación y reutilización de `AttributeID` y orden de entradas):**
   - En `AttributeGraph` nativo, los `AGAttribute` (`rawValue: UInt32`) son desplazamientos dentro de páginas por subgrafo: dentro de un mismo subgrafo crecen de `40` en `40` (`536, 576, 616...`), y un segundo subgrafo recibe otra página (`1048, 1088...`).
   - Cuando un subgrafo se invalida (`s2.invalidate()`), su página vuelve a la lista libre y el siguiente subgrafo creado reutiliza exactamente ese desplazamiento (`536`).
   - Como ambos motores mantienen `inputs` ordenado por índice de ranura / `AttributeID` creciente, reutilizar un hueco con índice menor hace que esa entrada ocupe una posición anterior en `inputs` (`slot-reuse-input-order`).
2. **C21 (Escrituras repetidas antes de leer):**
   - Escribir dos veces el mismo valor (`d.write(5, to: x2); d.write(5, to: x2)`) o encadenar duplicados antes de leer (`7, 7, 8, 8` frente a `7, 8`) produce exactamente las mismas ejecuciones (`runs=[3, 3]`) gracias al corte en `setValue` y a la coalescencia perezosa (`duplicate-writes-before-read`).
3. **C22 (Lectura duplicada de la misma entrada en una misma ejecución y poda posterior):**
   - Cuando una regla lee `x + y + x`, `AGTrace` emite un único `add_edge` para `x` y otro para `y` (`inputs=[536, 1048]`).
   - Al cambiar después el selector para dejar de leer `x`, esa única arista se poda limpiamente y mutaciones posteriores de `x` no reejecutan la regla (`double-read-and-prune`: `values=[120, 140, 100, 100]`, `runs=[1, 2, 3, 3]`).
4. **C23 (Indirecto cuyo `source` pertenece a un subgrafo que se invalida):**
   - Al invalidar el subgrafo hijo dueño del `source` de un `IndirectAttribute`, ni el indirecto ni el lector externo se marcan sucios (`ir.valueState == 88`). El lector conserva su valor cacheado (`78`, `runs=1`).
   - Si se reevalúa una regla que intenta resolver el `IndirectAttribute` cuyo `source` sigue muerto, el nativo aborta (`SIGABRT`); pero si el indirecto se redirige antes con `setSource` a un nuevo atributo vivo (`99`), el lector se ensucia y actualiza limpiamente a `100` (`runs=2`) (`indirect-source-invalidated`).
5. **C24 (Oráculo de grafos aleatorios nativo vs propio):**
   - En 6 semillas deterministas × 50 pasos con grafos aleatorios de 6 entradas y 24 reglas mixtas (`Rule` y `StatefulRule` con selectores condicionales `sel % 2 == 0 ? left : right`), las ejecuciones acumuladas (`[95, 108, 105, 100, 95, 107]`) y los checksums de 64 bits coinciden al 100 % entre el `AttributeGraph` de Apple y `SwiftAttributeGraph` (`random-graph-oracle`).

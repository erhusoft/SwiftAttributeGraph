# Diseño M0: núcleo del motor (versión 2)

Fecha: 2026-11-14. Sustituye a la primera versión de esta nota. Parte de [FUNDAMENTOS.md](FUNDAMENTOS.md),
[PREGUNTAS.md](PREGUNTAS.md) y, sobre todo, de la **paridad medida con SwiftUI real** en
`parity/ANALISIS.md` (macOS 15.7.9). **Estado: implementada** (resultados, límites y lo no verificado en
[PLAN-MOTOR.md](PLAN-MOTOR.md) §6). Desviaciones respecto a esta nota: se añadió el bit `pending` (una regla que
pierde una arista por invalidación debe ejecutarse aunque ninguna versión haya cambiado); no hay `dirtyStamp` (basta
el bit `dirty`); el subgrafo actual vive en el grafo y solo el grafo en ejecución va al almacenamiento por hilo;
la comparación del valor P4 y la opción B de P3/P4 no se construyeron.

> `parity/` (programa de pruebas y resultados de SwiftUI real) es una carpeta **local, no versionada**: sirve para
> otras pruebas, no forma parte del paquete. Los hechos que usa esta nota se citan por su identificador (E1…E19,
> R3-1…R4-5) y se resumen en las tablas de §5 y §8.

## 0. Qué cambió respecto a la versión 1

| Cambio | Motivo |
|---|---|
| El motor se hace para **aplicaciones de escritorio en Swift con sintaxis SwiftUI y paridad** (decisión del dueño) | El corte por valor, los subgrafos y la comparación pasan de «mejoras» a núcleo |
| **Subgrafos desde M0** (versión mínima, plana) | Q4: los atributos nacen en el subgrafo actual; no existe borrado de atributo suelto |
| **Versiones desde M0** en la disposición de datos (el nodo y la arista las llevan) | Q9: sin ellas no se puede saltar un `body` y no hay paridad. M1 añade el algoritmo de corte completo; M0 ya guarda y mueve los números |
| **M2 = política de comparación por atributo**, no un comparador por tipo | SwiftUI compara por **bits**, no con `==` (E13, E14), y con **tres políticas distintas** (§5) |
| El criterio de «correcto» es la **paridad observable** (quién ejecuta y cuándo) | Q10; cada fila de `parity/ANALISIS.md` es un test |

## 1. Alcance de M0

**Entra:**
- `Graph`, `AttributeID`, `Attribute<Value>`, tabla de ranuras.
- **`Subgraph` plano:** crear, fijar como actual, que los atributos nazcan en él e invalidarlo (libera todo lo suyo).
- Nodos de **valor (entrada)** y de **regla**.
- Aristas de entrada en orden de lectura **con versión vista**, y aristas de salida.
- **Versión por nodo** y política de comparación (solo la de *bits* y la de *siempre distinto*; las otras en M2).
- Propagación de sucio, actualización con pila explícita, rastreo con poda, ciclos.
- Lotes y observación.

**No entra** (cada cosa tiene su pieza): jerarquía de subgrafos e invalidación diferida (M5); las otras políticas de
comparación (M2); reglas con estado (M3); lecturas dinámicas sin recursión nativa y reentrada (M4); indirectos (M6);
borrado de arista O(1) (M7); volcado (M8).

**Qué hace M0 con las versiones, y qué deja a M1:** M0 implementa el corte completo para el caso básico: *una regla
sucia no se ejecuta si ninguna entrada, revisada en orden de lectura, tiene otra versión que la vista*. M1 queda
reducida a lo que falte tras medir (por ejemplo la versión global y los atajos); el plan se actualiza con esto.

## 2. API pública (propuesta)

```swift
public final class Graph { public init(); public var nodeCount: Int { get } }   // un hilo, no Sendable

public struct Attribute<Value> { public let id: AttributeID }                   // solo el ID (P1)
public struct Subgraph { public let id: SubgraphID }

extension Graph {
    public func makeSubgraph() -> Subgraph
    public func withCurrent<T>(_ s: Subgraph, _ body: () -> T) -> T            // fija el subgrafo actual
    public func invalidate(_ s: Subgraph)                                       // libera todo lo suyo

    public func makeInput<V>(_ value: V, comparison: Comparison = .bits) -> Attribute<V>
    public func makeRule<R: Rule>(_ rule: R, comparison: Comparison = .bits) -> Attribute<R.Value>
    public func makeRule<V>(_ body: @escaping () -> V) -> Attribute<V>          // atajo (P3)

    public func value<V>(of: Attribute<V>) -> V
    public func setValue<V>(_ v: V, for: Attribute<V>)
    public func withBatch<T>(_ body: () -> T) -> T
    public func observe(_ a: AnyAttribute, onInvalidate: @escaping () -> Void) -> ObservationToken
}
public protocol Rule { associatedtype Value; var value: Value { get } }          // lee con Attribute.value
public enum Comparison { case bits, alwaysDifferent }                             // M2 añade las demás
```

- Errores de programación (ID de un atributo invalidado, ciclo, tipo equivocado, hilo equivocado, escribir dentro de
  una regla): `precondition` con mensaje claro. Nada lanza en M0 (P5).
- No hay `remove(attribute)`: un atributo vive hasta que se invalida su subgrafo (principio 2).
- Hay un subgrafo **raíz** (siempre existe y es el actual por defecto). Así cumple el principio 2 sin forzar a la
  API a pasar un subgrafo en cada llamada.
- **Pendiente de confirmar:** lectura implícita (§9, pregunta 1).

## 3. Identidad y almacenamiento (Identity/, Storage/)

- `AttributeID`: `UInt64`, índice de 32 bits y generación de 32 bits. `Hashable`, `Sendable`. El nulo nunca se reparte.
- `NodeTable`: ranuras con lista libre. Invalidar un subgrafo sube la generación de cada ranura y la devuelve a la
  lista libre; un ID viejo no resuelve nunca, aunque el índice se reutilice.
- **Arreglos paralelos por ranura** (la parte común, sin genéricos ni ARC; medido en G2/G3):

| Campo | Tipo | Contenido |
|---|---|---|
| `generation` | `UInt32` | Validar IDs |
| `state` | `UInt8` | Bits: `isRule`, `dirty`, `observed`, `hasValue`, `evaluating` (2 bits, ciclo) |
| `version` | `UInt32` | Sube **solo si** la política dice que el valor cambió |
| `inputs` | `[InputEdge]` | `(source: UInt32, seenVersion: UInt32)` en **orden de lectura** |
| `outputs` | `[UInt32]` | Dependientes, sin duplicados ni orden |
| `subgraph` | `UInt32` | Dueño |
| `dirtyStamp` | `UInt32` | «Ya visitado en esta pasada» (sin conjunto `visited`) |

- Las aristas guardan **índices**: la arista nunca sobrevive al nodo, porque invalidar un subgrafo quita las aristas.
- **Subgrafo plano:** una tabla de subgrafos (índice + generación) con la lista de índices de sus nodos. Invalidar
  recorre esa lista con un bucle: quita cada nodo de las salidas de sus entradas, y para cada dependiente que esté
  **fuera** del subgrafo quita su arista y lo **marca sucio** (su regla volverá a correr y no encontrará el atributo;
  si lo vuelve a leer, `precondition`). Sin recursión.
- **Dónde vive el valor (P4)** se mide en M0; ver §7.

## 4. Propagación y actualización (Update/)

**Escritura (`setValue`)**:
1. Se aplica la política del atributo (§5). Si el valor cuenta como **igual**: no pasa nada (E4).
2. Si es distinto: se guarda, `version += 1` y se empuja «posiblemente sucio» a los dependientes con una pila
   explícita. No se baja por un nodo que ya estaba sucio (`dirtyStamp`, sin `visited`).
3. Los nodos observados que se ensucian se encolan en una lista de avisos, sin duplicados.
4. Fuera de un lote, los avisos se ejecutan al terminar; dentro, al cerrar el lote más externo (E9: dos escrituras,
   un solo aviso).

**Lectura (`value(of:)`)** de un nodo no sucio: devuelve el valor. De uno sucio:
1. Pila de marcos `(nodo, siguiente entrada a verificar)`. Se recorren sus entradas **en orden de lectura**: cada
   entrada que sea una regla sucia se actualiza primero (apila su marco).
2. Al volver, se compara `source.version` con `edge.seenVersion`. **En la primera diferencia** se ejecuta la regla.
3. Si ninguna difiere: se limpia `dirty` y **no se ejecuta la regla** (es el salto de `body`, E1, E5, E6).
4. Tras ejecutar la regla, su resultado pasa por su política; solo si cuenta como cambio sube `version` (así el corte
   se propaga hacia delante).
5. Ciclo: `evaluating` pasa de 0 a 1 al apilar; apilar un nodo con `evaluating != 0` → `precondition`.

**Orden:** de arriba abajo, entradas en orden de lectura (E10: padre, medio, hojas).
**Reentrada por lectura dinámica:** una regla que lee una entrada nueva llama a `value(of:)` desde dentro y usa la
pila nativa. Es el límite documentado (A11); se quita en M4. M0 lo cubre con un test que fija hasta dónde llega.

## 5. Políticas de comparación (Comparison/)

La paridad exige elegir la política **por atributo** (`parity/ANALISIS.md` §6):

| Política | Cuándo (en la UI) | Comportamiento medido |
|---|---|---|
| `bits` | Valor de una vista; por defecto | Compara los bytes del valor; la referencia por identidad (E14, E15, E16, E18) |
| `bits o ==` | Entorno | Salta si los bits son iguales **o** `==` es verdadero: `0.0 → -0.0`, `nan → nan`, `String` en otro buffer saltan; una clase distinta ejecuta (R3-3, R4-4, R4-5) |
| Escritura de `@State` | `@State` | Depende del tipo: trivial: bits **y** `==`; `Equatable` no trivial (`String`): `==`; resto: bits (R3-2, R4-1…R4-3, E4). Regla inferida, ver `parity/ANALISIS.md` §7 |
| `alwaysDifferent` | Valores que nunca se pueden comparar | Siempre sube la versión |

M0 trae `bits` y `alwaysDifferent`; M2 añade las otras y las afina con la ronda 4 de `parity/ANALISIS.md` si hace
falta.

**Cómo se comparan los bits en Swift (y el riesgo):**
- Se resuelve **una vez al crear el atributo**, sin `Equatable`: se comparan los `MemoryLayout<V>.size` bytes del valor
  anterior y del nuevo con `memcmp`. Para referencias vale: el mismo puntero son los mismos bits (E15), y un objeto
  mutado por dentro cuenta como no cambiado, igual que en SwiftUI.
- **Relleno:** los bytes de relleno entre campos no están garantizados. Una diferencia en el relleno daría un
  «cambió» falso: se ejecuta de más, nunca de menos. Es el fallo seguro. La prueba R3-5 no pudo forzar basura en el
  relleno, así que **no sabemos si SwiftUI lo ignora**. M0 mide con qué frecuencia ocurre en Swift (§7) antes de
  decidir si hace falta una comparación campo a campo.
- El `@State` de una vista **forma parte de sus bits**, incluido su valor inicial (R3-1). Eso lo gestiona la capa de
  UI; el motor solo debe comparar **todos** los bytes del valor de entrada de la regla `body`.

## 6. Rastreo y poda (Tracking/)

- Antes de ejecutar una regla, cada una de sus aristas se marca «sin leer».
- Cada lectura (`Attribute.value` dentro de la regla) busca su arista; si existe, la marca como leída, la **mueve a la
  posición de lectura actual** y apunta la `seenVersion` actual de la fuente. Si no existe, la crea y añade el nodo a
  las salidas de la fuente.
- Al terminar, las aristas «sin leer» se quitan (y el nodo sale de las salidas de su fuente).
- Borrar una arista cuesta O(grado) con arreglos. Riesgo ya anotado en G2; lo resuelve M7. Test de escala en M0.
- **Contexto actual:** almacenamiento por hilo nativo, aislado en **un solo archivo** (`Tracking/ThreadLocalGraph.swift`:
  `TlsAlloc` en Windows, `pthread_getspecific` en el resto). Guarda un puntero no retenido al grafo y el índice del
  nodo en evaluación; lo instala `Graph` al ejecutar una regla y lo restaura al salir.
- **Subgrafo actual:** también en el contexto por hilo; `withCurrent` lo instala y lo restaura.
- **Un grafo, un hilo:** `Graph` guarda el hilo creador y lo comprueba en depuración.
- **La invalidación va al lector, no al dueño del dato** (E5, R3-6): al escribir un atributo solo se ensucian sus
  dependientes; el nodo que lo posee no se marca.

## 7. Qué se mide en M0

Se escribe primero lo simple y se mide frente a la alternativa, en release, mediana de ≥ 5 ejecuciones alternadas:

| Decisión | A (por defecto) | B (alternativa) | Test |
|---|---|---|---|
| P4 valor | Una clase caja por nodo con el valor | Almacén por tipo (`[Value]`) | 100.000 nodos, crear y leer cada uno 10 veces |
| P3 regla | Tipo `Rule` con función de evaluación especializada | Cierre `() -> Value` | Crear 100.000 reglas; 500 reglas × 1.000 dependientes |
| Comparación | `memcmp` del valor | `==` cuando `Equatable` | 1 millón de escrituras de `Int`, `Double`, `String`, struct pequeño |
| Relleno | — | — | Cuántos structs típicos con relleno dan «cambió» falso |

Referencias que no se deben empeorar (SwiftGraph, Windows ARM64, release): 500 escrituras / 1.000 dependientes
**≤ 22,5 ms**; 32 escrituras en lote / 1.000 compartidos **≤ 0,28 ms**; 20.000 ámbitos de rastreo vacíos **≤ 1,71 ms**.
Propuesta de presupuesto: el motor no debe pasar de **~10 % del frame** (1,6 ms de 16) en el caso objetivo
(1.000 filas, 5–10 atributos por fila, un subgrafo por fila); a confirmar con el dueño.

## 8. Tests (primero; deben fallar antes de implementar)

**Paridad** (`Tests/…/Parity/`): cada fila de `parity/ANALISIS.md` §1, §2 y §6 se traduce a una prueba del motor,
donde «`body`» es una regla cuya entrada es el atributo «valor de la vista»:

| Medición de SwiftUI | Prueba del motor |
|---|---|
| E1 hijo que no recibe el dato se salta | Regla con entrada sin cambio de versión no se ejecuta |
| E2/E18 cierre sin / con capturas | Mismos bits → no cambia; otro contexto → cambia |
| E3/E16 array recreado / guardado | Otro puntero → cambia; mismo puntero → no |
| E4 mismo valor escrito | No sube versión, no ensucia, no avisa |
| E5 estado de hermanos | Escribir un atributo solo ensucia a sus lectores |
| E6 entorno: quien no lo lee, se salta | Un nodo sin arista a la fuente no se ejecuta |
| E7 cambio de rama | Invalidar el subgrafo libera todo; uno nuevo nace con estado inicial |
| E8/E19 `ForEach` por id | Un subgrafo por id; reordenar no crea ni ejecuta nada |
| E9 dos escrituras = un `body` | `withBatch`: un solo aviso |
| E10 orden | Padre, medio, hojas; entradas en orden de lectura |
| E11 dependencia por propiedad | Leer una propiedad crea la arista con ese atributo, no con otro |
| E13/E14 `==` mentiroso, `-0.0`, `nan` | La política `bits` ignora `==` |
| E15 identidad de clase | Mismo puntero: igual; otro: distinto |
| R3-1 `@State` constante o aleatorio | Valor inicial constante: sin cambio; aleatorio: cambia |
| R3-6 `@Binding`/`@Bindable` | La invalidación va al lector, no al dueño |

**Unidad / oráculo / profundidad / vida / rendimiento:**

| Carpeta | Tests |
|---|---|
| Unit | ID viejo falla tras reutilizar ranura; el nulo no se reparte; lectura perezosa (la regla no corre hasta que se pide); poda de una dependencia condicional; orden de lectura tras la poda; ciclo → `precondition` (con prueba de salida); `withBatch` anidado coalesce avisos; un aviso que escribe de nuevo |
| Oracle | Grafos aleatorios (semillas fijas) con entradas y reglas con lecturas condicionales. **Valores:** el motor coincide con un modelo que lo recalcula todo. **Ejecuciones:** el modelo cuenta que una regla corre si y solo si alguna entrada que leyó cambió de versión desde su última ejecución; el motor ejecuta exactamente esas |
| Depth | Cadena de 20.000 reglas (escritura en la raíz, lectura al final); 20.000 dependientes de una entrada; invalidar un subgrafo con 20.000 nodos; la lectura dinámica de 20.000 niveles **documenta** el límite (M4 lo quita) |
| Lifetime | `nodeCount` vuelve a la base tras crear e invalidar N subgrafos mezclados; invalidar quita las aristas de los dos lados; las ranuras no crecen con altas y bajas continuas |
| Performance | Los de §7, marcados para `--filter Performance` |

## 9. Preguntas que siguen abiertas

1. **Lectura implícita.** `Attribute.value` dentro de una regla usa el grafo y el nodo actuales del contexto por hilo
   (como AttributeGraph). La alternativa es pasar un contexto a la regla. Propuesta: implícita, por nombres y modelo
   de AttributeGraph (FUNDAMENTOS P2). Es la decisión de API más cara de cambiar después.
   **Se adopta como supuesto de trabajo** (el dueño pidió seguir con los pasos sin objetar); se revisa antes de M0
   si hay una razón en contra.
2. **Escribir dentro de una regla.** La propuesta es prohibirlo en M0 (`precondition`) porque SwiftUI no lo mide aún.
   Si la capa de UI lo necesitara, se medirá en Mac antes de permitirlo.
3. **Lectura que copia o presta.** `value(of:)` devuelve una copia (con copy-on-write de Swift). Una lectura prestada
   (`withValue`) se añade solo si la medida lo pide.
4. **Presupuesto del motor (~10 % del frame) y el caso objetivo** (§7): a confirmar.
5. **Ronda 4 de paridad** (políticas de entorno y escritura de estado con `String` largo y clases): no bloquea M0;
   se hace antes de M2.

## 10. Riesgos

- **Falsos «cambió» por relleno** (§5): se ejecuta de más, no de menos. Se mide y, si pesa, se compara campo a campo.
- **Una sola versión de macOS medida** (15.7.9). Si Apple cambia el comportamiento, la especificación cambia; por eso
  los tests de paridad son una carpeta aparte, fácil de actualizar.
- **Borrado de arista O(grado)** (M7). Mitigado con el test de escala.
- **Lecturas dinámicas reentran en la pila nativa** (M4). Documentado, con test.
- **TLS aislado en un archivo**: la rama `pthread` no se compila aquí; se marca «no verificado».
- **Swift 6 estricto con estado global:** la ranura TLS va como `nonisolated(unsafe)` con su justificación en `///`.
- **Versión en la arista desde M0:** si el diseño de M1 pide otro formato, se reescribe `InputEdge` antes de que
  haya más código encima; por eso se decide ahora.

## 11. Orden de trabajo

1. Responder §9 (sobre todo la 1).
2. Leer los tests antiguos de SwiftGraph que cita el plan y fijar qué se traduce y qué se descarta.
3. `AttributeID`, `NodeTable`, subgrafo plano y sus tests.
4. `makeInput`/`value`/`setValue` con versión y política `bits`.
5. Propagación de sucio, avisos y lotes.
6. Reglas, pila de actualización con corte por versión, TLS y poda.
7. Ciclos y `precondition`.
8. Paridad, oráculo, profundidad y vida.
9. Medidas de §7; resultados en `PLAN-MOTOR.md`.
10. Un solo commit de la pieza.

## 12. Qué se hace con los tests antiguos de SwiftGraph (leídos el 2026-11-14)

Se leyeron los seis archivos que cita el plan (`GraphTests`, `GraphOracleTests`, `GraphStructuralOracleTests`,
`NodeLifecycleTests`, `NodeStorageTests`, `TrackingContextStorageTests`; 668 líneas). Tres diferencias de modelo
condicionan la traducción:

1. **La API antigua lanza (`try`) y tiene aristas manuales** (`addEdge`, `removeEdge`, `graph.edges`, `parents`,
   `children`). El motor nuevo **descubre las aristas al leer**, no tiene API de aristas y trata los errores de
   programación con `precondition` (P5). Los tests de lanzar se convierten en pruebas de salida (`#expect(processExitsWith:)`
   de Swift Testing; **hay que comprobar que existe en este toolchain**).
2. **No existe borrar un nodo suelto**: solo se invalida un subgrafo.
3. **No hay UI**: `State`, `ViewTreeReconciler` y `ViewIdentity` no existen en este paquete.

| Test antiguo | Decisión | Cómo queda |
|---|---|---|
| `testPullRecomputeIsLazyAndUpdatesDependents` | **Traducir** | Escribir no ejecuta; leer ejecuta una vez; lectura limpia no ejecuta |
| `testLinearGraphWithTenThousandNodes` | **Traducir y ampliar** | 20.000 niveles (principio 1) |
| `testTwoNodesThatReadEachOtherThrowACycle…` | **Traducir** | Ciclo descubierto al leer → `precondition` (prueba de salida) |
| `testRemovingANode/RemovingAnEdge/AddingAnEdge…Dirties…Descendants` | **Adaptar** | Invalidar un subgrafo ensucia a **todos** los descendientes que viven fuera, no solo a los hijos. Los de «añadir/quitar arista» se descartan: no hay API de aristas |
| `testOnlyRequestedBranchesRecompute` | **Traducir** | 50 hojas; solo se ejecuta la que se lee |
| `testCycleDetectionRejectsEdgeWithoutChangingGraph` | **Descartar** | Dependía de `addEdge`; el ciclo ya se cubre al leer |
| `testSubgraphInsertAndRemovePreserveGraphConsistency` | **Adaptar** | `makeSubgraph` + `invalidate`; `nodeCount` vuelve a la base y las salidas de nodos externos quedan limpias |
| `testRemovingANodeOfASubgraph…` | **Descartar** | No hay borrado de un nodo suelto |
| `GraphOracleTests.testRandomDAGsMatchFullRecalculation…` | **Traducir** | Mismo generador; reglas con lecturas dinámicas; **añade el oráculo de ejecuciones** (§8) |
| `testDynamicBranchPrunesUnreadDependencies` | **Traducir** | Entradas exactas tras la poda (con un acceso `package` a las entradas de un nodo); la escritura de una fuente podada no ejecuta ni avisa |
| `testRandomDynamicBranchesMatchOracleAndTrackExactParents` | **Traducir** | Ídem, 8 semillas |
| `testFailedComputationCanRetryAfterInputChanges` | **Descartar** | Las reglas no lanzan (la paridad no mide reglas que fallan). Se reabre si la UI lo pide |
| `GraphStructuralOracleTests` | **Adaptar** | El modelo cambia: los «padres» de cada salida pasan a ser el conjunto de lecturas que su regla hace (se altera con una bandera por fuente); borrar un nodo = invalidar un subgrafo |
| `NodeLifecycleTests.testStaleTrackedEdgesArePruned…` | **Traducir** | Poda por regla condicional |
| `…testManualEdgesAreNotPruned` | **Descartar** | No hay aristas manuales |
| `…testStateNodesAreReleasedWithOwningView`, `…testCreatingAndDestroyingManyViewsLeavesNoNodes` | **Adaptar** | Sin vistas: 20 rondas de 1.000 subgrafos con atributos; `nodeCount` vuelve a la base |
| `NodeStorageTests` (los cinco) | **Traducir** | Reutilización de ranura con generación nueva; ID viejo nunca resuelve; el ID nulo no se reparte; invalidar todo invalida todos los IDs; tabla acotada con altas y bajas continuas |
| `TrackingContext…testContextIsRestoredAfterTheScopeThrows` | **Adaptar** | El contexto vuelve al anterior tras una regla anidada (no hay `throws`) |
| `…testNestedGraphsKeepTheOutermostGraph…` | **Descartar** | Leer un atributo de **otro grafo** desde una regla es un error de programación (`precondition`): un grafo por hilo |
| `…testEachThreadSeesOnlyItsOwnContext` | **Traducir** | Dos hilos con grafos distintos; el contexto no se mezcla (los tests pueden usar `Thread` aunque el motor no use Foundation) |
| `…testDeeplyNestedScopesUnwindToNoContext` | **Traducir** | Anidación de 100 niveles; el límite nativo se documenta (M4 lo elimina) |

**Resultado:** de 28 tests antiguos, **21 se traducen o adaptan y 7 se descartan** con el motivo de la tabla (aristas
manuales, borrado de un nodo suelto, reglas que lanzan, varios grafos en un hilo). A ellos se suman los de paridad (§8).

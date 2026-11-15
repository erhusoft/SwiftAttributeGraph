# Fundamentos del motor: preguntas antes de escribir código

Fecha: 2026-11-14. **Antes de M0.** Este documento fija la tecnología, la estructura de carpetas y los elementos del
motor, y lista las preguntas de diseño con una propuesta para cada una. Las marcadas **[dueño]** las decide el
dueño; las marcadas **[medida]** se deciden con un test y una medida en M0.

**Decisiones del dueño (2026-11-14):**

| Pregunta | Decisión |
|---|---|
| P1, API pública | `Attribute<Value>` ligero (solo el ID) |
| P2, nombres | Los de AttributeGraph donde coincida el concepto (`Attribute`, `Rule`, `StatefulRule`, `Subgraph`…) |
| Tests | Swift Testing |
| P5, errores | `precondition` para los errores de programación; `throws` solo para lo recuperable |
| P6, hilos | Un grafo por hilo |
| P8, tiempo y animaciones | Fuera del motor |
| P9, compatibilidad con `GraphNode` | No |

Quedan para medir en M0: P3 (forma de la regla) y P4 (dónde vive el valor).

## 1. Tecnología

| Pregunta | Propuesta | Motivo |
|---|---|---|
| ¿Qué lenguaje? | Swift puro | La ganancia medida en SwiftGraph vino de las estructuras de datos, no del lenguaje (G1–G3: 3,8×; G5: 18×) |
| ¿Qué versión de Swift? | `swift-tools-version: 6.2`, toolchain 6.4.1 | Comprobado en esta máquina (ARM64): compilan `~Copyable`, `InlineArray`, `Span`, `throws` tipado y `_isPOD` |
| ¿Modo de concurrencia? | Swift 6 estricto | Un grafo por hilo; los tipos del motor no son `Sendable` salvo los ID, y el compilador lo hace cumplir |
| ¿Foundation? | **No** en el motor | Sin dependencias (P5). Para el tiempo de los tests de rendimiento basta `ContinuousClock` de la biblioteca estándar |
| ¿Almacenamiento por hilo? | TLS nativo (`TlsAlloc` en Windows) aislado en un solo archivo | G5. Si un día se porta, se cambia solo ese archivo |
| ¿Punteros `Unsafe*`? | Solo dentro de los tipos de almacén, nunca en la API pública, y cada uso con su test | Rendimiento sin perder la seguridad en la superficie |
| ¿Framework de tests? | **Swift Testing** (`@Test`, `#expect`) | Decidido por el dueño (2026-11-14). Funciona en este toolchain |
| ¿Cómo se mide? | Tests de rendimiento marcados, en release, con mediana de varias ejecuciones; resultados en `PLAN-MOTOR.md` | Lo aprendido: en la máquina virtual hay mucho ruido, así que una sola ejecución no vale |
| ¿Plataformas? | Windows ARM64 (principal) y x64 | Igual que SwiftGraph |

## 2. Estructura de carpetas

Un solo módulo público (`SwiftAttributeGraph`). Lo interno se marca `internal` o `package`. Carpetas por
responsabilidad y un tipo principal por archivo:

```
Sources/SwiftAttributeGraph/
  Identity/      AttributeID (índice + generación), SubgraphID
  Storage/       Tabla de ranuras, lista libre, almacén de valores
  Node/          Parte común del nodo (estado, banderas, versión), aristas de entrada y de salida
  Graph/         Graph: crear, leer, escribir, quitar; contadores
  Rule/          Rule, StatefulRule (o cierres, según §4), contexto de regla
  Update/        Propagación de sucio, pila de actualización, verificación por versiones
  Tracking/      Contexto de lectura actual (TLS), registro y poda de dependencias
  Subgraph/      Jerarquía, subgrafo actual, invalidación diferida
  Comparison/    Comparador por tipo (Equatable, tipos triviales, «siempre distinto»)
  Indirect/      Atributos indirectos y desplazados (M6)
  Debug/         Volcado del grafo, trazas, contadores de memoria
Tests/SwiftAttributeGraphTests/
  Unit/          Una carpeta por carpeta de Sources
  Oracle/        Comparación con un modelo de referencia simple (recalcular todo) en grafos aleatorios
  Depth/         Profundidad ≥ 20.000 por cada recorrido (P1)
  Lifetime/      nodeCount vuelve a la base (P2)
  Performance/   Medidas en release
docs/            FUNDAMENTOS.md (este), PLAN-MOTOR.md, una nota de diseño por pieza
```

## 3. Elementos que necesita el motor

| Elemento | Responsabilidad | Pieza |
|---|---|---|
| `AttributeID` | Nombrar un atributo; detectar IDs de atributos ya borrados | M0 |
| Tabla de ranuras | Guardar nodos por índice; reutilizar huecos | M0 |
| Nodo de valor (entrada) | Valor escrito desde fuera; compara al escribir | M0 |
| Nodo de regla | Valor calculado a partir de otros; perezoso | M0 |
| Aristas | Entrada: fuente y versión vista. Salida: dependiente | M0, M1, M7 |
| Propagación | Marcar «posiblemente sucio» hacia delante, iterativo | M0 |
| Actualización | Recalcular al leer, con pila explícita, en orden de lectura | M0, M4 |
| Versiones y corte | No recalcular si ninguna entrada cambió de versión | M1 |
| Comparador por tipo | Igualdad rápida resuelta una vez | M2 |
| Rastreo | Saber qué lee la regla en curso; podar lo no leído | M0, M7 |
| Reglas con estado | Valor anterior; qué entradas cambiaron | M3 |
| Subgrafos | Dueños jerárquicos; liberar en bloque; invalidación diferida | M5 |
| Indirectos | Redirigir o leer un campo de otro atributo | M6 |
| Observación | Avisar al cliente (la UI) cuando algo que observa queda sucio | M0 |
| Lotes | Agrupar escrituras en una sola propagación | M0 |
| Ciclos | Detectarlos y dar un error claro | M0 |
| Depuración | Volcado, contadores, memoria | M8 |

## 4. Preguntas de diseño

| # | Pregunta | Opciones | Propuesta | Quién |
|---|---|---|---|---|
| P1 | ¿Cómo es la API pública? | (a) `Attribute<Value>`: un *struct* ligero con solo el ID, como AttributeGraph. (b) Un objeto nodo, como el `GraphNode` actual | **(a)**: es lo que espera una capa tipo SwiftUI, no expone el almacén y no hay ARC por atributo en la API | [dueño] |
| P2 | ¿Nombres como los de AttributeGraph (`Attribute`, `Rule`, `StatefulRule`, `Subgraph`, `WeakAttribute`)? | Sí / nombres propios | **Sí**, en lo que coincida el concepto: facilita traducir las ideas de OpenSwiftUI y de la documentación existente | [dueño] |
| P3 | ¿Cómo se escribe una regla? | (a) Cierre `() -> Value`. (b) Tipo con `var value` que cumple `Rule` | **Las dos**: el tipo como forma principal (sin reservar un cierre por nodo) y el cierre como atajo | [medida] |
| P4 | ¿Dónde vive el valor? | En el objeto nodo / en almacenes por tipo | Empezar en el nodo (lo probado en G2) y medir | [medida] |
| P5 | ¿Errores? | `throws` en todas partes / `precondition` para errores de programación | **Mixto**: ID de un atributo borrado, ciclo o tipo equivocado son errores de programación (`precondition` con mensaje claro); solo lo recuperable lanza | [dueño] |
| P6 | ¿Hilos? | Un grafo por hilo / grafo compartido con candados | **Un grafo por hilo**, comprobado en depuración | [dueño] |
| P7 | ¿Qué es «igual» para un tipo no `Equatable`? | Siempre distinto / comparar bytes si es trivial / reflexión | **Equatable → `==`; trivial (`_isPOD`) → bytes; resto → distinto** | Decidido por los estudios |
| P8 | ¿El tiempo y las animaciones van en el motor? | Sí, como AttributeGraph / No | **No**: el motor da «valor y versión»; el tiempo es una entrada más que pone la UI | [dueño] |
| P9 | ¿Hace falta compatibilidad con el `GraphNode` actual de SwiftGraph? | Sí / no | **No**: proyecto nuevo. La UI se adaptará una vez, al conectar | [dueño] |
| P10 | ¿Cómo se demuestra que funciona? | Tests unitarios / más un oráculo | **Oráculo**: grafos aleatorios comparados con un modelo simple que lo recalcula todo, más los tests de profundidad, de vida y de rendimiento | Decidido |

## 5. Lo que este documento cambia del plan

Una vez respondidas las preguntas **[dueño]**:
- `PLAN-MOTOR.md` §2 y §4 se actualizan con las respuestas.
- `Package.swift` pasa a `swift-tools-version: 6.2` y se crea la estructura de carpetas de §2.
- Empieza M0.

## 6. Preguntas de comportamiento frente al AttributeGraph de Apple

Añadido tras M0–M9. La hipótesis de trabajo es que **el grafo construido coincide con el AttributeGraph original**.
Como Apple no publica su código, la única vía es la ingeniería inversa por comportamiento: se formula una pregunta, se
**fija la predicción antes de medir**, se observa en el nativo (`NativeProbe` + `AGTrace`) y en nuestro motor, y se comparan
«ejecuta / salta» y los contadores por regla. Acertar sube la confianza sin demostrar nada general; una divergencia
obliga a corregir el motor o la hipótesis.

Una buena pregunta se responde observando, puede salir mal y es estrecha (una sola cosa por escenario).
Estado: **auditadas y alineadas en macOS 15.7.9 (M1)** con los 21 escenarios de `NativeProbe` (3 pares debug + 3 pares release, 100 % de paridad en las 21 trazas) y sondas de `AGTrace`.

| # | Tema | Pregunta | Resultado medido en `AttributeGraph` de Apple y estado en `SwiftAttributeGraph` |
|---|---|---|---|
| C1 | Reglas con estado | Si la regla no cambia su valor, ¿cuenta como cambio para sus dependientes? | **No.** Si `StatefulRule` no escribe `value` (o escribe un valor igual), la versión no sube y sus dependientes se saltan (`stateful-no-write-cut`: `sRuns=[1,2,3,4]`, `oRuns=[1,1,2,2]`). Coincide 100 %. |
| C2 | Reglas con estado | ¿Se ejecuta cuando cambia una entrada que no leyó la última vez? | **No.** Cambiar una rama no leída o podada en la evaluación anterior no ensucia ni ejecuta la regla con estado (`stateful-unread-input`: `runs=[1,1,2,2]`). Coincide 100 %. |
| C3 | Reglas con estado | ¿Ve el valor anterior si se invalidó y se restauró antes de leer? | **Sí.** Si una entrada directa se muta y se restaura (`5 -> 6 -> 5`) antes de leer, la regla sigue sucia, ejecuta con `hasValue == true`, lee su `value` previo (`50`) y `changedValue` reporta `changed == true` (`stateful-has-value-and-revert`). Coincide 100 %. |
| C4 | Selectores | Al cambiar de rama, ¿se poda de inmediato la dependencia que ya no se lee? | **Sí.** Confirmado con `AGTrace` (`remove_edge` inmediato al cerrar `update_attribute` del selector) y con `dynamic`. Coincide 100 %. |
| C5 | Selectores | ¿Importa el orden de lectura para el corte (leer A antes que B)? | **No.** El nativo guarda las aristas ordenadas por `AttributeID` creciente y actualiza **todas** las entradas sucias previas antes de decidir si la regla corre (`selector-input-order`: `[2,2,2]` tanto leyendo `A+B` como `B+A`). Alineado en `611b35c`. |
| C6 | Selectores | Con varias entradas que cambian a la vez, ¿cuántas veces ejecuta? | **Una sola vez** al tirar de la salida, tras actualizar todas sus entradas sucias previas (`diamond-multiple-*`). Coincide 100 %. |
| C7 | Diamantes | ¿Puede una regla ver una mezcla de valores viejos y nuevos? | **No (*glitch-free*).** La unión actualiza ambas ramas antes de evaluarse (`diamond-source-*` y `diamond-multiple-*`). Coincide 100 %. |
| C8 | Diamantes | Si se pide primero la hoja o la raíz, ¿cambia el número de ejecuciones? | **No.** Leer una rama intermedia antes de la unión adelanta su evaluación sin duplicarla cuando se lee la unión (`diamond-source-*` paso 3). Coincide 100 %. |
| C9 | Vida | Si se invalida el subgrafo durante una regla, ¿termina o falla? | **Termina.** `child.isValid` pasa a `false` de inmediato, mientras que los atributos del subgrafo siguen legibles hasta que termina el `update` en curso (`invalidate-in-rule`). Al invalidar un subgrafo, las aristas hacia lectores externos se desconectan (`remove_edge`) sin ensuciar a esos lectores (`weak-attribute-in-rule`). Alineado en `91cbc51`. |
| C10 | Vida | ¿Qué ocurre al leer un atributo ya borrado? | En `AttributeGraph` nativo sobre un atributo directo destruido aborta; a través de `WeakAttribute` devuelve `nil` sin crear aristas (`weak-attribute-in-rule`). En nuestro motor, leer un `Attribute` muerto dispara `precondition` y `WeakAttribute` devuelve `nil`. Coincide 100 %. |
| C11 | Escrituras | ¿Escribir el mismo valor propaga algo? | **No.** Escribir un valor igual según la política de comparación no sube versión ni marca sucios a los lectores (`cut` y `diamond-*`). Coincide 100 %. |
| C12 | Escrituras | Dentro de una regla, ¿se permite escribir? | **No.** Es un error de programación (`precondition` en `setValue` y `setSource` cuando `evaluatingNode != noNode`). Coincide 100 %. |
| C13 | Ciclos | ¿Un ciclo falla, se corta o se queda colgado? | **Falla determinísticamente** al detectar reentrada sobre un nodo en evaluación (`NodeState.evaluating` / ciclos en `setSource`). Coincide 100 %. |
| C14 | Comparación | ¿Se puede comparar solo parte de un valor para decidir si cambió? | **Sí.** Con `Focus<Root, Value>` / `makeFocus(_:keyPath:)` (`focus-keypath-cut`: cambiar otro campo del `struct` corta a los lectores del campo proyectado) y `ComparisonPlan` (M2). Implementado en `6cb030f`. |
| C15 | Débiles | ¿Qué lee un atributo débil cuando su destino ya no existe? | **`nil`**, tanto en `weakAttribute.value` como en `changedValue(of: weakAttribute)`, y mientras vive registra una dependencia normal (`weak-attribute-in-rule`). Implementado y verificado en `91cbc51`. |
| C16 | Plazo | ¿Una actualización puede abandonarse al pasar un plazo y qué queda sin evaluar? | Fuera del alcance del motor (P8: tiempo y animaciones viven fuera del motor). |
| C17 | Búsqueda | ¿En qué orden recorre las entradas una búsqueda por anchura? | **Por `AttributeID` creciente**, con independencia del orden en que la regla leyó sus entradas (verificado con `breadthFirstSearch(options: .searchInputs)` en permutación no monótona `[E2, E3, E1]`). Alineado en `611b35c`. |
| C18 | Externos | ¿Cómo se comportan los atributos externos, sin regla ni valor propio? | `IndirectAttribute` redirige a cualquier atributo (entrada o regla), permite cambiar `source` con `setSource` (ensuciando con `pending` si cambia el ID de destino aunque el valor coincida) y mantiene una sola arista en el lector (`indirect-rule-and-redirect`). Alineado en `74fad4c`. |
| C19 | Trazas | ¿Los eventos de ciclo de vida permiten observar el orden de ejecución sin depender solo de contadores? | **Sí.** `AGTrace` expone callbacks de ciclo de vida (`begin_update_stack`, `begin_update_attribute`, `add_edge`, `remove_edge`, `set_edge_pending`, `set_dirty`, `set_pending`, `set_source`), usados en esta auditoría para verificar C4, C5, C9, C15, C17 y C18. |
| C20 | IDs | ¿Cómo asigna Apple los `AttributeID` y los reutiliza al borrar? Si las aristas se ordenan por ID, ¿la reutilización de huecos cambia el orden de las entradas? | Apple asigna `AGAttribute` como desplazamientos dentro de páginas por subgrafo (en pasos de 40 bytes dentro de una página y 512 bytes entre páginas) y reutiliza páginas liberadas cuando se invalida un subgrafo (`b1=536 -> s2.invalidate() -> c1=536`). En ambos motores, reutilizar una ranura/página anterior con un índice menor coloca esa entrada antes en el arreglo ordenado de `inputs` (`slot-reuse-input-order`). Coincide 100 %. |
| C21 | Lotes | ¿Escribir dos veces el mismo valor dentro de un lote cambia el número de ejecuciones frente a escribirlo una vez? | **No.** La segunda escritura igual es filtrada por el comparador de entrada (`store` devuelve `false`) y las escrituras sucesivas antes de leer se coalescen en una sola evaluación perezosa (`duplicate-writes-before-read`: `runs=[3, 3]`). Coincide 100 %. |
| C22 | Lecturas | ¿Qué pasa si una regla lee la misma entrada dos veces, o la lee y deja de leerla en la misma ejecución: cuántas aristas quedan? | **Queda una única arista deduplicada** (`AGTrace` emite un solo `add_edge` en la primera lectura), y cuando en una evaluación posterior deja de leerse, esa única arista se poda por completo (`double-read-and-prune`: `runs=[1, 2, 3, 3]`). Coincide 100 %. |
| C23 | Indirectos | ¿Se ensucia un indirecto cuyo destino se invalida, y qué lee el lector después? | **No se ensucia, y si estaba redirigido vuelve a su `initialSource`.** Al invalidar el subgrafo dueño del `source` al que se redirigió un `IndirectAttribute`, el nativo restablece automáticamente `ind.source` a su `initialSource` original (reconectando `ind <- initialSource`) sin marcar sucios ni al indirecto ni a sus lectores externos (`reader` conserva su valor cacheado `78` con `runs=2`, y al cambiar después `initialSource` a `99` el lector pasa a `100` con `runs=3`, `indirect-source-invalidated`). También expone `resetSource(for:)`. Coincide 100 %. |
| C24 | Aleatorios | ¿Coinciden las ejecuciones y los valores entre nativo y propio en grafos aleatorios, y no solo en escenarios escritos a mano? | **Sí, al 100 %.** Verificado en dos oráculos deterministas contra `AttributeGraph` nativo: `random-graph-oracle` (6 semillas × 50 pasos con 6 entradas y 24 reglas mixtas `Rule` + `StatefulRule`, `runs=[95, 108, 105, 100, 95, 107]`) y `random-subgraph-weak-indirect-oracle` (6 semillas × 45 pasos mezclando creación/invalidación dinámica de subgrafos hijos, `WeakAttribute` e `IndirectAttribute` con `setSource`, `runs=[115, 96, 106, 66, 96, 89]`). |

**Origen de C14–C19:** sugeridas por los **nombres** de las pruebas de `CompatibilityTesting` de
[jcmosc/Compute](https://github.com/jcmosc/Compute) (licencia MIT): `PartialComparisonTests`, `WeakAttributeTests`,
`GraphDeadlineTests`, `AttributeSearchTests`, `ExternalTests` y `Tracing*`. No se ha leído el contenido de esas
pruebas ni se copia código; son solo ideas para formular preguntas propias.

**Límites:** lo observado vale para el runtime y chip medidos (macOS 15.7.9, M1) y puede cambiar con otra versión.

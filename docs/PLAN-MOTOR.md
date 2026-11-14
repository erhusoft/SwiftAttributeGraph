# Plan del motor SwiftAttributeGraph

Fecha: 2026-11-14. **Fuente de verdad del estado.** Hechas M0 ([§6](#6-resultados-de-m0)), M2 ([§7](#7-resultados-de-m2)), M3 ([§8](#8-resultados-de-m3)) y M5 ([§9](#9-resultados-de-m5)).
M4 sigue pendiente: la [propuesta revisada](DISENO-M4.md) tiene un prototipo aislado autorizado y validado en Mac
([§10](#10-prototipo-aislado-de-m4)); faltan rendimiento e integración y decidir la migración de API. No se implementa
el cambio a hilos auxiliares.
Hecho antes: fundamentos, preguntas previas ([PREGUNTAS.md](PREGUNTAS.md)), medición de paridad con SwiftUI real
y las notas de diseño ([DISENO-M0.md](DISENO-M0.md), [DISENO-M2.md](DISENO-M2.md), [DISENO-M3.md](DISENO-M3.md), [DISENO-M5.md](DISENO-M5.md)).

## 1. Objetivo y criterio de «motor al 100 %»

Un motor de grafo de atributos **completo y verificado** antes de conectarle una UI. «Al 100 %» significa:
1. Todas las piezas M0–M9 de §3 están hechas, con sus tests en verde.
2. La batería de especificación (M9) pasa: oráculos de comportamiento, profundidad ≥ 20.000 sin recursión, vuelta
   de `nodeCount` a la base y rendimiento medido.
3. Cubre lo que una capa de vistas tipo SwiftUI necesita, según `ESTUDIO-OPENSWIFTUI-VISTAS.md` en el repositorio
   SwiftGraph: atributos persistentes con dueño, `body` como regla que se salta si nada cambió, subgrafos para ramas y
   colecciones, y entradas y salidas como atributos.

**Fuera de alcance:** vistas, layout, dibujo, ventanas, accesibilidad e hilos múltiples sobre un mismo grafo.

## 2. Decisiones de diseño de partida (de los estudios y de las medidas en SwiftGraph)

| Tema | Decisión | Por qué |
|---|---|---|
| Identidad | `AttributeID` = índice de 32 bits + generación de 32 bits | Salsa; medido en SwiftGraph (G1) |
| Almacén | Tabla de ranuras con lista libre; la generación invalida los IDs viejos | G1 |
| Nodo | Parte común no genérica (estado, aristas, banderas) separada del valor tipado | G2/G3: 3,8× en propagación |
| Aristas | Arreglos de enteros; la de entrada es un registro `(fuente, versión vista, banderas)` | Compute, Signals |
| Sucio | Separar «posiblemente sucio» (empuje) de «cambió de verdad» (versión) | Las cuatro fuentes coinciden |
| Corte | Versión por nodo, que sube solo si el valor cambió; se verifica en orden de lectura | Signals; Salsa y Compute equivalentes |
| Rastreo | Contexto actual en almacenamiento por hilo nativo, sin diccionarios | G5: 18× |
| Actualización | Pila explícita con índice de reanudación por marco, también para lecturas dinámicas | Compute `UpdateStack`; P1 |
| Vida | El subgrafo es el dueño: jerárquico y con invalidación diferida durante una actualización | Compute, OpenSwiftUI |
| Lenguaje | Swift puro | Ver la discusión en SwiftGraph: la ganancia está en la estructura de datos, no en el lenguaje |

## 3. Piezas

Cada pieza sigue el proceso de `AGENTS.md` §4. **Orden:** M0 primero; el resto en el orden de la tabla salvo que
una pieza descubra otra cosa.

| # | Pieza | Qué incluye | Criterio de terminado | Estado |
|---|---|---|---|---|
| M0 | **Núcleo** | `Graph`, tabla de ranuras, `AttributeID`, **subgrafo plano** (los atributos nacen en el subgrafo actual; invalidarlo libera lo suyo), nodos de valor y de regla, aristas de entrada **con versión vista**, **versión por nodo**, propagación de sucio, recálculo perezoso con pila explícita, rastreo de lecturas, poda, lotes y observación. Comparación: solo `bits` y «siempre distinto» | Detalle en [DISENO-M0.md](DISENO-M0.md): 21 tests antiguos de SwiftGraph traducidos o adaptados (7 descartados con motivo), más los de **paridad** con SwiftUI real, oráculo de valores y de ejecuciones, profundidad ≥ 20.000, vida y rendimiento | ✅ ([resultados](#6-resultados-de-m0)) |
| M1 | **Corte por versiones (resto)** | M0 ya hace el corte básico (una regla sucia no corre si ninguna entrada, en orden de lectura, cambió de versión). M1 queda para lo que falte tras medir: versión global y atajos | Test: una regla que da el mismo valor no hace recalcular a sus dependientes; medida del atajo | 🔴 |
| M2 | **Políticas de comparación por atributo** | Cuatro políticas más `bits`, resueltas una vez por tipo y política al crear el atributo (caché por grafo): `viewValue` (por defecto), `environment`, `stateWrite`, `alwaysDifferent`. Reglas medidas en SwiftUI real en [DISENO-M2.md](DISENO-M2.md) §2 (campo a campo; hoja trivial por bytes en la vista y `==` en `@State`; existenciales por su tipo dinámico) | Cada política reproduce las filas medidas en SwiftUI real (caliente); sin `as? any Equatable` en el camino de escritura; medida de escrituras; el relleno no se compara | ✅ ([resultados](#7-resultados-de-m2)) |
| M3 | **Reglas con estado** | `StatefulRule` y `RuleContext`: valor anterior, poder no cambiarlo, `hasChanged`, `anyInputsChanged(excluding:)`, `changedValue(of:)` y estado propio (`mutating`); forma de tipo y de cierre | Tests de una regla que acumula y de una que solo reacciona a una entrada concreta; profundidad 20.000; el estado se libera con el subgrafo | ✅ ([resultados](#8-resultados-de-m3)) |
| M4 | **Actualización sin recursión total** | Las lecturas dinámicas dentro de una regla tampoco usan la pila nativa; reentrada (actualización anidada). [Diseño revisado](DISENO-M4.md): prototipo aislado de reglas reanudables validado en Mac ([§10](#10-prototipo-aislado-de-m4)); integración y migración de API pendientes; se mantiene el hilo original | Cadena de 20.000 lecturas dinámicas no declaradas sin desbordar; test de reentrada; resolver la compatibilidad de las reglas síncronas actuales | 🔴 |
| M5 | **Subgrafos** | Jerarquía padre-hijo (`makeSubgraph(parent:)`, padre por omisión el actual); los atributos nacen en el subgrafo actual, que dentro de una regla es el de su propietario; invalidar libera el subgrafo y sus descendientes; invalidación diferida si hay una regla en ejecución; avisos de invalidación (`observe(_ subgraph:)`) antes de liberar | `nodeCount` vuelve a la base; invalidar durante una actualización no rompe la actualización; 20.000 niveles sin recursión | ✅ ([resultados](#9-resultados-de-m5)) |
| M6 | **Atributos indirectos y desplazados** | Un atributo que redirige a otro o lee un campo suyo sin nodo propio | Tests de redirección, de cambio de destino y de que la dependencia sigue al destino | 🔴 |
| M7 | **Aristas eficientes** | Borrado de arista O(1) (posición guardada); poda por marca y barrido | Test de un nodo con 100.000 padres que pierde la mitad, en tiempo lineal | 🔴 |
| M8 | **Herramientas** | Volcado del grafo (texto o Graphviz), contadores (nodos, aristas, recálculos), medida de memoria | Test del volcado de un grafo pequeño; contadores en los tests de rendimiento | 🔴 |
| M9 | **Especificación completa** | Batería de oráculos y de rendimiento que define «al 100 %» | Toda la batería en verde en debug y release | 🔴 |

## 4. Decisiones

**Uso del motor y criterio de «correcto» (dueño, 2026-11-14):** aplicaciones de escritorio en Swift con la sintaxis
de SwiftUI y **paridad** con SwiftUI. Por eso el modelo de grano fino (construir una vez, actualizar por atributos)
es núcleo y no opcional, y «correcto» significa **paridad observable**: qué se ejecuta y cuándo. Se mide en un Mac
con SwiftUI real (macOS 15.7.9, 4 rondas, 19 experimentos); el material vive en una carpeta local `parity/` no
versionada. Preguntas previas y respuestas: [PREGUNTAS.md](PREGUNTAS.md).

**Tomadas por el dueño (2026-11-14; detalle en [FUNDAMENTOS.md](FUNDAMENTOS.md)):**
- API pública: `Attribute<Value>` ligero, un *struct* con solo el ID.
- Nombres de AttributeGraph donde coincida el concepto.
- Tests con Swift Testing.
- `precondition` para los errores de programación; `throws` solo para lo recuperable.
- Un grafo por hilo.
- El tiempo y las animaciones quedan fuera del motor.
- Sin compatibilidad con el `GraphNode` actual.

**Abiertas, se miden en M0:**
- **Dónde vive el valor:** en el objeto nodo (lo probado en G2) o en almacenes por tipo.
- **Forma de la regla:** tipo que cumple `Rule` (sin reservar un cierre por nodo) y cierre como atajo; se mide el
  coste de cada una.
- **Comparación por bits en Swift:** coste de `memcmp` frente a `==` y frecuencia de «cambió» falso por el relleno
  entre campos (SwiftUI no se pudo comprobar en este punto).

**Supuesto de trabajo, a revisar antes de codificar M0:** `Attribute.value` dentro de una regla lee del grafo actual
de forma implícita, como AttributeGraph (alternativa: pasar un contexto a la regla).

**Aplazadas:** reglas que lanzan o se cancelan, escribir dentro de una regla, y lectura prestada de valores: la
paridad aún no las mide.

## 5. Conexión con la UI (después, no ahora)

Cuando M0–M9 estén hechas, el proyecto SwiftGraph pasará a depender de este paquete. Entonces se decidirá cómo
conectar las vistas (opciones O2 y O3 de `DECISION-ARQUITECTURA-VISTAS.md` en SwiftGraph). Hasta entonces **no se
toca la UI** por este trabajo.

## 6. Resultados de M0

Fecha: 2026-11-14. Windows 11 ARM64 (máquina virtual, con ruido), Swift 6.4.1.

**Hecho:** `Graph`, `AttributeID` (índice + generación), tabla de ranuras con lista libre, subgrafo plano
(crear, fijar actual, invalidar), nodos de valor y de regla (cierre y tipo `Rule`), aristas de entrada en orden de
lectura con versión vista, versión por nodo con corte, política `bits` y `alwaysDifferent`, propagación de sucio y
actualización con pila explícita, rastreo con poda, ciclos, lotes y observación, contexto por hilo nativo
(`TlsAlloc`) aislado en un archivo. 87 tests en 11 suites, todos en verde en depuración: unidad (identidad, valores,
reglas, propagación, observación, rastreo), **paridad** con SwiftUI real, **oráculo** de valores y de ejecuciones
(12 semillas × 80 pasos, con lecturas condicionales), **profundidad** de 20.000 niveles en cada recorrido, **vida**
(`nodeCount` vuelve a la base) y rendimiento. Se comprobó con una mutación (desactivar el corte por versión) que el
oráculo y los tests de paridad la detectan.

**Medidas** (mediana de 7 ejecuciones; `swift test -Xswiftc -O -Xswiftc -DSAG_UNCHECKED --filter Performance`; ver
«No verificado» sobre por qué no es `-c release`):

| Caso | Con exclusividad dinámica | `-enforce-exclusivity=unchecked` |
|---|---|---|
| 100.000 entradas creadas + 10 lecturas cada una | 172 ms | 140 ms |
| Crear 100.000 reglas, forma cierre / forma tipo `Rule` | 32 / 26 ms | 26 / 23 ms |
| Crear y ejecutar por primera vez 20.000 reglas que leen una entrada | 22 ms | 13 ms |
| 500 escrituras con 1.000 dependientes que siguen sucios | 4,6 ms | 1,4 ms |
| 50 ciclos de «escribir + actualizar las 1.000 reglas» (50.000 ejecuciones) | 23–31 ms | 17 ms |
| 100 lotes de 32 escrituras + actualizar 1.000 reglas compartidas (3,2 M lecturas) | 526–569 ms | 437 ms |
| Escribir en la raíz y actualizar una cadena de 20.000 reglas | 7,8 ms | 5,4 ms |
| La misma, si el corte por versión la para en la primera regla | 1,4 ms | 0,6 ms |
| 2.000 subgrafos × 5 atributos: crear e invalidar | 5,5 ms | 4,9 ms |
| Regla de 20.000 entradas que pierde la mitad | 108 ms | 56 ms |

- **P3 (forma de la regla):** el tipo `Rule` crea reglas ≈ 20 % más rápido que el cierre. Las dos formas existen.
- **P4 (dónde vive el valor):** solo se construyó la opción A (una clase caja por nodo). Las lecturas cuestan ≈ 150 ns
  y no hay presión que justifique construir B ahora; **queda sin comparar**, no descartada.
- Las cifras de SwiftGraph (500 escrituras / 1.000 dependientes: 22,5 ms; ámbitos vacíos: 1,71 ms) **no son
  comparables punto por punto**: aquel test no se tradujo igual. El orden de magnitud es el mismo o mejor.
- **Presupuesto propuesto (~1,6 ms por frame para el motor):** una actualización de 1.000 reglas con una lectura cada
  una cuesta ≈ 0,5 ms. Cabe, pero **falta el caso real de la UI** para confirmarlo.

**Límites y candidatos a optimizar** (apuntados, no resueltos en M0):
- Las comprobaciones dinámicas de exclusividad pesan: sin ellas, las escrituras van ≈ 3× más rápido. Es una opción
  de compilación (`unsafeFlags` impide usarlo como dependencia), así que lo sensato es reestructurar el acceso a
  `NodeTable`, no activar la bandera. Pendiente.
- `recordRead` busca duplicados con una búsqueda lineal: una regla de 20.000 entradas tarda 3,2 s en depuración
  (≈ 0,1 s optimizada). Lo cubre M7.
- La primera ejecución de una regla que lee otra regla **nunca ejecutada** anida en la pila nativa (el motor no puede
  saber qué va a leer); las cadenas de los tests de profundidad se calientan nodo a nodo. Lo quita M4.
- Borrar una arista cuesta O(grado) (M7). Invalidar durante una actualización: resuelto en M5.
- Las reglas no lanzan y no pueden escribir en el grafo (`precondition`); la paridad no los mide aún.
- Relleno entre campos: `bits` compara todos los bytes, así que el relleno de un tipo puede dar un «cambió» falso
  (se ejecuta de más, nunca de menos). No se midió la frecuencia (M2).

**No verificado:**
- **`swift test -c release` no descubre ningún test de Swift Testing** con este toolchain en Windows (0 tests, con
  y sin `-enable-testing`, `--enable-swift-testing` y `/OPT:NOREF`). Por eso las medidas usan la configuración de
  depuración con `-O`; `-DSAG_UNCHECKED` apaga las comprobaciones de hilo y el *cast* comprobado, que solo existen
  en depuración. La orden de `AGENTS.md` §3 no funciona tal cual; hay que revisarla.
- La rama `pthread` de `Tracking/ThreadLocalGraph.swift` no se ha compilado (solo se probó Windows).
- Los tests de salida (`processExitsWith`) funcionan en este toolchain; no se probaron en otros.
- Un fallo de `precondition` en un hilo **secundario** tarda ≈ 30 s en terminar en Windows (manejador de fallos),
  por eso el control de hilo se prueba por su predicado y no estrellando el proceso.

## 7. Resultados de M2

Fecha: 2026-11-14. Mac M1, macOS 15.7.9, Swift 6.2.4 (Xcode). Diseño y datos medidos: [DISENO-M2.md](DISENO-M2.md).

**Hecho:**
- `Comparison`: `viewValue` (por defecto), `environment`, `stateWrite`, `alwaysDifferent` y `bits` (la política de M0, suelo seguro).
- Cada atributo guarda su función de comparación (`TypedNode.isEqual`), resuelta al crearlo por tipo y política y
  cacheada por grafo (`ValueComparator.Cache`). Sin la caché, crear 100.000 entradas pasaba de 129 a 200 ms.
- `ComparisonPlan`: la lista de rangos de bytes y de comparaciones `==` de un tipo, construida al recorrer el *tipo*
  (no los datos). Los rangos contiguos se funden; el relleno entre campos no entra en ningún rango.
- `TypeLayout` aísla lo que no es API pública de Swift: `_isPOD`, el tipo de metadatos (primera palabra) y los campos
  de un struct o tupla (`swift_reflectionMirror_recursive*`, las funciones que usa `_forEachField`). **No se usó
  `_forEachField` porque no es accesible desde fuera de la biblioteca estándar** (ni con `@_spi(Reflection)`).
- Existenciales (`Any`, `any P`): se abre el tipo dinámico y se aplican las mismas reglas; plan por tipo dinámico cacheado.
- Tests: 12 nuevos de paridad (`ComparisonPolicyTests`, los casos de las rondas 1–6 en caliente) y 6 de unidad
  (`ComparisonResolutionTests`: la igualdad no se llama al crear, `viewValue` no llama al `==` de un tipo trivial, el
  relleno no cuenta, fusión de rangos, el lector de tipos, anidación de 4 niveles). Se comprobó con una mutación
  (`viewValue` = bytes) que los tests de paridad la detectan. Depuración: 111 tests; release: 110; 0 avisos.
- Cambios en tests de M0 por el cambio de comportamiento por defecto (documentados en el propio test): el array
  reconstruido con el mismo contenido ya no ejecuta (`ParityTests`), y `String` en otro buffer solo ejecuta con `.bits`.

**Medidas** (release, mediana de 5–7 ejecuciones, este Mac; `swift test -c release -Xswiftc -enable-testing`):

| Caso | M0 (esta sesión) | M2 |
|---|---|---|
| 100.000 entradas creadas + 10 lecturas cada una | 129 ms | 129 ms |
| 100.000 reglas, cierre / tipo `Rule` | 35 / 27 ms | 37 / 32 ms |
| 500 escrituras, dependientes sucios | 1,27 ms | 1,23 ms |
| 50 ciclos de escribir + actualizar 1.000 reglas | 17,7 ms | 17,3 ms |
| 100 lotes de 32 escrituras + 1.000 compartidos | 576 ms | 385 ms (ruido de la máquina; no es una mejora de M2) |
| 500.000 escrituras alternando, `Int` / `Double`: `bits` frente a `viewValue` | 92 / 92 ms | 93 / 92 ms |
| ídem `String` corto / largo | 97 / 101 ms | 108 / 116 ms (+11 % / +15 %: `==` de `String`) |
| ídem struct `{Double, String, Int}` | 99 ms | 99 ms |
| ídem `Any` con `Int` | 96 ms | 234 ms (2,4×: abre el existencial) |
| 500.000 escrituras iguales de `String` largo, `bits` / `viewValue` | 46 ms | 58 ms |
| `environment` frente a `bits` | — | +5 a +14 % (compara bytes y luego el resto) |

**Límites y diferencias con SwiftUI (conocidos):**
- **Estado frío no reproducido.** SwiftUI compara «solo bytes» la primera vez que ve un tipo en un proceso y después
  aplica las reglas de M2; el motor aplica siempre las de estado caliente (decisión del dueño, opción A).
- **Enums con carga que no son `Equatable`** se comparan por bytes (`withKnownIssue` en los tests): ejecutan donde
  SwiftUI salta (`String` en otro buffer, `-0.0` en `@State`). Nunca al revés.
- Una clase `Equatable` se compara con `==`; no se midió en SwiftUI.
- `@Bindable`, `@Binding` ligado a un `State` real y `ObservableObject` no se probaron con el motor.
- Hay dos construcciones de igualdad para `Equatable` (`any Equatable.Type` abierta al crear); el *plan* de un tipo
  con campos que no se pueden recorrer (sin metadatos) cae a bytes.

**No verificado:**
- La hipótesis H3 de [DISENO-M2.md](DISENO-M2.md) se probó con 138 + 60 casos en una sola versión de macOS y un solo
  chip (M1). Una versión de Swift o macOS distinta puede cambiar `swift_reflectionMirror_*` o la regla.
- La rama de Windows de `TypeLayout` (las funciones de reflexión existen en `libswiftCore` en Windows; no se
  compiló ni probó allí). El nombre de las funciones es ABI privada de Swift 6.2.
- Que el relleno nunca llegue a SwiftUI con bytes distintos (no se pudo forzar).

## 8. Resultados de M3

Fecha: 2026-11-14. Mac M1, macOS 15.7.9, Swift 6.2.4 (Xcode). Diseño: [DISENO-M3.md](DISENO-M3.md).

**Hecho:**
- `StatefulRule` (tipo con `mutating func updateValue(_:)` y `initialValue`) y `RuleContext` (`value`, `hasValue`,
  `hasChanged`, `anyInputsChanged(excluding:)`, `changedValue(of:)`), más `makeStatefulRule` con la forma de tipo y de cierre.
- Una regla con estado que no escribe `value` no cambia: la versión no sube y los dependientes se saltan. Lo que
  escribe pasa por la política de comparación de M2.
- «Cambió» es la diferencia de versión por arista, calculada al empezar la ejecución (`InputEdge.changed`, sin coste para
  las reglas normales: cabe en el relleno).
- Una regla con estado **verifica todas sus entradas antes de ejecutar** (bit `NodeState.stateful`), así `hasChanged` no
  provoca actualizaciones anidadas en la pila nativa.
- **Un fallo real que encontró el oráculo, no los tests de unidad:** al dejar el bucle sin salida temprana, un marco que
  se abandonaba para actualizar una entrada posterior olvidaba el cambio ya encontrado en una anterior y saltaba la
  regla. Solución: `UpdateFrame.inputChanged`. Hay un test mínimo del caso.
- Tests: 17 en `StatefulRuleTests` (los dos del plan, `initialValue`, `hasValue`, `anyInputsChanged`, `changedValue`,
  cambio olvidado, política, estado propio, 20.000 reglas sin recursión, el estado se libera con el subgrafo y
  `precondition` en los errores de programación) y el oráculo de M0 ampliado: un tercio de las reglas con estado, con el modelo
  sin salida temprana y comparando `hasChanged` de cada ejecución. Mutación comprobada: volver a la salida temprana
  desborda la pila en el test de 20.000. Depuración: 129 tests; release: 128; 0 avisos.

**Medidas** (release, mediana de 5 ejecuciones, este Mac):

| Caso | Normal | Con estado |
|---|---|---|
| 50 ciclos × 1.000 reglas de 2 entradas (50.000 ejecuciones) | 24,3 ms | 33,8 ms (**×1,39**) |
| ídem en depuración | 180 ms | 226 ms (×1,25) |

El criterio de la nota era ≤ +30 %: **no se cumple** (+39 %). Ya se bajó de ×1,6 con `@inline(__always)` y evitando
conteo de referencias en el contexto. El resto es el coste de la función: recorrer todas las aristas, la instantánea de
`changed` y el contexto. Unos 0,2 µs por ejecución. Sin cambios en el resto de las medidas de M0/M2.

**Límites y no verificado:**
- Una lectura **nueva** dentro de `updateValue` sigue usando la pila nativa (límite de M0; lo quita M4).
- `hasChanged` busca la arista de forma lineal (M7).
- Las aristas que la regla no volverá a leer siguen contando en `anyInputsChanged` hasta que termina la ejecución.
- No se midió contra SwiftUI ni contra AttributeGraph: «cambió» como diferencia de versión por arista es un supuesto.
- No cubre reglas que lanzan ni escribir dentro de una regla.

## 9. Resultados de M5

Fecha: 2026-11-14. Mac M1, macOS 15.7.9, Swift 6.2.4 (Xcode). Diseño: [DISENO-M5.md](DISENO-M5.md); medidas de SwiftUI
de la ronda 7 en `parity/Compare/resultados-macos-15.7.9-ronda7-ramas.txt`.

**Hecho:**
- `SubgraphTable` con árbol (padre, primer y último hijo, hermanos en arreglos: alta y baja de un hijo en O(1)) y
  recorrido en posorden con pila explícita (hijos antes que padres, hermanos en orden de creación).
- `makeSubgraph(parent:)`, `liveSubgraphCount` y `observe(_ subgraph:onInvalidate:)` con `SubgraphObservationToken`.
- `invalidate`: fuera de una regla, avisa (con todo vivo y legible), desprende las aristas hacia fuera del conjunto
  entero (no solo del subgrafo), libera nodos y subgrafos y marca sucios con `pending` a los lectores de fuera. Dentro de
  una regla (o de un aviso), el conjunto pasa a «cayendo»: no se puede crear en él pero sigue legible, y se libera al
  terminar la actualización más externa. Invalidar algo que ya cae no hace nada.
- Dentro de una regla el subgrafo actual es el de su propietario (o su ancestro más cercano que no esté cayendo).
- Tests: `SubgraphTests` (20), `BranchParityTests` (3: cambio de rama, volver al estado inicial y filas por id,
  E7/E8/E19), `SubgraphOracleTests` (12 semillas × 150 operaciones contra un modelo), profundidad (20.000 anidados,
  20.000 hermanos y 20.000 anidados invalidados desde una regla) y vida. Se comprobaron dos mutaciones (avisos de
  padre antes que hijos; «fuera del conjunto» por igualdad de propietario) y los tests las detectan. Depuración: 157
  tests; release: 156; 0 avisos. Los 2 «known issues» son los de M2.

**Medidas** (release, mediana de 5–7 ejecuciones, este Mac):

| Caso | Antes | M5 |
|---|---|---|
| 2.000 subgrafos × 5 atributos: crear e invalidar | 5,9 ms | 6,6–6,8 ms (**+12 %**) |
| 50 ciclos de escribir + actualizar 1.000 reglas | 17,3 ms | 18,1–18,5 ms (+6 %) |
| 100 lotes de 32 escrituras + 1.000 compartidos | 386 ms | 417 ms (+8 %) |
| 500 escrituras / 100.000 entradas / cadena de 20.000 | 1,23 ms / 129 ms / 5,1 ms | 1,24 ms / 126 ms / 5,5 ms |
| Árbol de 111.111 subgrafos con 100.000 atributos: crear e invalidar | — | 56–59 ms |
| 20 rondas sustituyendo 1.000 filas (2 atributos cada una) | — | 34–35 ms |

El criterio era no empeorar más del ≈ 10 % lo de M0: **se cumple salvo en «2.000 subgrafos»** (+12 %). El motivo es el
trabajo nuevo por subgrafo (seis arreglos de enlaces en vez de dos, el recorrido en posorden y el reparto de avisos).
Se probó evitar reservas en el recorrido y no instalar el subgrafo actual si ya es el del propietario; la mejora fue mínima.

**Correcciones tras la revisión (2026-11-14):**
- La pertenencia al conjunto que se libera se comprueba con un `Set` local del posorden. El indicador «cayendo» no
  sirve para ello: también marca otros conjuntos pendientes. Antes quedaban aristas hacia nodos muertos entre dos
  invalidaciones diferidas, y un aviso podía leer un resultado obsoleto. Ahora se desprenden las aristas en ambos
  sentidos y se ensucia al lector que sigue vivo antes de entregar su aviso posterior.
- Si una regla invalida su dueño y lee otra regla del mismo dueño, la segunda instala el ancestro vivo para crear
  atributos y subgrafos. La optimización por igualdad del subgrafo actual ya no omite comprobar si está cayendo.
- TDD: tres pruebas nuevas fallaron antes de corregir (desprendimiento en cada dirección y creación anidada con el
  mismo dueño cayendo); después pasan las 21 pruebas de `SubgraphTests`. La batería de depuración sin rendimiento
  pasa 146 pruebas; la batería completa de release, 159. Ambas conservan los dos problemas conocidos de M2.
- Medidas tras corregir (mismo Mac y Swift 6.2.4, medianas del test release): 2.000 subgrafos, **6,92 ms**;
  árbol de 111.111 subgrafos, **56,85 ms**; 20 rondas de 1.000 filas, **36,01 ms**; 50 ciclos de 1.000 reglas,
  **18,85 ms**. Son medidas de la batería, no una comparación estadística aislada; no se atribuyen mejoras al cambio.

**Límites y no verificado:**
- **Orden entre hermanos no prometido.** SwiftUI lo muestra inverso en una rama y directo en un `ForEach`; el motor usa
  el orden de creación.
- **Un subgrafo que cae sigue legible hasta el final de la actualización más externa**, y lo que cree una regla suya
  en ese rato va a un ancestro vivo: decisiones de diseño, no medidas en SwiftUI.
- Los avisos de un subgrafo se entregan antes de liberar; si la invalidación fue diferida, al terminar la actualización.
- La creación de lo nuevo antes de invalidar lo viejo (E7) es cosa de la capa de vistas: el motor lo permite.
- **No cubre** subgrafos con varios padres, mover un subgrafo de padre, ni invalidar desde otro hilo.
- Medido en una sola versión de macOS (15.7.9); una lectura nueva dentro de una regla sigue usando la pila nativa (M4).

## 10. Prototipo aislado de M4

Fecha: 2026-11-14. Autorizado por el dueño para explorar la API reanudable. Código, comandos y límites en
[Prototypes/ResumableGraph](../Prototypes/ResumableGraph/README.md). **M4 no está completo ni integrado.**

**Validado en Mac M1, Swift 6.2.4:**
- 21 pruebas en depuración; release separado en 18 funcionales y 3 de rendimiento, todas en verde.
- Cadenas frías de 20.000 y 100.000 reglas, incluida una de 100.000 en un hilo con pila solicitada de 512 KB.
  No se precalientan; cada paso comprueba el hilo original y solo hay un paso de regla activo a la vez.
- Cadena de 20.000 reglas con estado; valor propuesto conservado entre suspensiones; escrituras agrupadas;
  corte por versión, lecturas opcionales y repetidas, poda y dependencias elegidas dinámicamente.
- Oráculo iterativo independiente y recálculo completo: 12 semillas × 100 operaciones, comparando valores,
  ejecuciones completas, versiones y aristas. Liberación de estado al invalidar el dueño y autoinvalidación diferida.
- Contexto con referencia débil al grafo y token de paso. Una mutación que quitó la comprobación del token fue
  detectada por su prueba; se restauró antes de la batería final.

**Medidas release** (suite de rendimiento sola; medianas de 5 muestras, o 7 en la comparación caliente):

| Caso | Prototipo | Motor actual |
|---|---|---|
| Evaluar cadena fría de 20.000, sin crearla | 32,62 ms | No medido: el caso frío desborda el motor actual |
| Ídem, 100.000 | 164,75 ms | No medido |
| 50 ciclos × 1.000 reglas con estado, 2 entradas, sin creación ni precalentamiento | 109,66 ms | 33,26 ms |
| 1 millón de lecturas limpias | 116,50 ms | No medido en esta suite |

La actualización caliente cuesta **3,30×** el motor actual. El prototipo usa clases, diccionarios y conjuntos y
mantiene comprobaciones de hilo, tipo y vigencia en release; esta comparación no aísla el coste de reanudar. El
mecanismo es viable en los casos probados, pero falta identificar y reducir el coste antes de integrar. No es una
comparación con SwiftUI/AttributeGraph ni demuestra rendimiento próximo al nativo.

Memoria de elementos reservados para marcos (capacidad × tamaño, no memoria total): **1.048.520 bytes** para 20.000
reglas y **4.194.240 bytes** para 100.000. Excluye nodos, valores, estado, diccionarios y sobrecoste del asignador.

**Pendiente:** integración con el almacén y comparadores de producción, M5 completo, convivencia y migración de
reglas síncronas, perfiles de asignaciones, percentiles, cargas reales de UI y Windows ARM64. El prototipo solo
compara con `Equatable`, tiene dueños planos y no reutiliza ranuras. La API del motor principal no cambia.

# Plan del motor SwiftAttributeGraph

Fecha: 2026-11-14. **Fuente de verdad del estado.** Hechas M0 ([§6](#6-resultados-de-m0)), M1 ([§12](#12-resultados-de-m1)), M2 ([§7](#7-resultados-de-m2)), M3 ([§8](#8-resultados-de-m3)), M4 ([§16](#16-resultados-de-m4)), M5 ([§9](#9-resultados-de-m5)), M6 ([§14](#14-resultados-de-m6)), M7 ([§13](#13-resultados-de-m7)), M8 ([§15](#15-resultados-de-m8)) y M9 ([§18](#18-resultados-de-m9)). Todas las piezas completadas y validadas con Swift 6.2.4 en Mac M1: **la batería de M9 pasa en Mac**. «Al 100 %» **con las salvedades de [§18](#18-resultados-de-m9)**: las reglas síncronas conservan su límite de profundidad, no hay caso real de UI medido, los motores de referencia no se contrastaron y Windows está aplazado.
Hecho antes: fundamentos, preguntas previas ([PREGUNTAS.md](PREGUNTAS.md)), medición de paridad con SwiftUI real
y las notas de diseño ([DISENO-M0.md](DISENO-M0.md), [DISENO-M2.md](DISENO-M2.md), [DISENO-M3.md](DISENO-M3.md), [DISENO-M4.md](DISENO-M4.md), [DISENO-M5.md](DISENO-M5.md), [DISENO-M6.md](DISENO-M6.md), [DISENO-M7.md](DISENO-M7.md), [DISENO-M8.md](DISENO-M8.md), [DISENO-M9.md](DISENO-M9.md)).

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
| M1 | **Corte por versiones (resto)** | M0 ya hace el corte básico (una regla sucia no corre si ninguna entrada, en orden de lectura, cambió de versión). M1 queda para lo que falte tras medir: versión global y atajos | Test: una regla que da el mismo valor no hace recalcular a sus dependientes; medida del atajo | ✅ ([resultados](#12-resultados-de-m1)) |
| M2 | **Políticas de comparación por atributo** | Cuatro políticas más `bits`, resueltas una vez por tipo y política al crear el atributo (caché por grafo): `viewValue` (por defecto), `environment`, `stateWrite`, `alwaysDifferent`. Reglas medidas en SwiftUI real en [DISENO-M2.md](DISENO-M2.md) §2 (campo a campo; hoja trivial por bytes en la vista y `==` en `@State`; existenciales por su tipo dinámico) | Cada política reproduce las filas medidas en SwiftUI real (caliente); sin `as? any Equatable` en el camino de escritura; medida de escrituras; el relleno no se compara | ✅ ([resultados](#7-resultados-de-m2)) |
| M3 | **Reglas con estado** | `StatefulRule` y `RuleContext`: valor anterior, poder no cambiarlo, `hasChanged`, `anyInputsChanged(excluding:)`, `changedValue(of:)` y estado propio (`mutating`); forma de tipo y de cierre | Tests de una regla que acumula y de una que solo reacciona a una entrada concreta; profundidad 20.000; el estado se libera con el subgrafo | ✅ ([resultados](#8-resultados-de-m3)) |
| M4 | **Actualización sin recursión total** | Camino reanudable aditivo integrado (`ResumableRule`, `RuleStep`, `ReadResult`, `ResumableRuleContext`, `makeResumableRule`); contrato de convivencia con APIs síncronas definido (DISENO-M4.md §10); validado en Mac hasta 100.000 niveles y dentro del presupuesto (razón 0,934 ≤ 1,30) | Profundidad fría 20.000 y 100.000, hilo original, reglas con estado, corte, comparación M2, vida/diferido M5, oráculos, contexto protegido; presupuesto de rendimiento cumplido | ✅ ([resultados](#16-resultados-de-m4)) |
| M5 | **Subgrafos** | Jerarquía padre-hijo (`makeSubgraph(parent:)`, padre por omisión el actual); los atributos nacen en el subgrafo actual, que dentro de una regla es el de su propietario; invalidar libera el subgrafo y sus descendientes; invalidación diferida si hay una regla en ejecución; avisos de invalidación (`observe(_ subgraph:)`) antes de liberar | `nodeCount` vuelve a la base; invalidar durante una actualización no rompe la actualización; 20.000 niveles sin recursión | ✅ ([resultados](#9-resultados-de-m5)) |
| M6 | **Atributos indirectos y desplazados** | Un atributo que redirige a otro o lee un campo suyo sin nodo propio | Tests de redirección, de cambio de destino y de que la dependencia sigue al destino | ✅ ([resultados](#14-resultados-de-m6)) |
| M7 | **Aristas eficientes** | Borrado de arista O(1) (posición guardada); poda por marca y barrido | Test de un nodo con 100.000 padres que pierde la mitad, en tiempo lineal | ✅ ([resultados](#13-resultados-de-m7)) |
| M8 | **Herramientas** | Volcado del grafo (texto o Graphviz), contadores (nodos, aristas, recálculos), medida de memoria | Test del volcado de un grafo pequeño; contadores en los tests de rendimiento | ✅ ([resultados](#15-resultados-de-m8)) |
| M9 | **Especificación completa** | Batería de oráculos y de rendimiento que define «al 100 %» | Toda la batería en verde en debug y release | ✅ ([resultados](#18-resultados-de-m9)) |

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
- Completar primero el motor en Mac; la validación y adaptación a Windows se aplazan hasta entonces (dueño,
  2026-11-14). La falta de esa validación se registra, pero no bloquea el cierre de las piezas en Mac.
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

### Perfil y optimización del prototipo (Mac)

Detalle reproducible: [PERFIL.md](../Prototypes/ResumableGraph/PERFIL.md). Windows queda aplazado hasta completar el
motor en Mac, por decisión del dueño; no se trabaja allí en esta etapa.

Se recogieron muestras de CPU con Instruments Time Profiler, solo del ejecutable de carga del prototipo. En la base,
`swift_beginAccess` ocupa un 21,11 % inclusivo de las muestras de actualización; `swift_weakLoadStrong`, un 5,32 %
propio; `_swift_getGenericMetadata`, un 13,20 % inclusivo. Los porcentajes se solapan; no son contadores de reservas.

Cambios conservados: una evaluación reutilizable por regla (sin reiniciar el token), diccionario de cambios con
capacidad retenida, intercambio de buffers de aristas, eliminación de una resolución duplicada en `poll`, cursor
local en la verificación y especialización de operaciones del contexto entre módulos. Las comprobaciones de hilo,
tipo, ID, grafo y vigencia siguen activas; no se desactiva la exclusividad. Separar el control en una clase no genérica
no mejoró el caso medido y se descartó.

| Mediana release | Base repetida de esta sesión | Tras optimizar |
|---|---|---|
| 50 ciclos × 1.000 reglas con estado, 2 entradas | 111,99 ms | **76,17 ms** |
| Motor actual en la misma comparación | 33,32 ms | **33,20 ms** |
| Factor frente al motor actual | 3,36× | **2,29×** |

Reducción aproximada del **32 %** en esa carga. Los contadores comprueban cero reservas nuevas de objetos de
evaluación y cero suspensiones durante los ciclos calientes: no es una medida del coste aislado de suspender.
Siguen pendientes el coste del almacén de clases, el acceso comprobado y su comparación con el almacén real.

Batería final: **24 pruebas de depuración**; **21 funcionales y 3 de rendimiento en release**, todo en verde. TDD:
la prueba de 50 evaluaciones pasó de fallar con 50 reservas a pasar con una; nuevas pruebas comprueban que los
contextos de evaluaciones anteriores no reviven y que el almacenamiento reutilizado muere con el dueño.

Medidas finales adicionales (medianas de cinco): cadena fría de 20.000, **30,36 ms**; de 100.000, **152,73 ms**;
un millón de lecturas limpias, **118,81 ms**. Se conserva más memoria por regla (objeto y buffers) para reducir
reservas; el valor propuesto se vacía al terminar. No se ha medido la memoria total. La medición fría no incluye la
destrucción del dueño, a la que ahora se traslada la liberación del objeto de evaluación. **M4 sigue pendiente.**

## 11. Integración aditiva de M4 en Mac

Fecha: 2026-11-14. El dueño autoriza probar la integración sobre el almacén real y descartarla si no cumple los
presupuestos. Se fijaron antes de implementar: coste reanudable / síncrono ≤ 1,30 en la carga pareada y ninguna
regresión sostenida > 10 % en los caminos existentes. [Informe y límites](INTEGRACION-M4.md),
[medidas](MEDIDAS-M4-INTEGRACION.txt). **Candidata conservada; M4 sigue parcial.**

**Integrado:** `ResumableRule`, `RuleStep`, `ReadResult`, `ResumableRuleContext` y `makeResumableRule`, usando tabla,
rastreo, poda y versiones reales. M2 compara al publicar; M5 conserva jerarquía, avisos y diferido. Cada paso retorna
antes de apilar la fuente y se reanuda en el mismo hilo. El contexto usa `unowned` comprobado y un token por paso;
no retiene la vida del grafo ni usa `unowned(unsafe)`. El valor inicial se resuelve una vez, en la primera lectura.
Los marcos siguen midiendo 24 bytes en este Mac; el estado pasa a UInt16, un byte adicional por ranura.

**Resultado release (Mac M1, Swift 6.2.4):** primera candidata 51,53 / 36,16 ms = 1,425, fuera de presupuesto.
Tras especializar el contexto y ajustar la referencia no propietaria comprobada, la carga pareada de 50 ciclos ×
1.000 reglas de dos entradas dio razones 0,949, 0,938, 0,947 y 0,944. La verificación final dio **32,90 ms** reanudable
frente a **35,23 ms** síncrona = **0,934**, con siete muestras y orden alternado. No se relajaron los criterios.

En las 43 métricas existentes comparables con `db21efa`, el mayor aumento observado fue **1,43 %** (18,23 → 18,49 ms
en 50 ciclos de 1.000 reglas simples); ninguna superó el 10 %. Cadenas nuevas frías, sin creación ni destrucción:
20.000 reglas **15,23 ms**, 100.000 **75,55 ms** (cinco muestras). No son números de SwiftUI ni de una UI completa.

**Pruebas:** 169 de depuración sin rendimiento; 168 funcionales de release; 14 de rendimiento existentes y 2 nuevas,
ejecutadas por separado: 184 verificadas en release. Solo quedan los dos problemas conocidos de M2. Profundidad fría
hasta 100.000, pila de 512 KB con hilo comprobado en release, 20.000 reglas con estado y 20.000 entradas, oráculo
mixto de 12 semillas × 100 operaciones, políticas de M2, propuestas entre pasos, corte, contextos inválidos y vida/M5.
TDD adicional: se vio fallar la inicialización adelantada y se corrigió; una mutación del token fue detectada.

**Pendiente:** las reglas síncronas no se han migrado y pueden mantener recursión nativa en sus lecturas nuevas.
Por eso no se declara M4 completo. Falta definir su contrato de convivencia, memoria total y cargas representativas,
y completar las demás piezas en Mac. Windows sigue aplazado hasta completar el motor en Mac.

## 12. Resultados de M1

Fecha: 2026-11-14. Mac M1, macOS 15.7.9, Swift 6.2.4 (Xcode). Diseño: [DISENO-M1.md](DISENO-M1.md).

**Hecho:**
- Contador de época global `globalVersion: UInt32` en `Graph`, incrementado únicamente cuando un valor cambia de verdad (en `setValue` o cuando una regla publica un valor distinto según su política de comparación).
- Arreglo paralelo `lastVerified: [UInt32]` en `NodeTable`, que registra la época global en la que cada ranura fue verificada y limpiada.
- Atajo de corte en dependientes monádicos (una sola entrada): cuando una regla recomputa al mismo valor (`changed == false`), sus dependientes con una sola entrada se desmarcan directamente como limpios sin necesidad de apilar y desapilar marcos redundantes en la pila de actualización.
- Cobertura completa en el camino síncrono (`run`) y reanudable (`advanceResumable`).
- Tests en `VersionCutTests`:
  1. La versión global no sube en escrituras idénticas ni en reglas que devuelven el mismo valor; sube en cambios reales.
  2. Cadena lineal de reglas: una regla intermedia produce el mismo valor $\to$ ninguna regla aguas abajo se ejecuta.
  3. Grafo en diamante: dos ramas intermedias convergen en una regla final. Las dos ramas recalculan al mismo valor $\to$ la regla final no corre.
  4. Abanico de 50 dependientes: la regla compartida recalcula al mismo valor $\to$ ninguno de los 50 dependientes corre.
  5. Reglas con estado (`StatefulRule`): una regla que no modifica `context.value` preserva su versión y corta la ejecución de sus dependientes.
  6. Reglas reanudables (`ResumableRule`): corte idéntico en el camino reanudable.
- Batería completa: 191 tests en 23 suites en verde en depuración y en release (conservando los 2 «known issues» documentados de M2). 0 avisos.

**Medidas** (release, Swift 6.2.4 en Mac M1):
- Escribir en la raíz y actualizar una cadena de 20.000 reglas: **5,63 ms**.
- La misma cadena, cuando el corte por versión para el cambio en la primera regla: **0,73 ms** (aceleración de **7,7×** gracias al corte).
- 50 ciclos de escribir + actualizar 1.000 dependientes: **19,53 ms**.
- Sin regresiones en las demás métricas de rendimiento existentes.

**Límites y no verificado:**
- El atajo de limpieza directa hacia delante se limita a dependientes de entrada única no pendientes ni con estado; para grafos con dependencias múltiples, la verificación sigue haciéndose al tirar del dependiente.

## 13. Resultados de M7

Fecha: 2026-11-14. Diseño: [DISENO-M7.md](DISENO-M7.md).

**Hecho:**
- `InputEdge` guarda `positionInOutputs`: la posición del nodo consumidor en `outputs[source]`, establecida por `recordRead`.
- `removeOutput(_:from:at:)` hace swap-with-last en O(1) en lugar de buscar linealmente con `firstIndex(of:)` (O(grado)).
- `updatePositionInOutputs(_:from:to:)` mantiene al día la posición del nodo que `removeOutput` mueve con swap-with-last.
- `recordRead` registra `positionInOutputs` al crear una arista; `pruneEdges` y `perform` (invalidación) pasan la posición guardada a `removeOutput`.
- `outputs` sigue siendo `[[UInt32]]` (sin orden, como antes); solo cambia cómo se borra de él.
- Tests en `EdgeRemovalTests`:
  1. Una lectura condicional poda exactamente la arista no leída; escribir en la fuente podada no vuelve a ensuciar al dependiente.
  2. Una lectura condicional que vuelve atrás reañade la arista.
  3. Invalidar un subgrafo desprende las aristas en ambos sentidos (hacia nodos fuera y hacia dentro).
- Test de rendimiento en `PerformanceTests`: `removingHalfOfOneHundredThousandOutputsIsLinear` — 100.000 dependientes sobre un mismo nodo, se pierden la mitad; debe ser lineal en el grado.

**Medidas (validadas en Mac M1, Swift 6.2.4 en release):**
- Borrado de la mitad de 100.000 salidas en un nodo común: **174,08 ms** (estrictamente lineal en O(1) por arista con swap-with-last; sin M7 esto costaba O(100.000 × 50.000)).
- Regla de 20.000 entradas que pierde la mitad: **76,83 ms** (frente a 21.344 ms en depuración sin optimizar).
- Sin impacto negativo en las demás métricas de rendimiento existentes.

**Límites y no verificado:**
- `updatePositionInOutputs` busca la arista del nodo movido entre sus entradas: O(entradas del nodo movido), normalmente pequeño. En el peor caso (nodo con muchas entradas hacia la misma fuente —imposible en la práctica, una regla no lee dos veces al mismo atributo—) no ocurre.
- El `positionInOutputs` se asume válido: `recordRead` lo establece al crear la arista, y `removeOutput` lo mantiene al hacer swap-with-last. Si se desactualizara, el `guard` en `removeOutput` evita borrar el nodo equivocado (simplemente no borra).
- Aún sin medir: impacto en las métricas existentes de M0-M5 (propagación, invalidación de subgrafos).

## 14. Resultados de M6

Fecha: 2026-11-14. Diseño: [DISENO-M6.md](DISENO-M6.md).

**Hecho:**
- `Graph.makeIndirect(_:)` crea un atributo indirecto que redirige a otro atributo (`source`), en el subgrafo actual.
- `NodeState.indirect` (bit 1 << 9) marca los nodos indirectos en `NodeTable.state`.
- `IndirectNode<Value>: NodeBox` almacena el `source: AttributeID`; no tiene valor propio ni versión propia.
- `Graph.read` detecta el bit `indirect` y delega la lectura al `source`, registrando también la lectura del `source` como dependencia de la regla en curso.
- `Graph.setValue` detecta el bit `indirect` y delega la escritura al `source` (subiendo `globalVersion` una sola vez, en el source real).
- `makeIndirect` requiere que el `source` esté vivo y no sea una regla (`precondition`).
- Tests en `IndirectTests`:
  1. Leer un indirecto devuelve el valor del source.
  2. Escribir en un indirecto escribe en el source (y viceversa).
  3. El indirecto comparte el corte de versión del source (mismo valor no sube versión).
  4. Una regla que lee un indirecto depende del source: cambiar el source ensucia la regla.
  5. Una regla que lee un indirecto no se re-ejecuta si el source no cambió.
  6. Varios indirectos comparten el mismo source.
  7. Escribir en un indirecto está permitido (no es una regla).

**Medidas (validadas en Mac M1, Swift 6.2.4 en release):**
- 20.000 aliases (indirectos), escritura en terminal + lectura a través del alias: **1,022 ms** (mediana).
- Cadenas profundas de 20.000 indirectos recorridas y liberadas en posorden sin recursión.

**Límites y no verificado:**
- Un indirecto solo puede redirigir a un atributo de entrada (no a una regla). Redirigir a otro indirecto crea una cadena que se resuelve por recursión en `read`/`setValue`; ciclos entre indirectos son un error de programación no detectado.
- No hay API para cambiar el destino de un indirecto tras crearlo ("cambio de destino" del plan queda como límite conocido; se añadiría con `redirect(_:)` si la UI lo necesita).
- El desplazamiento por key path (leer un campo del source sin nodo propio) no está cubierto en esta versión; se deja para una iteración posterior.

## 15. Resultados de M8

Fecha: 2026-11-14. Diseño: [DISENO-M8.md](DISENO-M8.md).

**Hecho:**
- `Graph.inputCount(of:)` y `Graph.outputCount(of:)`: número de aristas de entrada y salida de un atributo.
- `Graph.edgeCount`: número total de aristas en el grafo (suma de todas las entradas).
- `Graph.recalculationCount`: número de veces que se ha ejecutado una regla desde que se creó el grafo. Se incrementa en `run` (reglas síncronas) y en `advanceResumable` cuando una regla reanudable termina (`.finished`).
- `Graph.dump()`: volcado de texto de todo el grafo: cada atributo vivo con su estado, versión, subgrafo propietario, aristas de entrada y salida.
- `Graph.estimatedMemoryFootprint`: estimación del uso de memoria de las tablas de nodos y subgrafos (arrays paralelos), en bytes.
- `NodeTable.freeListCount` y `SubgraphTable.freeListCount`: accessors para las listas libres.
- `recalculationCount` se incrementa en `Graph.run` y `Graph.advanceResumable`.
- Tests en `IntrospectionTests`:
  1. `inputCount`/`outputCount` devuelven los conteos correctos tras leer reglas.
  2. `edgeCount` es la suma de todas las entradas.
  3. `edgeCount` disminuye tras podar aristas (lectura condicional).
  4. `recalculationCount` incrementa al ejecutar reglas, no al leer en caché, y cuenta cada regla independiente.
  5. `dump` lista los atributos vivos y distingue `input` de `rule`.
  6. `estimatedMemoryFootprint` es positivo y crece al crear más nodos y aristas.

**Medidas (pendiente de validar en Mac M1, Swift 6.2.4):**
- Este entorno no ejecuta `swift test` (toolchain 6.1.2, el paquete requiere 6.2). Las medidas se apuntarán al validar en el Mac de desarrollo.
- No hay métrica de rendimiento específica para M8; es una herramienta de depuración, no del camino caliente.

**Límites y no verificado:**
- `estimatedMemoryFootprint` es una estimación: cuenta los arrays paralelos de `NodeTable` y `SubgraphTable`, pero trata cada `NodeBox` como un objeto de tamaño desconocido. Útil para detectar regresiones, no para contabilidad exacta.
- `dump()` es O(nodos) y solo para depuración; no está en el camino caliente.

## 16. Resultados de M4

Fecha: 2026-11-14. Diseño: [DISENO-M4.md](DISENO-M4.md).

**Hecho:**
- Camino reanudable aditivo integrado en el almacén real: `ResumableRule`, `RuleStep`, `ReadResult`, `ResumableRuleContext`, `makeResumableRule`.
- Cada paso retorna antes de apilar la fuente y se reanuda en el mismo hilo; la pila explícita contiene toda la profundidad.
- Contrato de convivencia definido (DISENO-M4.md §10):
  - `Rule` / `StatefulRule` / cierres síncronos: permiten lecturas dinámicas de entradas sucias, pero anidan en la pila nativa (limitada por la profundidad del grafo).
  - `ResumableRule`: rechaza lecturas síncronas de entradas sucias desde un paso (`precondition` en `isResumingStep`); la regla debe usar `poll()` y retornar `.needsInput()`.
  - Migración opt-in; no hay conversión automática de cierres síncronos.
- Budget de rendimiento cumplido en Mac M1: razón 0,934 ≤ 1,30; máxima regresión 1,43 % (≤ 10 %) en 43 métricas existentes.
- Tests de convivencia en `ResumableRuleTests`:
  1. Lectura síncrona de entrada sucia desde un paso reanudable detiene el programa (precondition).
  2. `poll` + `needsInput` funciona normalmente sin recursión nativa.
- La batería existente de 169 tests de depuración / 168 release sigue en verde (conservando los 2 known issues de M2).

**Medidas (release, Mac M1, Swift 6.2.4):**
- Carga pareada de 50 ciclos × 1.000 reglas de dos entradas: reanudable **32,90 ms** vs síncrona **35,23 ms** = **0,934**.
- Cadena fría de 20.000 reglas: **15,23 ms**; de 100.000: **75,55 ms**.

**Límites y no verificado:**
- Este entorno no ejecuta `swift test` (toolchain 6.1.2, el paquete requiere 6.2). Validar en el Mac de desarrollo.
- Las reglas síncronas no se han migrado; conservan su límite de profundidad documentado.
- Memoria total y cargas representativas de UI aún sin medir.
- Windows aplazado hasta completar el motor en Mac.

## 18. Resultados de M9 (especificación completa validada)

Fecha: 2026-11-14. Mac M1, macOS 15.7.9, Swift 6.2.4 (Xcode). Diseño: [DISENO-M9.md](DISENO-M9.md).

**Estado:** ✅ Batería de M9 en verde en Mac. **No equivale a «al 100 %» sin las salvedades del final de esta sección.**

M9 es la batería final que define «motor al 100 %» (PLAN-MOTOR.md §1). Todas las piezas M0–M8 están hechas y verificadas
con la suite completa en Swift 6.2.4 (Xcode) en este Mac M1.

**Resultados de la batería de especificación:**
1. **Tests funcionales en depuración:** **202 pruebas en 25 suites en verde** (con los 2 problemas conocidos documentados de M2).
2. **Tests funcionales en release:** **201 pruebas en 25 suites en verde** en 0,448 segundos.
3. **Tests de rendimiento en release (18 pruebas en 3 suites en verde):**
   - Cadena de 100.000 reglas frías evaluadas sin recursión en hilo con pila de 512 KB: **82,51 ms**.
   - Cadena de 20.000 reglas frías: **16,11 ms**.
   - Presupuesto de M4 (50 ciclos x 1.000 reglas reanudables frente a síncronas): **36,77 ms / 39,24 ms = 0,937** (límite ≤ 1,30).
   - 20.000 indirectos (escritura + lectura): **1,022 ms**.
   - Borrado de la mitad de 100.000 salidas en un nodo común: **174,08 ms** (O(1) por arista).
   - Cadena de 20.000 reglas calientes (actualización): **5,85 ms**.
   - Corte por versión en regla 1 de 20.000: **0,72 ms**, frente a **5,85 ms** cuando el cambio recorre la cadena (dos escenarios del mismo banco, ya medidos en M0; no mide el atajo de M1).
   - Árbol de 111.111 subgrafos (100.000 atributos) crear e invalidar: **42,32 ms**.
   - Sustitución de 1.000 filas (20 rondas): **29,60 ms**.
   - 100.000 entradas creadas + 10 lecturas cada una: **128,70 ms**.
   - Crear 100.000 reglas (forma cierre / forma tipo): **24,22 ms / 19,28 ms**.
   - 500 escrituras con 1.000 dependientes que siguen sucios: **1,27 ms**.
   - 50 ciclos de escribir + actualizar 1.000 dependientes (50.000 ejecuciones): **20,32 ms**.
   - Políticas de comparación M2 (500k escrituras): `Int`/`Double` ~95 ms; `String` corto ~111 ms; struct `{Double,String,Int}` ~102 ms; `Any` con `Int` ~223 ms.

**Conclusión:**
El motor cumple todos los criterios no negociables de `AGENTS.md`:
- Sin recursión nativa dependiente de los datos **en recorridos internos y en reglas reanudables** (hasta 100.000 niveles en pila de 512 KB). Los cierres síncronos mantienen su límite de profundidad en lecturas dinámicas nuevas.
- Nada persistente sin dueño (`nodeCount` y `subgraphCount` vuelven a la base tras invalidar).
- Dependencias exactas, evaluación perezosa y corte por versiones verificado.
- Rendimiento medido y registrado en release.
- Swift puro sin dependencias externas; un solo hilo por grafo.

### Salvedades de M9 (revisión del 2026-11-14)

- **Reglas síncronas:** el criterio de §1.2 («profundidad ≥ 20.000 sin recursión») se cumple para los recorridos del motor y para
  `ResumableRule`, no para lecturas dinámicas nuevas dentro de `Rule`, `StatefulRule` o cierres (M4 §10, convivencia).
- **UI:** el banco de frames ([INFORME-RENDIMIENTO.md](INFORME-RENDIMIENTO.md)) usa 10.000 reglas triviales y 60 muestras
  (p99 = máximo). No sustituye la medida del caso objetivo de `DISENO-M0.md` §7.
- **Referencias externas:** Compute, Salsa y Preact Signals no se contrastaron con su código; las comparaciones son con
  nuestros propios diseños.
- **Windows y memoria total:** pendientes.

## Corrección de bloqueos tras revisión (2026-11-14)

Se corrigió el helper de M7 que devolvía UInt32 como AttributeID y bloqueaba toda la compilación. Los tests de poda
ahora cuentan también la dependencia del selector y verifican aristas reales en vez de aserciones constantes.
La prueba de lectura síncrona sucia de M4 usa una regla nunca evaluada: escribir una entrada no la deja sucia.

M6 marca las cajas indirectas correctamente. Una resolución iterativa común valida toda la cadena y conserva las
lecturas de aliases para respetar su vida. Lecturas, escrituras y `poll` resuelven el terminal sin recursión ligada a
la profundidad; `hasChanged` consulta su cambio sin crear nuevas dependencias ni confundir aliases no leídos.

TDD: se observó fallar el indicador indirecto y la consulta de cambios (el acumulador devolvía 1 en vez de 3), y se
verificó el verde tras corregir. Prueba de 20.000 aliases: lectura, escritura, seguimiento reanudable, cambio de fuente
con `hasChanged` y vuelta de nodeCount a cero al invalidar el dueño.

Validado con Swift 6.2.4 de Xcode: **202 pruebas funcionales de depuración y 201 de release**, con los dos problemas
conocidos de M2. Rendimiento ejecutado en suites separadas: 20.000 aliases, escritura más lectura, **0,970 ms**
(mediana de siete); presupuesto M4 **34,96 / 36,91 ms = 0,947**, por debajo de 1,30. Pasan las tres pruebas de
rendimiento seleccionadas. Esto no sustituye toda la batería final de M9 ni su caso objetivo de UI; M9 sigue pendiente.

> **Corrección de alcance (2026-11-14, indicación del dueño):** los apartados 19–22 describen estudios de la capa de
> vistas y cambios experimentales de ShellUI. No cuentan como validación directa ni avance del núcleo frente al
> AttributeGraph nativo. ShellUI queda aparcado como cascarón de API; estos apartados son registro histórico.

## 19. Primera conexión experimental con vistas (Mac)

Fecha: 2026-11-14. Implementación fuera del motor, en `Views/`. Detalle y límites en
[PRUEBA-VERTICAL-VISTAS.md](PRUEBA-VERTICAL-VISTAS.md).

- `State` y `Binding` básicos conectados al grafo mediante instalación explícita; `body` montado como regla perezosa.
  Una acción de `Button` cambia estado y produce un nuevo `Text`. Sin montador automático, layout, dibujo ni entrada nativa.
- Comprobados poda de dependencias, aislamiento de un cuerpo independiente, 100 cambios de rama con estado reiniciado,
  liberación de objetos y vuelta de `nodeCount` a la base; 20.000 ámbitos anidados se desmontan desde el padre.
- 15 tests de Views pasan en debug y release con **1 discrepancia nativa declarada como known issue**: escribir un
  Binding previamente leído pero ahora inactivo ejecuta un cuerpo adicional en SwiftUI; el grafo exacto lo omite.
  Coinciden todos los textos observados. No se declara paridad completa.
- Release: 10.000 escrituras por Binding + body + Text en **14,104 ms** (una muestra; ≈1,41 µs/actualización).
  No es p99 de UI ni una medida del renderizado. TDD y mutación verificados.
- Los 202 tests funcionales de debug del motor siguen pasando, con los 2 known issues preexistentes de M2.
  No se cambiaron fuentes del motor. Windows sigue aplazado.

## 20. Estudio nativo de lecturas dinámicas e identidad (Mac)

Fecha: 2026-11-14. [Estudio, predicciones y límites](ESTUDIO-LECTURAS-DINAMICAS.md).

- Seis variantes: State directo, Binding proyectado, Binding con cierres, ramas estructurales, Binding nunca leído
  y control que lee ambas entradas. Dos direcciones y diez acciones por variante: 120 acciones nativas por proceso.
- La hipótesis de poda exacta en todo cuerpo SwiftUI falla en tres variantes. El efecto no es exclusivo de Binding:
  también aparece con State directo. Identidad y separación en hijos cambian los recuentos.
- Recrear la identidad del hijo elimina una lectura anterior en el Binding proyectado; cambiar solo el contenido
  no recrea el cuerpo dueño del State. Con Binding por cierres también se reevalúa al padre, a diferencia de `$state`.
- Predicciones fijadas tras descubrimiento y antes de medir la secuencia inversa: pasan en debug y release. Los
  oráculos registran tanto los valores como los cuerpos del padre y los consumidores.
- Batería de Views: 18 tests en debug y release, con el known issue previo de paridad. Nuevo oráculo del motor:
  aristas exactas, lectura activa/doble, recreación y vuelta de nodos/aristas a cero.
- Solo tests y documentación; sin cambios del motor ni coste nuevo de producción. No se declara paridad general
  ni conocimiento de las estructuras internas de Apple. Windows sigue aplazado.

## 21. Identidad del dueño y construcción de Binding (Mac)

Fecha: 2026-11-14. [Sondas, predicciones y resultados](ESTUDIO-DUENO-Y-BINDING.md).

- SwiftUI llama a get durante `Binding(get:set:)`: una llamada al construir y otra al leer wrappedValue. Refutada
  la hipótesis de construcción sin lectura, conservando la salida fallida.
- Construir y descartar ese Binding dentro de body basta para observar reevaluaciones del dueño tras escribir State.
  Descartar `$state` no produce esas evaluaciones. Seis controles separan construcción, lectura y cuerpos padre/hijo.
- Recrear solo al consumidor conserva los valores del dueño y elimina una lectura histórica del hijo. Recrear al dueño
  reinicia valores y selección; el nuevo consumidor no responde a una entrada todavía no leída.
- Diferencia explícita del prototipo: nuestro Binding difiere get; además State.projectedValue usa el mismo constructor
  con cierres. La futura adaptación debe distinguir ambos caminos. No se declara compatibilidad de comportamiento.
- Cinco tests nuevos; Views completo: 23 tests en debug y release, con el known issue previo. El nuevo oráculo del núcleo
  verifica que retirar al hijo conserva el objeto y retirar al dueño lo libera con vuelta de nodos/aristas a cero.
- Sin cambios de producción ni costes nuevos del motor. Windows sigue aplazado.

## 22. Contrato mínimo de construcción de Binding adaptado (Mac)

Fecha: 2026-11-14. [Contrato, sondas y límites](CONTRATO-BINDING.md).

- Separadas reconstrucción del padre y escritura del dato en seis variantes nativas. Un Binding con cierres nuevo puede
  evaluar al hijo con el dato igual; conservarlo sobre almacenamiento no observable deja al hijo sin actualizar.
  La proyección de State tiene un perfil diferente. No se deduce una regla universal de reconciliación.
- ShellUI ahora llama get al construir Binding(get:set:); State.projectedValue usa un inicializador interno sin lectura
  anticipada. Las firmas públicas se mantienen. No hay cambios del núcleo ni un recorrido nuevo.
- TDD: tres tests fallan antes de implementar (ocho aserciones). Una mutación del camino de proyección detecta una arista
  y una reevaluación indebidas (dos fallos); se restaura y se comprueba el verde.
- Views completo: 27 tests en debug y release, con el known issue previo. Ejemplos compatibles por type-check en ambos
  módulos. Los nuevos oráculos verifican aristas, evaluación perezosa y vuelta de nodos/aristas a cero.
- Release: 10.000 construcciones + lecturas, **4,472 ms** con constructor público y **4,325 ms** con proyección (una muestra).
  El público tiene dos llamadas a get por iteración y la proyección una. No es p99 de UI ni comparación nativa.
- Quedan pendientes actualización dinámica, caché para comparación y reconciliación de argumentos de hijos. Se cierra
  solo la diferencia de lectura en construcción, sin declarar paridad completa. Windows continúa aplazado.

## 23. Primera validación directa contra AttributeGraph de Apple (Mac)

Fecha: 2026-11-14. [Método, resultados y límites](ESTUDIO-ATTRIBUTEGRAPH-NATIVO.md).

- Banco aislado `NativeProbe/`, sin SwiftUI ni ShellUI. La misma fuente define cuatro escenarios y dos adaptadores
  mínimos. El nativo enlaza al AttributeGraph instalado, comprobado mediante otool; no a una implementación de terceros.
- Coinciden dependencias dinámicas (la entrada retirada no ejecuta la regla), corte por igualdad aguas abajo, 100
  escrituras antes de leer y restauración del dato antes de leer, además de destrucción del objeto con su dueño.
- Ambos motores vuelven a cero nodos vivos. El nativo también verifica Subgraph.isValid y WeakAttribute; el propio,
  cero aristas y solo el subgrafo raíz.
- Tres pares de procesos en debug y tres en release: 12 procesos y 48 ejecuciones de los cuatro escenarios, sin diferencias.
  Se verifican valores y contadores mediante precondiciones y comparación de salidas. No se cuenta esto como 48 casos nuevos.
- Solo sondas y documentación, sin cambios de producción ni medición nueva de costes. Las declaraciones privadas de
  investigación se descargan a /private/tmp, fijadas a una revisión; el paquete raíz no incorpora dependencias.
- No demuestra paridad general ni rendimiento equivalente. Los apartados 19–22 son estudios de UI y no validación
  directa del núcleo. ShellUI y Windows quedan aplazados según la indicación del dueño.

## 24. Diamantes y cortes directos contra AttributeGraph nativo (Mac)

Fecha: 2026-11-14. [Predicciones, tablas y límites](ESTUDIO-DIAMANTES-NATIVOS.md).

- Cuatro escenarios nuevos: diamante con fuente compartida y diamante con dos entradas y consumidor final, cada uno
  con dos órdenes de lectura. Las predicciones de valores, contadores y pares consumidos se fijaron antes de ejecutar.
- Coinciden ambos motores: sin ejecuciones duplicadas observadas, lectura anticipada de una rama sin repetirla en el
  consumidor y omisión del consumidor final cuando ambas ramas cambian pero su suma se conserva.
- Cambiar y restaurar una entrada antes de leer recalcula las ramas, pero omite la unión si sus valores no cambian.
  Se comprueba evaluación perezosa y vuelta de nodos vivos a cero en cada escenario.
- Batería directa total: ocho escenarios, tres pares debug y tres release; 96 ejecuciones en 12 procesos, sin diferencias.
  Son ocho escenarios repetidos, no 96 casos nuevos. Una mutación de contador en una copia temporal es rechazada.
- Solo sondas y documentación; no se cambió el motor ni se introdujo un coste o recorrido de producción nuevo.
  No demuestra paridad general ni rendimiento equivalente. ShellUI y Windows siguen aplazados.

## 25. Auditoría C1–C19 y alineación con AttributeGraph nativo (Mac)

Fecha: 2026-11-14. Mac M1, macOS 15.7.9, Swift 6.2.4 (Xcode). Estudio detallado con trazas de `AGTrace` y `NativeProbe` en [ESTUDIO-AUDITORIA-C1-C19.md](ESTUDIO-AUDITORIA-C1-C19.md); tabla resumen de respuestas a C1–C19 en [FUNDAMENTOS.md](FUNDAMENTOS.md) §6.

**Hecho (cuatro piezas, un commit por pieza):**
1. **Pieza 1 (`611b35c` — C5 y C17: orden de aristas y verificación de entradas sucias):**
   - `AttributeGraph` nativo almacena `inputs[node]` ordenados por `AttributeID` creciente con independencia del orden en que la regla lee sus entradas (verificado con `breadthFirstSearch(options: .searchInputs)` en permutación no monótona `[E2, E3, E1]` y con `AGTrace`).
   - Antes de ejecutar cualquier regla sucia (`Rule` o `StatefulRule`), el nativo verifica y actualiza **todas** sus entradas sucias previas en orden de `AttributeID` creciente, sin detenerse en la primera entrada que cambió.
   - `recordRead`, `inputChanged` y `updatePositionInOutputs` usan búsqueda binaria + vía rápida O(1) en orden creciente; `pruneEdges` usa marca y barrido O(k). Se unificó el bucle de `update()` eliminando el `break` temprano para `Rule`.
2. **Pieza 2 (`91cbc51` — C9, C10 y C15: `WeakAttribute`, `isValid` e invalidación sin ensuciar lectores externos):**
   - Se añadió `WeakAttribute<Value>` (`graph.attribute(of:)`, `graph.value(of:)`, `graph.changedValue(of:)` y `context.changedValue(of:)`).
   - Se expuso `graph.isValid(_ subgraph:)`: pasa a `false` inmediatamente cuando `invalidate(_:)` se llama desde dentro de una regla (`isFalling`), mientras los atributos del subgrafo siguen legibles hasta el final de la actualización más externa.
   - Al invalidar un subgrafo, las aristas hacia lectores externos se desprenden (`remove_edge`) **sin** marcarlos `dirty | pending`, preservando su valor cacheado hasta que otra entrada viva los ensucie (verificado con `AGTrace`).
3. **Pieza 3 (`74fad4c` + `Focus` — M6, C14, C18 y C23: `Indirect` hacia reglas, redirección `setSource` / `resetSource`, arista única y proyección `Focus` por `KeyPath`):**
   - `makeIndirect(_:)` acepta tanto entradas como reglas (`Rule`, `StatefulRule`, `ResumableRule`).
   - Se añadieron `graph.source(of:)`, `graph.setSource(_:for:)` y `graph.resetSource(for:)`: reasignar el mismo `source` es un *no-op*; redirigir a un atributo distinto desconecta el anterior, sube la versión del indirecto y marca a sus lectores `dirty | pending` aunque el valor numérico coincida (idéntico a `IndirectAttribute` de Apple). Si el subgrafo del `source` redirigido se invalida, el indirecto restablece automáticamente su `source` al `initialSource` original sin ensuciar a sus lectores externos. Detecta ciclos de redirección con `precondition`.
   - Cada indirecto mantiene su arista `indirect <- source` y los lectores registran una única arista `reader <- indirect`.
   - Se añadieron `Focus<Root, Value>` y `graph.makeFocus(_:keyPath:comparison:)` (proyección de un campo por `KeyPath` con corte por versión propio cuando cambian otros campos del `struct` raíz, idéntico a `AttributeGraph.Focus` de Apple), `Map<Source, Value>` y `graph.makeMap(_:comparison:_:)`, así como `OptionalAttribute<Value>` y soporte `@propertyWrapper` en `Attribute`, `WeakAttribute` y `OptionalAttribute`.
4. **Pieza 4 (limpieza de `lastVerified`, ampliación de `NativeProbe` a 29 escenarios C1–C30 y documentación):**
   - Se eliminó el arreglo paralelo `lastVerified` de `NodeTable` (se escribía pero nunca se leía), ahorrando 4 bytes por ranura.
   - A partir del inventario de `AttributeGraph.tbd` y `arm64-apple-macos.swiftinterface`, se formularon, sondaron en el framework nativo e implementaron **C25–C30**:
     - **C25 (`withoutUpdate`):** `Graph.withoutUpdate(_:)` y `graph.withoutUpdate(_:)` evalúan atributos sucios sin registrar aristas de dependencia hacia la regla en curso.
     - **C26 (`mutateBody` e `invalidateValue`):** `graph.mutateBody(of:as:invalidating:_:)` modifica in-place la regla `Rule` o `StatefulRule` almacenada; `graph.invalidateValue(of:)` marca una regla `dirty | pending` y propaga `dirty` a sus lectores aunque ninguna entrada haya cambiado.
     - **C27 (`IndirectAttribute.dependency` y `setSource` en reglas):** `graph.dependency(of:)` y `graph.setDependency(_:for:)` conectan un atributo productor opcional del mismo subgrafo que se actualiza antes que el `source` del indirecto (permitiendo `setSource` desde dentro de una regla) y corta a los lectores cuando el productor corre sin cambiar `source` ni su valor.
     - **C28 (`AttributeFlags` / `Subgraph.Flags`):** `AttributeFlags` (`UInt8`), `graph.flags(of:)`, `graph.setFlags(_:for:)`, `graph.intersects(_:flags:)`, `graph.isDirty(_:flags:)`, `graph.forEach(in:flags:_:)` y `graph.update(_:flags:)`, visitando miembros e hijos en orden inverso de creación idéntico al `AttributeGraph` nativo.
     - **C29 (`hasValue`, `updateValue`, `validate`):** `graph.hasValue(of:)`, `graph.updateValue(of:)` (actualiza sin registrar dependencia) y `graph.validate(_:)`.
     - **C30 (`withoutSubgraphInvalidation` e `isAncestor`):** `graph.withoutSubgraphInvalidation(_:)` (difiere la destrucción física y los avisos hasta cerrar el ámbito exterior mientras marca `isValid == false` al instante) y `graph.isAncestor(_:of:)`.
   - Se añadieron 23 escenarios directos a `NativeProbe` (total **31 escenarios C1–C32**), incluyendo dos oráculos de grafos aleatorios comparados paso a paso contra el `AttributeGraph` de Apple, `breadthFirstSearch(from:options:_:)` con `SearchOptions` y `@dynamicMemberLookup` / `subscript(keyPath:)` en `Attribute<Value>`.

**Validación y medidas (Mac M1, Swift 6.2.4):**
- **`NativeProbe`:** **31 escenarios directos** (3 pares debug + 3 pares release = 12 procesos) coinciden al **100 %** entre `AttributeGraph.framework` nativo de macOS 15.7.9 y `SwiftAttributeGraph`.
- **Tests funcionales:** **228 pruebas en 26 suites** pasan en depuración y **227 pruebas** en release con **0 *known issues*** (se resolvieron también los 2 *known issues* de M2 para `enum` con carga no `Equatable`, comparando caso activo y payload con las reglas del modo).
- **Rendimiento en release (18 pruebas en 3 suites en verde):**
  - Regla de 20.000 entradas que pierde la mitad: **4,85 ms** (frente a 76,83 ms antes de la Pieza 1: **15,8× más rápido**).
  - Presupuesto M4 (50 ciclos × 1.000 reglas reanudables frente a síncronas): **33,20 ms / 36,56 ms = 0,908** (≤ 1,30).
  - 20.000 indirectos en cadena (escritura + lectura): **1,94 ms**.
  - Cadena fría de 100.000 reglas reanudables en hilo con pila de 512 KB: **76,20 ms** (20.000 reglas: **15,38 ms**).
  - Borrado de la mitad de 100.000 salidas en un nodo común: **169,89 ms**.
  - `StressBenchmark` (10.000 componentes, 60 frames con 500 mutaciones/frame): media **0,524 ms**, p50 **0,513 ms**, p95 **0,650 ms**, máx/p99 **0,654 ms** (≤ 1,6 ms); fan-out 50.000 lectores: propagación **0,477 ms**, recálculo **17,052 ms**; churn 10.000 subgrafos (30.000 atributos): creación **6,75 ms**, invalidación **7,64 ms**, **0 nodos residuales**.

## 26. Casos límite combinados en `NativeProbe` y orden de avisos de subgrafo (Mac)

Fecha: 2026-11-15. Mac M1, macOS 15.7.9, Swift 6.2.4 (Xcode).

**Hecho (4 escenarios nuevos en `NativeProbe` — total 54 trazas directas):**
1. **`indirect-reset-source-multi-redirect`:** tras encadenar `A -> B -> C`, `AGGraphResetIndirectAttribute` / `resetSource` vuelve al origen inicial `A` (no al previo `B`). Coincide.
2. **`indirect-chain-and-intermediate-death`:** cadena `ind2 -> ind1 -> source` con `.dependency`; redirigir `ind1` a otro origen distinto con el mismo valor reevalúa al lector; invalidar el subgrafo del origen intermedio `c` deja al lector con el último valor sin reevaluarlo. Coincide.
3. **`changed-value-after-skipped-and-indirect`:** volver a leer un atributo podado tras mutar su valor y restaurarlo reporta `changed == true`; `changedValue(of:)` sobre un `IndirectAttribute` redirigido a otro atributo con el mismo valor numérico también reporta `changed == true` hasta la siguiente evaluación estable (`false`). Coincide.
4. **`multi-observer-tree-order-and-cancel`:** el `AttributeGraph.framework` nativo notifica primero al subgrafo padre y después a los hijos en **orden inverso de creación** (preorden con hijos invertidos: `parent -> child2 -> child1 -> grand1`), idéntico al recorrido ya usado por `Subgraph.forEach` / `update(flags:)`. Cancelar un observador de un subgrafo hijo desde el padre lo cancela antes de ejecutarse, mientras que cancelar un observador hermano del mismo subgrafo desde su observador previo no impide que el hermano siga ejecutándose en la instantánea actual.
   - Se alineó `Graph+Invalidation.swift` (`for index in order.reversed()`) y su documentación DocC; se actualizaron los tres tests M5 que asumían el antiguo posorden (`SubgraphTests`, `ResumableRuleTests`, `BranchParityTests`) y se añadieron cuatro pruebas espejo en `ParityTests.swift`.

**Validación y límites:**
- **`NativeProbe`:** **54 trazas directas** (3 pares debug + 3 pares release = 12 procesos) coinciden al **100 %**. Para invocar `resetSource` en el `AttributeGraph.framework` nativo desde `NativeProbe/Sources/Probe/main.swift` se usa `AGGraphResetIndirectAttribute(_ attribute: AnyAttribute)` porque `IndirectAttribute.resetSource()` está en `.tbd` pero omitido de `.swiftinterface`.
- **Tests funcionales:** **257 pruebas en 29 suites** en verde con `swift test` en depuración tras el cambio final. No se reejecutaron las mediciones de rendimiento en `release` (el cambio en `Graph+Invalidation.swift` solo sustituye la iteración `order` por `order.reversed()`, de coste O(1)).

## Adaptaciones nativas (rama aislada `codex/native-adaptations-integration`)

- **Comparación parcial en arista sobre cadenas de indirectos (release):** `PERF 20 writes over 20k indirect chain with partial comparator: 16.19 ms` (`0.016188292 s`).
- **Indirectos con offset `(offset, size)` en arista (release):** `PERF 20 writes over 20k offset-indirect chain: 16.08 ms` (`0.016078041 s`).
- **Optimización `hasOffsetInChain` $O(1)$ (`indirectsWithOffsetInChain`):** `IndirectPerformanceTests` (`20,000 indirects, write + read`) bajó de **67,326.73 ms** (`0eacd92`) a **4.37 ms** en `release`; `20 writes over 20k offset-indirect chain` en **19.51 ms**.

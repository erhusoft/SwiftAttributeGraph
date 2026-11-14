# Plan del motor SwiftAttributeGraph

Fecha: 2026-11-14. **Fuente de verdad del estado.** Nada está implementado todavía salvo el esqueleto del paquete.
Hecho hasta ahora: fundamentos, preguntas previas ([PREGUNTAS.md](PREGUNTAS.md)), medición de paridad con SwiftUI real
y la nota de diseño de M0 ([DISENO-M0.md](DISENO-M0.md), propuesta pendiente de aprobación).

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
| M2 | **Políticas de comparación por atributo** | Tres políticas resueltas una vez al crear el atributo, según el tipo: `viewValue` (todos los bytes), `environment` (bits **o** `==`), `stateWrite` (trivial: bits **y** `==`; `Equatable` no trivial: `==`; resto: bits). SwiftUI **no** usa `==` para el valor de una vista (medido) | Cada política reproduce las filas medidas en SwiftUI real; sin `as? any Equatable` en el camino caliente; medida de escrituras y del relleno entre campos | 🔴 |
| M3 | **Reglas con estado** | Acceso al valor anterior y a qué entradas cambiaron (equivalente a `StatefulRule` y `anyInputsChanged`) | Tests de una regla que acumula y de una que solo reacciona a una entrada concreta | 🔴 |
| M4 | **Actualización sin recursión total** | Las lecturas dinámicas dentro de una regla tampoco usan la pila nativa; reentrada (actualización anidada) | Cadena de 20.000 lecturas dinámicas no declaradas sin desbordar; test de reentrada | 🔴 |
| M5 | **Subgrafos** | Jerarquía padre-hijo; los atributos nacen en el subgrafo actual; invalidar un subgrafo libera todo lo suyo; diferido si hay una actualización en curso | `nodeCount` vuelve a la base; invalidar durante una actualización no rompe la actualización | 🔴 |
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
- Borrar una arista cuesta O(grado) (M7). Invalidar durante una actualización no está permitido (M5).
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

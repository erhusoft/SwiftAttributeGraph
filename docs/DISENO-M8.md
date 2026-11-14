# Diseño M8: herramientas (volcado, contadores, memoria)

Fecha: 2026-11-14. Parte de [PLAN-MOTOR.md](PLAN-MOTOR.md) §3 (M8). **Estado: implementado** (código y tests; las
medidas de rendimiento se validan en Mac M1, Swift 6.2.4).

## 1. Alcance

M8 añade herramientas de depuración e introspección sobre el grafo, sin tocar el camino caliente:

| Capacidad | API |
|-----------|-----|
| Contadores de aristas por nodo | `inputCount(of:)`, `outputCount(of:)` |
| Contador total de aristas | `edgeCount` |
| Contador de recálculos de reglas | `recalculationCount` |
| Volcado de texto de todo el grafo | `dump()` |
| Estimación de uso de memoria | `estimatedMemoryFootprint` |

## 2. Contador de recálculos

`Graph.recalculationCount` es una propiedad almacenada en `Graph` (`var recalculationCount = 0`). Se incrementa:

- En `Graph.run` (regla síncrona): cada vez que se ejecuta la regla de un nodo.
- En `Graph.advanceResumable` (regla reanudable): cuando el paso termina con `.finished`.

No se incrementa al leer un valor ya en caché (corte por versión), solo cuando una regla realmente corre.

## 3. Volcado (`dump()`)

`Graph.dump()` devuelve un `String` con una línea por atributo vivo, incluyendo índice, generación, versión, tipo
(`input`/`rule`/`indirect`), estado (`dirty`, `hasValue`), subgrafo propietario, aristas de entrada y aristas de salida.

Es O(nodos + aristas) y solo para depuración; no está en el camino caliente.

## 4. Estimación de memoria

`Graph.estimatedMemoryFootprint` suma el tamaño de los arrays paralelos de `NodeTable` y `SubgraphTable`
(generations, state, versions, lastVerified, owners, boxes, freeList, inputs, outputs, y los arrays equivalentes de
`SubgraphTable`), en bytes. Trata cada `NodeBox` como un objeto de referencia de tamaño desconocido, así que es una
estimación útil para detectar regresiones, no para contabilidad exacta.

## 5. Tests (`Tests/…/Unit/IntrospectionTests.swift`)

1. `inputCount`/`outputCount` devuelven los conteos correctos tras leer reglas.
2. `edgeCount` es la suma de todas las entradas.
3. `edgeCount` disminuye tras podar aristas (lectura condicional).
4. `recalculationCount` incrementa al ejecutar reglas, no al leer en caché, y cuenta cada regla independiente.
5. `dump` lista los atributos vivos y distingue `input` de `rule`.
6. `estimatedMemoryFootprint` es positivo y crece al crear más nodos y aristas.

## 6. Archivos tocados

- `Debug/Graph+Introspection.swift`: `inputCount(of:)`, `outputCount(of:)`, `edgeCount`, `recalculationCount`,
  `dump()`, `estimatedMemoryFootprint`.
- `Graph/Graph.swift`: `recalculationCount` propiedad almacenada.
- `Storage/NodeTable.swift`: `freeListCount`.
- `Subgraph/SubgraphTable.swift`: `freeListCount`.
- `Update/Graph+Update.swift`: incrementa `recalculationCount` en `run`; `box(at:)` con `UInt32` en `setValue`
  indirecto.
- `Update/Graph+ResumableUpdate.swift`: incrementa `recalculationCount` en `.finished`.

## 7. Límites

- `estimatedMemoryFootprint` no incluye el tamaño real de los `NodeBox` (valores, cierres, reglas), solo los arrays
  paralelos y una referencia por box.
- `dump()` no es Graphviz; es texto plano. Graphviz se puede añadir después si la UI lo necesita.
- No hay contadores de notificaciones ni de observaciones todavía.
